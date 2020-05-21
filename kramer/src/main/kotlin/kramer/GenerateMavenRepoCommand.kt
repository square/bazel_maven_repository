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
import kotlin.collections.Map.Entry
import kotlin.system.measureTimeMillis
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.asFlow
import kotlinx.coroutines.flow.count
import kotlinx.coroutines.flow.flatMapMerge
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kramer.GenerateMavenRepo.ArtifactResolution.AarArtifactResolution
import kramer.GenerateMavenRepo.ArtifactResolution.SimpleArtifactResolution

class GenerateMavenRepo(
  fs: FileSystem = FileSystems.getDefault()
) : CliktCommand(name = "gen-maven-repo") {
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

  /**
   * Represents the outcome of an artifact resolution processing step. It has a simple and
   * android representation (which adds an android custom package)
   */
  internal sealed class ArtifactResolution {
    abstract val resolved: ResolvedArtifact
    abstract val config: ArtifactConfig
    abstract operator fun component1(): ResolvedArtifact
    abstract operator fun component2(): ArtifactConfig

    internal data class SimpleArtifactResolution(
      override val resolved: ResolvedArtifact,
      override val config: ArtifactConfig
    ) : ArtifactResolution()

    internal data class AarArtifactResolution(
      override val resolved: ResolvedArtifact,
      override val config: ArtifactConfig,
      var androidPackage: String
    ) : ArtifactResolution()
  }

  internal data class TemplateApplication(
    val resolution: ArtifactResolution,
    val content: String
  )

  @FlowPreview
  @ExperimentalCoroutinesApi
  override fun run() {
    val repoConfig = parseRepoConfig(configFile)
    val count = AtomicInteger(0)
    var exit = AtomicInteger(0)
    val seen = ConcurrentHashMap<String, IndexEntry>()
    val unresolved = Collections.newSetFromMap(ConcurrentHashMap<String, Boolean>())
    val declaredArtifactSlugs = Collections.newSetFromMap(ConcurrentHashMap<String, Boolean>())
    val benchmark = measureTimeMillis {
      if (repoConfig.artifacts.isNotEmpty()) Files.createDirectories(workspace)
      runBlocking {
        kontext.out(false) { "Building workspace for ${repoConfig.artifacts.size} artifacts" }
        kontext.out { if (kontext.verbosity > 1) "using $threadCount threads." else "." }
        val f = repoConfig.artifacts.entries.asFlow()
          .onEach {
            // TODO: Validate per-artifact configuration (currently validated in starlark).
          }
          .flatMapMerge(threadCount) { (artifact_spec, config) ->
            resolvePomFlow(artifact_spec, seen, declaredArtifactSlugs, unresolved, config, exit)
          }
          .flatMapMerge(threadCount) { result -> extractAarPackageFlow(result, count, exit) }
          .map { resolution -> applyTemplate(resolution, repoConfig, seen) }
          .flowOn(Dispatchers.IO)
          .toListMultimapFlow() // Associate template operations with their build file
          .flatMapMerge(threadCount) { (path, filledTemplates) ->
            flow { emit(writeBuildFiles(path, filledTemplates)) }
          }
          .count()
          .let { kontext.out { "Generated $it build files in $workspace" } }

        // Check for, and handle, any errors or mis-specifications.
        if (declaredArtifactSlugs.size != repoConfig.artifacts.size) {
          exit.set(1)
          handleDuplicateArtifacts(repoConfig)
        }
        if (unresolved.isNotEmpty()) {
          exit.set(1)
          handleUnresolvedArtifacts(unresolved)
        }
        with(seen.filterKeys { it !in declaredArtifactSlugs }) {
          if (isNotEmpty()) {
            exit.set(1)
            handleMissingArtifacts(this)
          }
        }
      }
    }
    kontext.out {
      "Resolved $count artifacts with $threadCount threads in ${benchmark / 1000.0} seconds"
    }
    exit.get().let { status -> if (status != 0) throw ProgramResult(status) }
  }

  private fun writeBuildFiles(
    path: Path,
    templateApplications: Collection<TemplateApplication>
  ): Path {
    val android =
      templateApplications.map { it.resolution is AarArtifactResolution }
        .reduce { b, acc -> b || acc }
    val androidHeader = if (android) ANDROID_LOAD_HEADER else ""
    val mavenRulesRepo = "maven_repository_rules"
    val content = templateApplications.joinToString(
      "\n",
      prefix = HEADER + androidHeader + RAW_LOAD_HEADER_TEMPLATE.format(mavenRulesRepo)
    ) { it.content }
    Files.createDirectories(path.parent)
    Files.write(path, content.lines())
    return path
  }

  private fun applyTemplate(
    resolution: ArtifactResolution,
    repoConfig: RepoConfig,
    seen: ConcurrentHashMap<String, IndexEntry>
  ): Pair<Path, TemplateApplication> {
    val (resolved, config) = resolution
    val jetify = if (repoConfig.useJetifier) "\n    jetify = True," else ""
    val visibility = "[\"//visibility:public\"]" // TODO configurable.
    val testonly = if (config.testonly) "\n    testonly = True," else ""
    val deps = prepareDependencies(resolved, config, seen, repoConfig)
      .joinToString("") { d -> "        \"$d\",\n" }
      .let { if (it.isNotBlank()) "\n$it    " else it }

    // If we have a build snippet, use that, else use the appropriate template for the type.
    val content = config.snippet ?: when (resolution) {
      is AarArtifactResolution -> aarTemplate(
        target = resolved.target,
        coordinate = resolved.coordinate,
        customPackage = resolution.androidPackage,
        jetify = jetify,
        deps = deps,
        fetchRepo = resolved.fetchRepoPackage(),
        testonly = testonly,
        visibility = visibility
      )
      else -> jarTemplate(
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
    return path to TemplateApplication(resolution, content)
  }

  private fun extractAarPackageFlow(
    resolution: SimpleArtifactResolution,
    count: AtomicInteger,
    exit: AtomicInteger
  ): Flow<ArtifactResolution> {
    return flow {
      val (resolved, config) = resolution
      val resolver = newResolver()
      if (resolved.model.packaging == "aar") {
        var status: FetchStatus? = null
        val time = measureTimeMillis {
          status = resolver.downloadArtifact(resolved)
        }
        when (status) {
          is SUCCESSFUL -> {
            kontext.info {
              val cache = if (status is FOUND_IN_CACHE) " from cache" else ""
              "Downloaded ${resolved.main.localFile} $cache in ${time / 1000.0} seconds"
            }
            kontext.verbose { "Extracting package metadatata from ${resolved.main.localFile}" }
            val androidPackage: String?
            try {
              if (Files.exists(resolved.main.localFile)) {
                val uri = URI.create("jar:" + resolved.main.localFile.toUri())
                extractPackageFromManifest(uri)?.let { customPackage ->
                  count.incrementAndGet()
                  emit(AarArtifactResolution(resolution.resolved, resolution.config, customPackage))
                } ?: run {
                  kontext.info { "WARNING: Null package for ${resolved.coordinate}" }
                  exit.set(1)
                }
              } else exit.set(1)
            } catch (e: IOException) {
              kontext.out { "Failed to find android manifest for ${resolved.coordinate}" }
              exit.set(1)
            }
          }
          else -> {
            kontext.out { "Failed to download ${resolved.coordinate}." }
            exit.set(1)
          }
        }
      } else {
        count.incrementAndGet()
        emit(resolution)
      }
    }
  }

  /**
   * Returns a flow that (lazily) produces [ArtifactResolution] objects IF the pom could be
   * resolved. The [ResolvedArtifact] (crucially with it's maven [org.apache.maven.model.Model]),
   * along with its [ArtifactConfig] are sent down the pipeline.
   *
   * If the flow cannot be resolved, this function simply omits that artifact from further
   * downstream pipeline processing steps.
   *
   * As side-effects, it gathers unresolved artifacts, declared artifacts, etc. for bookkeeping
   * and later error bulk processing.
   */
  private fun resolvePomFlow(
    artifact_spec: String,
    seen: ConcurrentHashMap<String, IndexEntry>,
    declaredArtifactSlugs: MutableSet<String>,
    unresolved: MutableSet<String>,
    config: ArtifactConfig,
    exit: AtomicInteger
  ): Flow<SimpleArtifactResolution> {
    return flow {
      val resolver = newResolver()
      val artifact = resolver.artifactFor(artifact_spec)
      val slug = "${artifact.groupId}:${artifact.artifactId}"
      val entry = seen.getOrPut(slug) { IndexEntry() }
      entry.versions.add(artifact.version)
      declaredArtifactSlugs.add(slug)
      var resolved: ResolvedArtifact? = null
      val time = measureTimeMillis {
        resolved = resolver.resolveArtifact(artifact)
      }
      resolved?.let {
        kontext.info { "Resolved ${it.coordinate} in ${time / 1000.0} seconds" }
        emit(SimpleArtifactResolution(it, config))
      } ?: run {
        unresolved.add(artifact.coordinate)
        exit.set(1)
      }
    }
  }

  private fun newResolver(): ArtifactResolver {
    return ArtifactResolver(
      cacheDir = kontext.localRepository,
      suppressAddRepositoryWarnings = true,
      repositories =
      if (kontext.repositories.isNotEmpty()) kontext.repositories
      else Repositories.DEFAULT
    )
  }
}

/**
 * Takes key-value pairs (`Pair<A, B>`) performs a collection/indexing on them, and emits the
 * indexed values as a `Pair<A, Collection<B>>` (essentially a list-multimap flow)
 */
private suspend fun <A, B> Flow<Pair<A, B>>.toListMultimapFlow(): Flow<Entry<A, Collection<B>>> {
  return (this
    .toList() // Collector
    .toImmutableListMultimap() // Associate snippets to their build file.
    .asMap() as Map<A, Collection<B>>)
    .entries
    .asFlow()
}

/**
 * For a given resolved artifact, prepare the list of its dependencies, excluding unused scopes,
 * explicitly excluded deps, and fixing and formatting.
 */
private fun prepareDependencies(
  resolved: ResolvedArtifact,
  config: ArtifactConfig,
  seen: ConcurrentHashMap<String, GenerateMavenRepo.IndexEntry>,
  repoConfig: RepoConfig
): Sequence<String> {
  if (!config.snippet.isNullOrBlank()) return sequenceOf()
  val substitutes =
    repoConfig.targetSubstitutes.getOrElse(resolved.groupId) { mapOf() }
  return resolved.model.dependencies.asSequence()
    .filter { dep -> dep.scope in acceptedScopes }
    .filter { dep -> "${dep.groupId}:${dep.artifactId}" !in config.exclude }
    .onEach { dep ->
      // Cache for later validation
      val entry =
        seen.getOrPut("${dep.groupId}:${dep.artifactId}") { GenerateMavenRepo.IndexEntry() }
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
