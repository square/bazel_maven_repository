/*
 * Copyright (C) 2020 Square, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License
 * is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
 * or implied. See the License for the specific language governing permissions and limitations under
 * the License.
 *
 */
package kramer

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.ProgramResult
import com.github.ajalt.clikt.core.requireObject
import com.github.ajalt.clikt.parameters.options.default
import com.github.ajalt.clikt.parameters.options.defaultLazy
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.options.required
import com.github.ajalt.clikt.parameters.types.enum
import com.github.ajalt.clikt.parameters.types.int
import com.github.ajalt.clikt.parameters.types.path
import com.squareup.tools.maven.resolution.ArtifactResolver
import com.squareup.tools.maven.resolution.FetchStatus
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.FETCH_ERROR
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.SUCCESSFUL
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.SUCCESSFUL.FOUND_IN_CACHE
import com.squareup.tools.maven.resolution.Repositories.Companion.DEFAULT
import com.squareup.tools.maven.resolution.ResolutionResult
import com.squareup.tools.maven.resolution.ResolvedArtifact
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
import kramer.GenerateMavenRepo.ArtifactResolution.FileArtifactResolution
import kramer.GenerateMavenRepo.ArtifactResolution.JarArtifactResolution
import org.apache.maven.model.Dependency
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

class GenerateMavenRepo(
  fs: FileSystem = FileSystems.getDefault()
) : CliktCommand(name = "gen-maven-repo") {
  internal val workspace: Path by option(
    "--workspace",
    help = "Path to the workspace to be generated."
  )
    .path(canBeFile = false, canBeSymlink = false, canBeDir = true)
    .default(fs.getPath("${System.getProperties()["java.io.tmpdir"]}", "bazel/maven"))

  /** Name of the workspace - nearly always the nearest directory name of the workspace path */
  private val workspaceName: String by option("--workspace-name")
    .defaultLazy { workspace.fileName.toString() }

  private val specificationFile by option("--specification").path(mustExist = true).required()

  private val threadCount: Int by option("--threads").int()
    .default(1)

  private val unknownPackagingStrategy: UnknownPackagingStrategy by option(
    "--unknown-packaging"
  )
    .enum<UnknownPackagingStrategy>()
    .default(UnknownPackagingStrategy.WARN)

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

    internal data class JarArtifactResolution(
      override val resolved: ResolvedArtifact,
      override val config: ArtifactConfig
    ) : ArtifactResolution()

    internal data class AarArtifactResolution(
      override val resolved: ResolvedArtifact,
      override val config: ArtifactConfig,
      var androidPackage: String,
      var libs: List<Path>
    ) : ArtifactResolution()

    internal data class FileArtifactResolution(
      override val resolved: ResolvedArtifact,
      override val config: ArtifactConfig
    ) : ArtifactResolution()
  }

  internal data class TemplateApplication(
    val resolution: ArtifactResolution,
    val content: String
  )

  @FlowPreview
  @ExperimentalCoroutinesApi
  override fun run() {
    val repoSpec = kontext.parseJson(specificationFile, RepositorySpecification::class)
    with(repoSpec.validate()) {
      if (isNotEmpty()) {
        forEach { kontext.out { "ERROR: Invalid config: ${it.message}" } }
        throw ProgramResult(1)
      }
    }
    val count = AtomicInteger(0)
    val exit = AtomicInteger(0)
    val seen = ConcurrentHashMap<String, IndexEntry>()
    val unresolved = Collections.newSetFromMap(ConcurrentHashMap<String, Boolean>())
    val declaredArtifactSlugs = Collections.newSetFromMap(ConcurrentHashMap<String, Boolean>())
    val resolutions = Collections.newSetFromMap(ConcurrentHashMap<ArtifactResolution, Boolean>())
    val benchmark = measureTimeMillis {
      if (repoSpec.artifacts.isNotEmpty()) Files.createDirectories(workspace)
      runBlocking {
        kontext.out { "Building workspace for ${repoSpec.artifacts.size} artifacts" }
        repoSpec.artifacts.entries.asFlow()
          .onEach {
            // TODO: Validate per-artifact configuration (currently validated in starlark).
          }
          .flatMapMerge(threadCount) { (artifact_spec, config) ->
            resolvePomFlow(artifact_spec, seen, declaredArtifactSlugs, unresolved, config, exit)
          }
          .flatMapMerge(threadCount) { result ->
            count.incrementAndGet()
            when (result.resolved.model.packaging) {
              "jar" -> packageJarFlow(result)
              "bundle" -> packageJarFlow(result)
              "aar" -> extractAarPackageFlow(result, exit)
              else -> unknownPackageFlow(result, exit)
            }
          }
          .onEach { resolution -> resolutions.add(resolution) /* Store for aliases */ }
          .map { resolution -> applyTemplate(resolution, repoSpec, seen) }
          .flowOn(Dispatchers.IO)
          .toListMultimapFlow() // Associate template operations with their build file
          .flatMapMerge(threadCount) { (path, filledTemplates) ->
            flow { emit(writeBuildFiles(path, filledTemplates, repoSpec.rulesLabel)) }
          }
          .count()
          .let { kontext.out { "Generated $it build files in $workspace" } }

        // Check for, and handle, any errors or mis-specifications.
        if (declaredArtifactSlugs.size != repoSpec.artifacts.size) {
          exit.set(1)
          handleDuplicateArtifacts(repoSpec)
        }
        if (unresolved.isNotEmpty()) {
          exit.set(1)
          handleUnresolvedArtifacts(unresolved)
        }
        if (repoSpec.useJetifier && !repoSpec.ignoreLegacyAndroidSupportArtifacts) {
          with(declaredArtifactSlugs.intersect(JETIFIER_ARTIFACT_MAPPING.keys)) {
            if (isNotEmpty()) {
              exit.set(1)
              handlePreAndroidXArtifacts(this)
            }
          }
        }
        with(seen.filterKeys { it !in declaredArtifactSlugs }) {
          if (isNotEmpty()) {
            exit.set(1)
            handleMissingArtifacts(this)
          }
        }
        if (repoSpec.generateRulesJvmCompatabilityTargets) {
          val content = generateRulesJvmCompatibilityTargets(repoSpec, resolutions)
          val path = workspace.resolve("BUILD.bazel")
          Files.write(path, content.lines())
          kontext.out { "Generated root compatibility build file in $workspace" }
        }
      }
    }
    kontext.out {
      "Resolved $count artifacts with $threadCount threads in ${benchmark / 1000.0} seconds"
    }
    kontext.out { if (kontext.verbosity > 1) "using $threadCount threads." else "." }
    exit.get()
      .let { status -> if (status != 0) throw ProgramResult(status) }
  }

  private fun writeBuildFiles(
    path: Path,
    templateApplications: Collection<TemplateApplication>,
    mavenRulesRepo: String
  ): Path {
    val android =
      templateApplications.map { it.resolution is AarArtifactResolution }
        .reduce { b, acc -> b || acc }
    val androidHeader = if (android) ANDROID_LOAD_HEADER else ""
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
    repoConfig: RepositorySpecification,
    seen: ConcurrentHashMap<String, IndexEntry>
  ): Pair<Path, TemplateApplication> {
    val (resolved, config) = resolution
    val shouldUseJetifier =
      repoConfig.useJetifier && !repoConfig.jetifierMatcher.matches(resolved)
    val jetify = if (shouldUseJetifier) "\n    jetify = True," else ""
    val visibility = "[\"//visibility:public\"]" // TODO configurable.
    val testonly = if (config.testonly) "\n    testonly = True," else ""
    val deps = prepareDependencies(resolved, config, seen, repoConfig)
      .joinToString("") { d -> "        \"$d\",\n" }
      .let { if (it.isNotBlank()) "\n$it    " else it }

    // If we have a build snippet, use that, else use the appropriate template for the type.
    val content = config.snippet ?: when (resolution) {
      is AarArtifactResolution -> mavenAarTemplate(
        target = resolved.target,
        coordinate = resolved.coordinate,
        customPackage = resolution.androidPackage,
        jetify = jetify,
        deps = deps,
        fetchRepo = resolved.fetchRepoPackage(),
        testonly = testonly,
        visibility = visibility,
        libs = resolution.libs
      )
      is JarArtifactResolution -> mavenJarTemplate(
        target = resolved.target,
        coordinate = resolved.coordinate,
        jetify = jetify,
        deps = deps,
        fetchRepo = resolved.fetchRepoPackage(),
        testonly = testonly,
        visibility = visibility
      )
      else -> mavenFileTemplate(
        target = resolved.target,
        coordinate = resolved.coordinate,
        deps = deps,
        fetchRepo = resolved.fetchRepoPackage(),
        testonly = testonly,
        visibility = visibility
      )
    }
    val path = workspace.resolve(resolved.groupPath)
      .resolve("BUILD.bazel")
    return path to TemplateApplication(resolution, content)
  }

  private fun unknownPackageFlow(
    resolution: FileArtifactResolution,
    exit: AtomicInteger
  ): Flow<ArtifactResolution> {
    return flow {
      unknownPackagingStrategy.handle(kontext, exit, resolution)
      emit(resolution)
    }
  }

  private fun packageJarFlow(
    resolution: FileArtifactResolution
  ): Flow<ArtifactResolution> {
    return flow {
      emit(JarArtifactResolution(resolution.resolved, resolution.config))
    }
  }

  private fun extractAarPackageFlow(
    resolution: FileArtifactResolution,
    exit: AtomicInteger
  ): Flow<ArtifactResolution> {
    return flow {
      val (resolved, config) = resolution
      val resolver = newResolver()
      var status: FetchStatus?
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
          try {
            if (Files.exists(resolved.main.localFile)) {
              val uri = URI.create("jar:" + resolved.main.localFile.toUri())
              extractPackageFromManifest(uri)?.let { (customPackage, libs) ->
                if (customPackage == null) {
                  kontext.info { "ERROR: Null resource package for ${resolved.coordinate}" }
                  exit.set(1)
                } else {
                  emit(AarArtifactResolution(resolved, config, customPackage, libs))
                }
              } ?: run {
                kontext.info { "ERROR: Could not extract pieces of aar ${resolved.coordinate}" }
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
    artifactSpec: String,
    seen: ConcurrentHashMap<String, IndexEntry>,
    declaredArtifactSlugs: MutableSet<String>,
    unresolved: MutableSet<String>,
    config: ArtifactConfig,
    exit: AtomicInteger
  ): Flow<FileArtifactResolution> {
    return flow {
      val resolver = newResolver()
      val artifact = resolver.artifactFor(artifactSpec)
      val slug = "${artifact.groupId}:${artifact.artifactId}"
      val entry = seen.getOrPut(slug) { IndexEntry() }
      entry.versions.add(artifact.version)
      declaredArtifactSlugs.add(slug)
      var tmp: ResolutionResult?
      val time = measureTimeMillis {
        tmp = resolver.resolve(artifact)
      }
      val result = requireNotNull(tmp)
      result.artifact?.let {
        kontext.info { "Resolved ${it.coordinate} in ${time / 1000.0} seconds" }
        emit(FileArtifactResolution(it, config))
      } ?: run {
        when (val status = result.status) {
          is FETCH_ERROR -> {
            kontext.out { "ERROR: Could not resolve ${artifact.coordinate}: ${status.message}" }
            status.error?.let { kontext.info { it.formatStackTrace() } }
          }
        }
        unresolved.add(artifact.coordinate)
        exit.set(1)
      }
    }
  }

  private fun newResolver(): ArtifactResolver {
    return ArtifactResolver(
      cacheDir = kontext.localRepository,
      suppressAddRepositoryWarnings = true,
      repositories = if (kontext.repositories.isNotEmpty()) kontext.repositories else DEFAULT,
      modelInterceptor = ::filterBuildDeps
    )
  }
}

/**
 * Takes key-value pairs (`Pair<A, B>`) performs a collection/indexing on them, and emits the
 * indexed values as a `Pair<A, Collection<B>>` (essentially a list-multimap flow)
 */
private suspend fun <A, B> Flow<Pair<A, B>>.toListMultimapFlow(): Flow<Entry<A, Collection<B>>> {
  return (
    this
      .toList() // Collector
      .toImmutableListMultimap() // Associate snippets to their build file.
      .asMap() as Map<A, Collection<B>>
    )
    .entries
    .asFlow()
}

private val jvmPackagingTypes = setOf("jar", "aar", "bundle")
private val bazelPackagePrefixes = setOf('@', '/', ':')
/**
 * For a given resolved artifact, prepare the list of its dependencies, excluding unused scopes,
 * explicitly excluded deps, and fixing and formatting.  Returns an ordered set, to handle cases
 * where a dependency is included in multiple scopes, or multiple times in the .pom file.
 */
private fun prepareDependencies(
  resolved: ResolvedArtifact,
  config: ArtifactConfig,
  seen: ConcurrentHashMap<String, GenerateMavenRepo.IndexEntry>,
  repoConfig: RepositorySpecification
): Set<String> {
  if (!config.snippet.isNullOrBlank()) return setOf()
  val substitutes =
    repoConfig.targetSubstitutes.getOrElse(resolved.groupId) { mapOf() }
  return when {
    config.deps.isNotEmpty() -> config.deps.asSequence()
      .map {
        if (it[0] in bazelPackagePrefixes) it
        else unversionedDependency(it).targetFor(repoConfig.name, substitutes, resolved)
      }
      .toSet()

    else -> resolved.model.dependencies.asSequence()
      .filter { dep -> !dep.isOptional }
      .filter { dep -> dep.slug !in config.exclude }
      // need a more robust filter, as the dependency type is not guaranteed to be set, but this will do for now.
      .filter { dep ->
        when {
          resolved.model.packaging in jvmPackagingTypes && dep.type in jvmPackagingTypes -> true
          resolved.model.packaging !in jvmPackagingTypes && dep.type !in jvmPackagingTypes -> true
          else -> false
        }
      }
      .map { dep ->
        JETIFIER_ARTIFACT_MAPPING[dep.slug]?.let { unversionedDependency(it) } ?: dep
      }
      .plus(
        // add maven extra includes
        config.include
          .asSequence()
          .filter { it[0] !in bazelPackagePrefixes }
          .map { unversionedDependency(it) }
      )
      .onEach { dep ->
        // Cache for later validation
        val entry = seen.getOrPut(dep.slug) { GenerateMavenRepo.IndexEntry() }
        entry.versions.add(dep.version)
        entry.dependants.add(resolved.coordinate)
      }
      .map { dep -> dep.targetFor(repoConfig.name, substitutes, resolved) }
      .plus(config.include.filter { it[0] in bazelPackagePrefixes }) // add bazel extra includes
      .toSet()
  }
}

private fun Dependency.targetFor(
  repoName: String,
  substitutes: Map<String, String>,
  resolved: ResolvedArtifact
): String {
  val bazelPackage = "@$repoName//$groupPath"
  val leafPackage = bazelPackage.split("/")
    .last()
  val prefix = "$bazelPackage:"
  return "$prefix$target"
    .let { d ->
      substitutes.getOrElse(d) { d }
    }
    .let { d ->
      when {
        resolved.groupId == groupId -> d.removePrefix(bazelPackage)
        leafPackage == target -> bazelPackage
        else -> d
      }
    }
}

internal enum class UnknownPackagingStrategy {
  WARN {
    override fun handle(
      kontext: Kontext,
      exit: AtomicInteger,
      a: FileArtifactResolution
    ) = kontext.out {
      "WARNING: ${a.resolved.coordinate} is not a handled package type, " +
        "${a.resolved.model.packaging}"
    }
  },
  FAIL {
    override fun handle(
      kontext: Kontext,
      exit: AtomicInteger,
      a: FileArtifactResolution
    ) {
      kontext.out {
        "\nERROR: ${a.resolved.coordinate} is not a supported packaging, " +
          "${a.resolved.model.packaging}"
      }
      exit.set(1)
    }
  },
  IGNORE {
    override fun handle(
      kontext: Kontext,
      exit: AtomicInteger,
      a: FileArtifactResolution
    ) {}
  };

  abstract fun handle(
    kontext: Kontext,
    exit: AtomicInteger,
    a: FileArtifactResolution
  )
}
