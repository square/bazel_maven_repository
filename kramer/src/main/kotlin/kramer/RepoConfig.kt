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
