package kramer

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.nio.file.Paths

class ConfigurationTest {
  private val kontext = Kontext(localRepository = Paths.get("."))

  private val CONFIG = """
    {
      "name": "maven",
      "repositories": [ { "id": "blah", "url": "foo://bar/" } ]
    }
    """.trimIndent()

  private val SETTINGS = """
    {
      "mirrors": [ { "id": "blah", "url": "foo://blah/" } ]
    }
    """.trimIndent()

  @Test fun testConfigParse() {
    val config = kontext.parseJson(CONFIG, KramerConfig::class)
    assertThat(config.repositories).hasSize(1)
    assertThat(config.repositories.first().id).isEqualTo("blah")
    assertThat(config.repositories.first().url).isEqualTo("foo://bar/")
  }

  @Test fun testSettingsParse() {
    val settings = kontext.parseJson(SETTINGS, Settings::class)
    assertThat(settings.mirrors).hasSize(1)
    assertThat(settings.mirrors.first().id).isEqualTo("blah")
    assertThat(settings.mirrors.first().url).isEqualTo("foo://blah/")
  }

  @Test fun testDefaultParse() {
    val settings = kontext.parseJson(null, Settings())
    assertThat(settings.mirrors).hasSize(0)
  }
}
