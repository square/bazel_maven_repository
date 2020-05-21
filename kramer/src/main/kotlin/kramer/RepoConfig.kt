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

data class ArtifactConfig(
  val sha256: String?,
  @Json(name = "build_snippet")
  val snippet: String?,
  val insecure: Boolean = false,
  val testonly: Boolean = false,
  val exclude: Set<String> = setOf()
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
  val mavenRulesRepository: String
) {
  val jetifierMatcher by lazy {
    JetifierMatcher(jetifierExcludes.map { ArtifactExclusionGlob(it) })
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
