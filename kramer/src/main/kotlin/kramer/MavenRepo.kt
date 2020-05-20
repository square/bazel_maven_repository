package kramer

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.ProgramResult
import com.github.ajalt.clikt.core.requireObject
import com.github.ajalt.clikt.parameters.options.default
import com.github.ajalt.clikt.parameters.options.defaultLazy
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.options.required
import com.github.ajalt.clikt.parameters.types.int
import com.github.ajalt.clikt.parameters.types.path
import com.squareup.tools.maven.resolution.ArtifactResolver
import com.squareup.tools.maven.resolution.FetchStatus
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.SUCCESSFUL
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.SUCCESSFUL.FOUND_IN_CACHE
import com.squareup.tools.maven.resolution.Repositories
import com.squareup.tools.maven.resolution.ResolvedArtifact
import java.io.IOException
import java.net.URI
import java.nio.file.FileSystem
import java.nio.file.FileSystems
import java.nio.file.Files
import java.nio.file.Path
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.system.measureTimeMillis
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.asFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.filterNot
import kotlinx.coroutines.flow.flatMapMerge
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking

class MavenRepo(fs: FileSystem = FileSystems.getDefault()) : CliktCommand(name = "gen-maven-repo") {
  private val workspace: Path by option(
    "--workspace",
    help = "Path to the workspace to be generated."
  )
    .path(canBeFile = false, canBeSymlink = false, canBeDir = true)
    .default(fs.getPath("${System.getProperties()["java.io.tmpdir"]}", "bazel/maven"))

  /** Name of the workspace - nearly always the nearest directory name of the workspace path */
  private val workspaceName: String by option("--workspace-name")
    .defaultLazy { workspace.fileName.toString() }

  private val configFile by option("--configuration").path(mustExist = true).required()

  private val threadCount: Int by option("--threads").int().default(1)

  internal val kontext by requireObject<Kontext>()

  internal data class IndexEntry(
    val dependants: MutableSet<String> = Collections.newSetFromMap(ConcurrentHashMap()),
    val versions: MutableSet<String> = Collections.newSetFromMap(ConcurrentHashMap())
  )

  @FlowPreview
  @ExperimentalCoroutinesApi
  override fun run() {
    val repoConfig = parseRepoConfig(configFile)
    val count = AtomicInteger(0)
    var exit = 0
    val seen = ConcurrentHashMap<String, IndexEntry>()
    val unresolved = Collections.newSetFromMap(ConcurrentHashMap<String, Boolean>())
    val declaredArtifactSlugs = Collections.newSetFromMap(ConcurrentHashMap<String, Boolean>())
    val benchmark = measureTimeMillis {
      if (repoConfig.artifacts.isNotEmpty()) Files.createDirectories(workspace)
      runBlocking {
        kontext.out(false) { "Building workspace for ${repoConfig.artifacts.size} artifacts" }
        kontext.out { if (kontext.verbosity > 1) "using $threadCount threads." else "." }
        repoConfig.artifacts.entries.asFlow()
          .onEach {
            // TODO: Validate per-artifact configuration.
          }
          .flatMapMerge(concurrency = threadCount) { (artifact_spec, config) ->
            flow {
              val resolver = ArtifactResolver(
                cacheDir = kontext.localRepository,
                suppressAddRepositoryWarnings = true,
                repositories =
                if (kontext.repositories.isNotEmpty()) kontext.repositories
                else Repositories.DEFAULT
              )
              val artifact = resolver.artifactFor(artifact_spec)
              val slug = "${artifact.groupId}:${artifact.artifactId}"
              val entry = seen.getOrPut(slug) { IndexEntry() }
              entry.versions.add(artifact.version)
              declaredArtifactSlugs.add(slug)
              var resolved: ResolvedArtifact? = null
              val time = measureTimeMillis {
                resolved = resolver.resolveArtifact(artifact)
              }
              if (resolved != null) with (resolved!!.model) {
                kontext.info { "Resolved ${artifact.coordinate} in ${time / 1000.0} seconds" }
                kontext.verbose {
                  dependencies.filter { it.scope != "test" }
                    .joinToString("\n") { dep ->
                      "  - ${dep.groupId}:${dep.artifactId}:${dep.version} - ${dep.scope}" +
                        if (dep.exclusions.isNotEmpty()) {
                          "\n    exclusions = ${dep.exclusions.forEach { ex -> ex.toString() }}"
                        } else ""
                    }
                }
              } else {
                unresolved.add(artifact.coordinate)
              }
              emit(resolved to resolver tre config)
            }
          }
          .filterNot { (resolved) -> resolved == null }
          .flatMapMerge(concurrency = threadCount) { (resolved, resolver, config) ->
            resolved!! // Smart cast to not null
            flow {
              if (resolved.model.packaging == "aar") {
                var status: FetchStatus? = null
                val time = measureTimeMillis {
                  status = resolver.downloadArtifact(resolved)
                }
                when (status) {
                  is SUCCESSFUL -> {
                    val cache = if (status is FOUND_IN_CACHE) " from cache" else ""
                    kontext.info {
                      "Downloaded ${resolved.main.localFile} $cache in ${time / 1000.0} seconds"
                    }
                    kontext.verbose {
                      "Extracting package metadatata from ${resolved.main.localFile}"
                    }
                    val androidPackage: String?
                    try {
                      if (Files.exists(resolved.main.localFile)) {
                        val uri = URI.create("jar:" + resolved.main.localFile.toUri())
                        androidPackage = extractPackageFromManifest(uri)
                        if (androidPackage == null)
                          kontext.info { "WARNING: Null package for ${resolved.coordinate}" }
                        count.incrementAndGet()
                        emit(resolved to config tre androidPackage)
                      } else exit = 1
                    } catch (e: IOException) {
                      kontext.out { "Failed to find android manifest for ${resolved.coordinate}" }
                      exit = 1
                    }
                  }
                  else -> {
                    kontext.out { "Failed to download ${resolved.coordinate}." }
                    exit = 1
                  }
                }
              } else {
                count.incrementAndGet()
                emit(resolved to config tre null)
              }
            }
          }
          .map { (resolved, config, customPackage) ->
            val jetify = if (repoConfig.useJetifier) "\n    jetify = True," else ""
            val visibility = "[\"//visibility:public\"]" // TODO configurable.
            val testonly = if (config.testonly) "\n    testonly = True," else ""
            val deps = prepareDependencies(resolved, config, seen, repoConfig)
              .joinToString("") { d -> "        \"$d\",\n" }
              .let { if (it.isNotBlank()) "\n$it    " else it }

            // If we have a build snippet, use that, else use the appropriate template for the type.
            val content = config.snippet ?: when (resolved.model.packaging.trim()) {
              "aar" -> aar_template(
                target = resolved.target,
                coordinate = resolved.coordinate,
                customPackage = customPackage ?: "UNKNOWN", // Error, but should show up clearly.
                jetify = jetify,
                deps = deps,
                fetchRepo = resolved.fetchRepoPackage(),
                testonly = testonly,
                visibility = visibility
              )
              else -> jar_template(
                target = resolved.target,
                coordinate = resolved.coordinate,
                jarPath = "${resolved.main.path}",
                jetify = jetify,
                deps = deps,
                fetchRepo = resolved.fetchRepoPackage(),
                testonly = testonly,
                visibility = visibility
              )
            }
            val path = workspace.resolve(resolved.groupPath).resolve("BUILD.bazel")
            path to (content to (resolved.model.packaging.trim() == "aar"))
          }
          .flowOn(Dispatchers.IO)
          .toList() // Collector
          .toImmutableListMultimap()
          .also {
            kontext.out { "Writing ${it.keySet().size} build files into $workspace" }
          }
          .asMap()
          .entries
          .asFlow()
          .flatMapMerge(concurrency = threadCount) { (path, snippets) ->
            flow {
              val android = snippets.map { it.second }.reduce { b, acc -> b || acc }
              val androidHeader = if (android) ANDROID_LOAD_HEADER else ""
              val mavenRulesRepo = "maven_repository_rules"
              val content = snippets.joinToString(
                  "\n",
                  prefix = HEADER + androidHeader + RAW_LOAD_HEADER_TEMPLATE.format(mavenRulesRepo)
                ) { it.first }
              Files.createDirectories(path.parent)
              Files.write(path, content.lines())
              emit(path to snippets)
            }
          }
          .collect()

        // Check for, and handle, any errors or mis-specifications.
        if (declaredArtifactSlugs.size != repoConfig.artifacts.size) {
          exit = 1
          handleDuplicateArtifacts(repoConfig)
        }
        if (unresolved.isNotEmpty()) {
          exit = 1
          handleUnresolvedArtifacts(unresolved)
        }
        with(seen.filterKeys { it !in declaredArtifactSlugs }) {
          if (isNotEmpty()) {
            exit = 1
            handleMissingArtifacts(this)
          }
        }
      }
    }
    kontext.out {
      "Resolved $count artifacts with $threadCount threads in ${benchmark / 1000.0} seconds"
    }
    if (exit != 0) throw ProgramResult(exit)
  }
}

/**
 * For a given resolved artifact, prepare the list of its dependencies, excluding unused scopes,
 * explicitly excluded deps, and fixing and formatting.
 */
private fun prepareDependencies(
  resolved: ResolvedArtifact,
  config: ArtifactConfig,
  seen: ConcurrentHashMap<String, MavenRepo.IndexEntry>,
  repoConfig: RepoConfig
): Sequence<String> {
  val substitutes = repoConfig.targetSubstitutes.getOrElse(resolved.groupId) { mapOf() }
  return resolved.model.dependencies.asSequence()
    .filter { dep -> dep.scope in acceptedScopes }
    .filter { dep -> "${dep.groupId}:${dep.artifactId}" !in config.exclude }
    .onEach { dep ->
      // Cache for later validation
      val entry = seen.getOrPut("${dep.groupId}:${dep.artifactId}") { MavenRepo.IndexEntry() }
      entry.versions.add(dep.version)
      entry.dependants.add(resolved.coordinate)
    }
    .map { dep ->
      val bazelPackage = "@${repoConfig.name}//${dep.groupPath}"
      val leafPackage = bazelPackage.split("/").last()
      val prefix = "$bazelPackage:"
      "$prefix${dep.target}"
        .let { d ->
          substitutes.getOrElse(d) { d }
        }
        .let { d ->
          when {
            resolved.groupId == dep.groupId -> d.removePrefix(bazelPackage)
            leafPackage == dep.target -> bazelPackage
            else -> d
          }
        }
    }
    .sorted()
}
