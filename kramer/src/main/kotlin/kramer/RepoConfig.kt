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

import com.squareup.moshi.Json
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.nio.file.Files
import java.nio.file.Path

/** Defines the permissible artifact configuration */
data class ArtifactConfig(
  /** SHA256 hash of the main artifact's content. Incompatible with [insecure] */
  val sha256: String?,

  /**
   * An explicit acknowledgement that this artifact is not being securely checked for its sha256
   * content hash, and may, therefore, be subject to a man-in-the-middle attack or repository
   * poisoning. Incompatible with [sha256]
   */
  val insecure: Boolean = false,

  /**
   * A text snippet which entirely replaces the generated build snippet, and disables any
   * automatic resolution/dependency-computation/etc.
   *
   * Incompatible with configuration options that affect dependencies or otherwise would affect
   * the generated snippet.
   */
  @Json(name = "build_snippet")
  val snippet: String?,

  /**
   * Sets the bazel `testonly` flag for the generated target. Incompatible with [snippet]]
   */
  val testonly: Boolean = false,

  /**
   * Replaces the resolved dependencies entirely with the supplied dependencies, resolving any
   * maven-style `groupId:artifactId` pairs into local maven/bazel targets, and directly passing
   * through any bazel targets.
   *
   * Incompatible with [exclude], [include], and [snippet]
   */
  val deps: List<String> = listOf(),

  /**
   * Omits any listed `groupId:artifactId` pairs from the computed dependencies for this
   * target. This is a lenient list, and will not error of an excluded artifact is not present in
   * the computed artifact list. Excluded deps are excluded from the generated list, not the from
   * any supplied [include] list.
   *
   * Incompatible with [snippet] and [deps]
   */
  val exclude: Set<String> = setOf(),

  /**
   * Adds additional dependencies to the dependency list above and beyond the computed dependencies
   * for this target. Dependencies in the maven form of `groupId:artifactId` pairs will be treated
   * as if they had been discovered from dependency metadata, and the bazel snippet generated will
   * point to the generated targets of those dependencies. Bazel-formatted targets will be passed
   * through as-is, leaving validation to the bazel graph itself.  Include list is added after the
   * [exclude] list, so will override any exclusions made there.
   *
   * Incompatible with [snippet] and [deps]
   */
  val include: Set<String> = setOf()
) {
  fun validate(artifact: String): List<ValidationError> {
    val errors = mutableListOf<ValidationError>()
    if (insecure xor (sha256 == null)) errors.add(
        ValidationError(artifact, "$artifact must be marked either with a sha256 or as insecure.")
    )
    if (testonly && (snippet != null)) errors.add(
        ValidationError(
            artifact,
            "Do not set testonly on $artifact. " +
                "It has a build_snippet and target generation is overridden"
        )
    )
    if (!zeroOrOneOf(
            snippet != null,
            deps.isNotEmpty(),
            include.isNotEmpty() || exclude.isNotEmpty())) {
      errors.add(
        ValidationError(
            artifact,
            "$artifact may only be configured with build_snippet, or deps, or include/exclude" +
                " mechanisms. These are incompatible settings"
        )
      )
    }

    return errors
  }
}

data class ValidationError(
  val artifact: String?,
  val message: String
)

data class RepoConfig(
  val name: String,
  val artifacts: Map<String, ArtifactConfig>,
  @Json(name = "target_substitutes")
  val targetSubstitutes: Map<String, Map<String, String>>,
  @Json(name = "use_jetifier")
  val useJetifier: Boolean,
  @Json(name = "jetifier_excludes")
  val jetifierExcludes: List<String>,
  @Json(name = "maven_rules_repository")
  val mavenRulesRepository: String,
  @Json(name = "ignore_legacy_android_support_artifacts")
  val ignoreLegacyAndroidSupportArtifacts: Boolean = false
) {
  val jetifierMatcher by lazy {
    JetifierMatcher(jetifierExcludes.map { ArtifactExclusionGlob(it) })
  }

  fun validate(): List<ValidationError> {
    return artifacts.entries
        .flatMap { (artifact, config) -> config.validate(artifact) }
  }
}

internal fun parseRepoConfig(configFile: Path): RepoConfig {
  val moshi = Moshi.Builder()
    // ... add your own JsonAdapters and factories ...
    .add(KotlinJsonAdapterFactory())
    .build()
  val adapter: JsonAdapter<RepoConfig> = moshi.adapter(RepoConfig::class.java)
  val json = Files.readAllLines(configFile).joinToString("\n")
  val config = adapter.fromJson(json)
  assert(config != null) { "Could not parse config from $configFile" }
  return config!!
}
