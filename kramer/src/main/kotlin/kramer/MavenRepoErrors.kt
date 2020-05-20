package kramer

import com.squareup.tools.maven.resolution.ArtifactResolver
import com.squareup.tools.maven.resolution.MavenVersion
import kramer.GenerateMavenRepo.IndexEntry

internal fun GenerateMavenRepo.handleDuplicateArtifacts(repoConfig: RepoConfig) {
  val resolver = ArtifactResolver() // only used for parsing
  kontext.out { "ERROR: Duplicate artifact entries are not permitted:" }
  repoConfig.artifacts.keys
    .map { spec -> with(resolver.artifactFor(spec)) { "$groupId:$artifactId" to version } }
    .toImmutableListMultimap()
    .asMap()
    .filter { (_, versions) -> versions.size > 1 }
    .forEach { (slug, versions) ->
      kontext.out { "    $slug: $versions" }
    }
}

internal fun GenerateMavenRepo.handleUnresolvedArtifacts(unresolved: Set<String>?) {
  kontext.out { "ERROR: Failed to resolve the following artifacts: $unresolved" }
}

internal fun GenerateMavenRepo.handleMissingArtifacts(remainder: Map<String, IndexEntry>) {
  kontext.out { "ERROR: Un-declared artifacts referenced in the dependencies of some artifacts." }
  kontext.out { "Please exclude the following or add them to your artifact configuration list." }
  kontext.out { "To add them, copy this into your artifact list:" }
  for ((slug, details) in remainder.entries) {
    val version = when (details.versions.size) {
      0 -> throw AssertionError("Seen must contain at least one version.")
      1 -> details.versions.first()
      else -> details.versions.map { MavenVersion.from(it) }.max()!!
    }
    kontext.out { "    \"$slug:$version\": {\"insecure\": True}," }
  }
  kontext.out { "To exclude them, add them to the exclude lists of their dependants:" }
  remainder.entries
    .map { (slug, details) -> slug to details.dependants }
    .forEach { (slug, dependants) ->
      for (dependant in dependants) {
        kontext.out { """    "$dependant": {"insecure": True, "exclude": ["$slug"]},""" }
      }
    }
}
