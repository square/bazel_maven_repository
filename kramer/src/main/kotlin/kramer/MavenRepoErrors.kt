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

import com.squareup.tools.maven.resolution.MavenVersion
import kramer.GenerateMavenRepo.IndexEntry

internal fun GenerateMavenRepo.handleDuplicateArtifacts(repoConfig: RepoConfig) {
  kontext.out { "ERROR: Duplicate artifact entries are not permitted:" }
  repoConfig.artifacts.keys
    .map { spec ->
      val (groupId, artifactId, version) = spec.split(":")
      "$groupId:$artifactId" to version
    }
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

internal fun GenerateMavenRepo.handlePreAndroidXArtifacts(preX: Set<String>) {
  kontext.out { "ERROR: Jetifier enabled but pre-androidX support artifacts specified:" }
  preX.forEach { kontext.out { "    $it (should be ${JETIFIER_ARTIFACT_MAPPING[it]})" } }
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
