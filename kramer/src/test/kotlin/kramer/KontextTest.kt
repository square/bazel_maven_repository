package kramer

import com.google.common.truth.Truth.assertThat
import org.apache.maven.model.Repository
import org.junit.Test
import java.nio.file.Paths

class KontextTest {
  private val kontext = Kontext(localRepository = Paths.get("."))
  private val testConfig = KramerConfig(
    workspaceName = "foo",
    repositories = listOf(Repository().apply { id = "blah" ; url = "foo://blah/" })
  )
  private val testSettings = Settings(
    mirrors = listOf(Mirror(id = "blah", url = "foo://bar/"))
  )

  @Test fun testOverriding() {
    kontext.apply {
      this.settings = testSettings
      this.config = testConfig
    }
    val repositories = kontext.repositories
    assertThat(repositories).hasSize(1)
    assertThat(repositories.first().id).isEqualTo("blah")
    assertThat(repositories.first().url).isEqualTo("foo://bar/")
  }
}
