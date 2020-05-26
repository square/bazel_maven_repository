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

import com.google.common.truth.Truth.assertThat
import com.squareup.tools.maven.resolution.ArtifactResolver
import org.apache.maven.model.Dependency
import org.junit.Test

class CommonTest {

  val artifact = ArtifactResolver().artifactFor("a.b.c-d:e.f-g:1.0")
  val dependency = Dependency().apply {
    groupId = "a.b.c-d"
    artifactId = "e.f-g"
    version = "1.0"
  }

  @Test fun artifactGroupPath() {
    assertThat(artifact.groupPath).isEqualTo("a/b/c-d")
  }

  @Test fun artifactTarget() {
    assertThat(artifact.target).isEqualTo("e_f-g")
  }
  @Test fun dependencyGroupPath() {
    assertThat(dependency.groupPath).isEqualTo("a/b/c-d")
  }

  @Test fun dependencyTarget() {
    assertThat(dependency.target).isEqualTo("e_f-g")
  }

  @Test fun fetchRepoPackage() {
    assertThat(artifact.fetchRepoPackage()).isEqualTo("@a_b_c_d_e_f_g//maven")
  }
}
