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
    assertThat(artifact.groupPath).isEqualTo("a/b/c_d")
  }

  @Test fun artifactTarget() {
    assertThat(artifact.target).isEqualTo("e_f-g")
  }
  @Test fun dependencyGroupPath() {
    assertThat(dependency.groupPath).isEqualTo("a/b/c_d")
  }

  @Test fun dependencyTarget() {
    assertThat(dependency.target).isEqualTo("e_f-g")
  }

  @Test fun fetchRepoPackage() {
    assertThat(artifact.fetchRepoPackage()).isEqualTo("@a_b_c_d_e_f_g//maven")
  }
}
