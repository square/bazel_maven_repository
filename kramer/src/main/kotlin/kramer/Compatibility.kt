package kramer

import kramer.GenerateMavenRepo.ArtifactResolution

internal fun generateRulesJvmCompatibilityTargets(
  repoSpec: RepositorySpecification,
  resolutions: Set<ArtifactResolution>
): String {
  val snippets = resolutions.sortedBy { (artifact) -> artifact.coordinate }
    .map { (artifact, config) ->
      val compatibilityTarget = (artifact.groupId + "_" + artifact.artifactId)
        .replace("[-.]".toRegex(), "_")
      val target = "@${repoSpec.name}//${artifact.groupPath}:${artifact.target}"
      """alias(name = "$compatibilityTarget", actual = "$target") # ${artifact.coordinate}"""
    }

  val preamble = """
    |# Aliases from rules_jvm_external-style root targets to bazel_maven_repository
    |# package-name-spaced targets.
    |package(default_visibility = ["//visibility:public"])
    |
    |# Aliases
    |
    |""".trimMargin()
  return preamble + snippets.joinToString("\n")
}
