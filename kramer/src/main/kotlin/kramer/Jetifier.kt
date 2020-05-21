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

import com.squareup.tools.maven.resolution.Artifact

fun String.toGlobMatcher() =
  replace(".", "[.]").replace("*", ".*").toRegex()

class ArtifactExclusionGlob(private val glob: String) {
  init {
    require(glob != "*:*") {
      "Invalid exclusion glob \"*:*\" would exclude all artifacts. Set use_jetifier=False instead."
    }
    require(glob.contains(":")) {
      "Invalid exclusion glob \"abcdef*g\" lacks the groupId:artifactId structure."
    }
    val remainder = glob.replace("*", "")
      .replace(":", "")
      .replace(".", "")
      .trim()
    require(remainder.isNotBlank()) {
      "Invalid exclusion glob \"$glob\" - requires some valid partial group or artifact id"
    }
  }
  private val parts by lazy { glob.split(":") }
  private val groupIdMatcher by lazy { parts[0].toGlobMatcher() }
  private val artifactIdMatcher by lazy { parts[1].toGlobMatcher() }

  fun matches(groupId: String, artifactId: String) =
    groupIdMatcher.matches(groupId) && artifactIdMatcher.matches(artifactId)
}

class JetifierMatcher(val matchers: List<ArtifactExclusionGlob>) {
  fun matches(artifact: Artifact): Boolean {
    matchers.forEach {
      if (it.matches(artifact.groupId, artifact.artifactId)) return true
    }
    return false
  }
}
