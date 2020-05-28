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
import com.squareup.tools.maven.resolution.ArtifactFetcher
import com.squareup.tools.maven.resolution.ArtifactFile
import com.squareup.tools.maven.resolution.ArtifactResolver
import com.squareup.tools.maven.resolution.FileSpec
import com.squareup.tools.maven.resolution.PomFile
import java.nio.file.Paths
import org.apache.maven.model.Repository
import org.junit.Assert.assertThrows
import org.junit.Test

class JetifierTest {
  @Test fun badGlobNoColon() {
    val e = assertThrows(IllegalArgumentException::class.java) {
      ArtifactExclusionGlob("abcdef*g")
    }
    assertThat(e).hasMessageThat()
      .contains("Invalid exclusion glob \"abcdef*g\" lacks the groupId:artifactId structure.")
  }

  @Test fun badTotalWildcardGlob() {
    val e = assertThrows(IllegalArgumentException::class.java) {
      ArtifactExclusionGlob("*:*")
    }
    assertThat(e).hasMessageThat()
      .contains("Invalid exclusion glob \"*:*\" would exclude all artifacts.")
  }

  @Test fun badGlobNoPartial() {
    val e = assertThrows(IllegalArgumentException::class.java) {
      ArtifactExclusionGlob("*.*.*:*")
    }
    assertThat(e).hasMessageThat().contains("Invalid exclusion glob \"*.*.*:*\" - requires")
  }

  @Test fun matches() {
    assertThat(ArtifactExclusionGlob("foo.*:bar").matches("foo.bar", "bar")).isTrue()
    assertThat(ArtifactExclusionGlob("foo.*:bar").matches("foo", "bar")).isFalse()
    assertThat(ArtifactExclusionGlob("foo.*:*").matches("foo.bar", "bar")).isTrue()
    assertThat(ArtifactExclusionGlob("foo.*:*").matches("foo.blah", "blargh")).isTrue()
    assertThat(ArtifactExclusionGlob("*:blargh").matches("foo.blah", "blargh")).isTrue()
    assertThat(ArtifactExclusionGlob("*:blargh").matches("blah.foo", "blargh")).isTrue()
    assertThat(ArtifactExclusionGlob("*:bla*rgh").matches("blah.foo", "blargh")).isTrue()
    assertThat(ArtifactExclusionGlob("*:bla*rgh").matches("blah.foo", "blaaaarrrrrgh")).isTrue()
    assertThat(ArtifactExclusionGlob("foo.*.baz:*").matches("foo.bar.baz", "whatevz")).isTrue()
    assertThat(ArtifactExclusionGlob("foo.*.baz:*").matches("foo.blah.baz", "yo")).isTrue()
  }

  @Test fun matchMany() {
    val matcher = JetifierMatcher(listOf(
      ArtifactExclusionGlob("foo.*:bar"),
      ArtifactExclusionGlob("*:bla*rgh"),
      ArtifactExclusionGlob("foo.*.baz:*")
    ))
    assertThat(matcher.matches(artifact("foo", "bar"))).isFalse() // no dot
    assertThat(matcher.matches(artifact("foo.bar", "bar"))).isTrue()
    assertThat(matcher.matches(artifact("foo.bar", "blah"))).isFalse()
    assertThat(matcher.matches(artifact("foo.blah", "blargh"))).isTrue()
    assertThat(matcher.matches(artifact("blah.foo", "blaaaarrrrrgh"))).isTrue()
    assertThat(matcher.matches(artifact("foo.blah.baz", "yo"))).isTrue()
    assertThat(matcher.matches(artifact("a", "b"))).isFalse()
  }

  fun artifact(groupId: String, artifactId: String) =
    resolver.artifactFor("$groupId:$artifactId:1.0")

  companion object {
    private val resolver = ArtifactResolver(
      fetcher = object : ArtifactFetcher {
        override fun fetchArtifact(artifactFile: ArtifactFile, repositories: List<Repository>) =
          throw UnsupportedOperationException("Fake")

        override fun fetchFile(fetchFile: FileSpec, repositories: List<Repository>) =
          throw UnsupportedOperationException("Fake")

        override fun fetchPom(pom: PomFile, repositories: List<Repository>) =
          throw UnsupportedOperationException("Fake")
      },
      cacheDir = Paths.get(".")
    ) // purely for creating artifacts.
  }
}
