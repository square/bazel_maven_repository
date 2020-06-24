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
package kramer.integration

import com.github.ajalt.clikt.core.subcommands
import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.nio.file.Files
import java.nio.file.Paths
import kramer.GenerateMavenRepo
import kramer.Kontext
import kramer.Kramer
import kramer.RepositorySpecification
import kramer.UnknownPackagingStrategy
import kramer.parseJson
import org.junit.After
import org.junit.Ignore
import org.junit.Test
import java.nio.file.FileSystems
import java.nio.file.Path

/**
 * Integration tests for [GenerateMavenRepoCommand]. These are dependent on access to the network
 * and to the maven repositories it fetches from. It's runtime depends on latencies and throughput
 * to the above repositories. That said, from a home office internet it completes in less than 10
 * seconds on average (which includes 2 large no-cache scenarios).
 */
class GenerateMavenRepoIntegrationTest {
  private val relativeDir = "test_workspace/src/test/kotlin"
  private val packageDir = this.javaClass.`package`!!.name.replace(".", "/")
  private val tmpDir = Files.createTempDirectory("resolution-test-")
  private val cacheDir = tmpDir.resolve("localcache")
  private val runfiles = Paths.get(System.getenv("JAVA_RUNFILES")!!)
  private val baos = ByteArrayOutputStream()
  private val mavenRepo = GenerateMavenRepo()
  private val cmd = Kramer(output = PrintStream(baos)).subcommands(mavenRepo)

  @After fun tearDown() {
    tmpDir.toFile()
        .deleteRecursively()
    check(!Files.exists(cacheDir)) { "Failed to tear down and delete temp directory." }
  }

  @Test fun simpleResolution() {
    val args = configFlags("simple", "gen-maven-repo")
    val output = cmd.test(args, baos)
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("\nGenerated 1 build files in ")
    assertThat(output).contains("\nResolved 1 artifacts with 100 threads in")
    val build = mavenRepo.readBuildFile("javax.inject")
    assertThat(build).contains("javax.inject:javax.inject:1")
    assertThat(build).contains("name = \"javax_inject\"")
    assertThat(build).contains("@javax_inject_javax_inject//maven")
  }

  @Test fun unknownPackagingFail() {
    val args = configFlags("unhandled-packaging", "gen-maven-repo")
    val output =
      cmd.fail(args + listOf("--unknown-packaging", UnknownPackagingStrategy.FAIL.name), baos)
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("Generated 1 build files in ")
    assertThat(output).contains("Resolved 1 artifacts with 100 threads in")
    assertThat(output)
        .contains("ERROR: com.squareup.sqldelight:runtime:1.4.0 is not a supported packaging, pom")
  }

  @Test fun unknownPackagingWarn() {
    val args = configFlags("unhandled-packaging", "gen-maven-repo")
    val output = cmd.test(
        args + listOf("--unknown-packaging", UnknownPackagingStrategy.WARN.name),
        baos
    )
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("Generated 1 build files in ")
    assertThat(output).contains("Resolved 1 artifacts with 100 threads in")
    assertThat(output)
        .contains("WARNING: com.squareup.sqldelight:runtime:1.4.0 is not a handled package type, pom")
    val build = mavenRepo.readBuildFile("com.squareup.sqldelight")
    assertThat(build).contains("com.squareup.sqldelight:runtime:1.4.0")
    assertThat(build).contains("filegroup(")
    assertThat(build).contains("srcs = [\"@com_squareup_sqldelight_runtime//maven\"],")

    println(build)
  }

  @Test fun unknownPackagingIgnore() {
    val args = configFlags("unhandled-packaging", "gen-maven-repo")
    val output = cmd.test(
        args + listOf("--unknown-packaging", UnknownPackagingStrategy.IGNORE.name),
        baos
    )
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("Generated 1 build files in ")
    assertThat(output).contains("Resolved 1 artifacts with 100 threads in")
    val build = mavenRepo.readBuildFile("com.squareup.sqldelight")
    assertThat(build).contains("com.squareup.sqldelight:runtime:1.4.0")
    assertThat(build).contains("filegroup(")
    assertThat(build).contains("srcs = [\"@com_squareup_sqldelight_runtime//maven\"],")
  }

  @Test fun excludeSuccess() {
    val args = configFlags("excludes-success", "gen-maven-repo")
    val output = cmd.test(args, baos)
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("Generated 1 build files in ")
    assertThat(output).contains("Resolved 1 artifacts with 100 threads in")
  }

  @Test fun excludeFailure() {
    val args = configFlags("excludes-failure", "gen-maven-repo")
    val output = cmd.fail(args, baos)
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("Generated 1 build files in ")
    assertThat(output).contains("Resolved 1 artifacts with 100 threads in")

    assertThat(output)
        .contains("ERROR: Un-declared artifacts referenced in the dependencies of some artifacts.")
    assertThat(output)
        .contains(""""org.apache.maven:maven-builder-support:3.6.3": {"insecure": True}""")
    assertThat(output).contains(""""exclude": ["org.apache.maven:maven-builder-support"]""")
  }

  @Test fun includeDeps() {
    val args = configFlags("include", "gen-maven-repo")
    val output = cmd.test(args, baos)
    assertThat(output).contains("Building workspace for 5 artifacts")
    assertThat(output).contains("Generated 5 build files in ")
    assertThat(output).contains("Resolved 5 artifacts with 100 threads in")

    val jimfs = mavenRepo.readBuildFile("com.google.jimfs")
    assertThat(jimfs).contains("\"@maven//blah/foo\",")
    assertThat(jimfs).contains("\"@maven//javax/inject:javax_inject\",")

    val helpshift = mavenRepo.readBuildFile("com.helpshift")
    assertThat(helpshift).contains("\":blah\",")
    assertThat(helpshift).contains("\"@maven//blah/foo\",")
    assertThat(helpshift).contains("\"//blah/foo\",")
    assertThat(helpshift).contains("\"@maven//androidx/annotation\",")
  }

  @Test fun replaceDeps() {
    val args = configFlags("replace-deps", "gen-maven-repo")
    val output = cmd.test(args, baos)
    assertThat(output).contains("Building workspace for 3 artifacts")
    assertThat(output).contains("Generated 3 build files in ")
    assertThat(output).contains("Resolved 3 artifacts with 100 threads in")

    val jimfs = mavenRepo.readBuildFile("com.google.jimfs")
    assertThat(jimfs).contains("\"@maven//androidx/annotation\",")

    val helpshift = mavenRepo.readBuildFile("com.helpshift")
    assertThat(helpshift).contains("\":blah\",")
    assertThat(helpshift).contains("\"@maven//blah/foo\",")
    assertThat(helpshift).contains("\"//blah/foo\",")
    assertThat(helpshift).contains("\"@maven//androidx/annotation\",")
  }

  @Test fun overconfiguredArtifacts() {
    val args = configFlags("overconfigured", "gen-maven-repo")
    val output = cmd.fail(args, baos)

    assertThat(output)
        .contains("ERROR: Invalid config: com.google.jimfs:jimfs:1.1 may only be configured " +
            "with build_snippet, or deps, or include/exclude mechanisms.")
    assertThat(output)
        .contains("ERROR: Invalid config: com.helpshift:android-helpshift-aar:7.8.0 " +
        "may only be configured with build_snippet, or deps, or include/exclude mechanisms.")
  }

  @Test fun buildSnippetOverridesUndeclared() {
    // If an artifact has a build snippet, it's deps should not contribute to the required list.
    // This config includes a build snippet but no excludes.
    val args = configFlags("build-snippet", "gen-maven-repo")
    val output = cmd.test(args, baos)
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("Generated 1 build files in ")
    assertThat(output).contains("Resolved 1 artifacts with 100 threads in")
  }

  @Test fun dontPropagateOptionalDeps() {
    val args = configFlags("optional", "gen-maven-repo")
    val output = cmd.test(args, baos)
    assertThat(output).contains("Building workspace for 2 artifacts")
    assertThat(output).contains("Generated 2 build files in ")
    assertThat(output).contains("Resolved 2 artifacts with 100 threads in")
  }

  @Test fun aarWithLibs() {
    val args = configFlags("aar-libs", "gen-maven-repo")
    val output = cmd.test(args, baos)
    assertThat(output).contains("Building workspace for 8 artifacts")
    assertThat(output).contains("Generated 7 build files in ")
    assertThat(output).contains("Resolved 8 artifacts with 100 threads in")

    val helpshift = mavenRepo.readBuildFile("com.helpshift")
    val support = mavenRepo.readBuildFile("androidx.core")
    assertThat(support).contains("deps = [\":core_classes\"] + [] + [")

    assertThat(helpshift).contains("""
      |    deps = [":android-helpshift-aar_classes"] + [
      |        ":android-helpshift-aar_libs_logger",
      |        ":android-helpshift-aar_libs_core",
      |        ":android-helpshift-aar_libs_NVWebsockets",
      |        ":android-helpshift-aar_libs_HelpshiftLogger",
      |        ":android-helpshift-aar_libs_Downloader",
      |    ] + [],
      |    exports = [":android-helpshift-aar_classes"] + [
      |        ":android-helpshift-aar_libs_logger",
      |        ":android-helpshift-aar_libs_core",
      |        ":android-helpshift-aar_libs_NVWebsockets",
      |        ":android-helpshift-aar_libs_HelpshiftLogger",
      |        ":android-helpshift-aar_libs_Downloader",
      |    ],""".trimMargin()
    )

    assertThat(helpshift).contains("""
      |raw_jvm_import(
      |    name = "android-helpshift-aar_libs_logger",
      |    jar = "@com_helpshift_android_helpshift_aar//maven:libs/logger.jar",
      |)""".trimMargin()
    )
  }

  @Test fun jetifierMatch() {
    val args = configFlags("jetifier", "gen-maven-repo")
    val output = cmd.test(args, baos)
    assertThat(output).contains("Building workspace for 2 artifacts")
    assertThat(output).contains("Generated 2 build files in ")
    assertThat(output).contains("Resolved 2 artifacts with 100 threads in")

    val guava = mavenRepo.readBuildFile("com.google.guava")
    assertThat(guava).contains("jetify = True")
    val jimfs = mavenRepo.readBuildFile("com.google.jimfs")
    assertThat(jimfs).doesNotContain("jetify")
  }

  @Test fun jetifierMap() {
    val args = configFlags("jetifier-map", "gen-maven-repo")
    val output = cmd.test(args, baos)
    assertThat(output).contains("Building workspace for 2 artifacts")
    assertThat(output).contains("Generated 2 build files in ")
    assertThat(output).contains("Resolved 2 artifacts with 100 threads in")

    val picasso = mavenRepo.readBuildFile("com.squareup.picasso")
    assertThat(picasso).contains("jetify = True")
    assertThat(picasso).contains("@maven//androidx/annotation")
  }

  @Test fun jetifierMapMissingArtifact() {
    val args = configFlags("jetifier-map-missing-artifact", "gen-maven-repo")
    val output = cmd.fail(args, baos)
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("Generated 1 build files in ")
    assertThat(output).contains("Resolved 1 artifacts with 100 threads in")
    assertThat(output)
        .contains("ERROR: Un-declared artifacts referenced in the dependencies of some artifacts.")

    // Picasso declares dep on com.android.support:support-annotation. Want to see androidx here.
    assertThat(output).contains("androidx.annotation:annotation:<SOME_VERSION>")
  }

  @Test fun jetifierPreAndroidXArtifact() {
    val args = configFlags("android-support", "gen-maven-repo")
    val output = cmd.fail(args, baos)
    assertThat(output).contains("Building workspace for 3 artifacts")
    assertThat(output).contains("Generated 3 build files in ")
    assertThat(output).contains("Resolved 3 artifacts with 100 threads in")

    assertThat(output)
        .contains("ERROR: Jetifier enabled but pre-androidX support artifacts specified:")
    assertThat(output)
        .contains(
            "com.android.support:support-annotations (should be androidx.annotation:annotation)"
        )
    assertThat(output).doesNotContain("javax.inject:javax.inject")
  }

  @Test fun jetifierPreAndroidXArtifactDisabled() {
    val args = configFlags("android-support-check-disabled", "gen-maven-repo")
    val output = cmd.test(args, baos)
    assertThat(output).contains("Building workspace for 3 artifacts")
    assertThat(output).contains("Generated 3 build files in ")
    assertThat(output).contains("Resolved 3 artifacts with 100 threads in")
  }

  @Test fun largeListOfArtifacts() {
    val args = configFlags("large", "gen-maven-repo")
    val output = cmd.test(args, baos)

    assertWithMessage("missing groups and labels")
        .that(
            readLabelIndexFromConfigOf("large")
                .asSequence()
                .flatMap { (groupId, arts) ->
                  val build = mavenRepo.maybeReadBuildFile(groupId)
                  arts.asSequence()
                      .filterNot { lbl ->
                        build?.contains(lbl) ?: false
                      }
                      .map { lbl -> "$groupId -> $lbl" }
                }
                .sorted()
                .toList()
        )
        .isEmpty()

    assertThat(output).contains("Building workspace for 467 artifacts")
    assertThat(output).contains("Generated 228 build files in ")
    assertThat(output).contains("Resolved 467 artifacts with 100 threads in")
  }

  // This is the flakiest test design that ever flaked, but we want a sense that there is
  // a speed up with large artifact lists, and to have a canary.
  //
  // Also, it's not presently honoring the prior-cache in the test environment, so i've
  // disabled it for now. The caching works fine in normal operations, so it's unclear what's
  // happening. Leaving this here TBD
  //
  // TODO Fix this or migrate it to a more appropriate performance test enviornment.
  //
  @Ignore("This is a performance test, crazy flaky, and not quite right yet.")
  @Test fun largeListOfArtifactsWithCaching() {
    val timingMatcher = "with [0-9]* threads in ([0-9.]*) seconds".toRegex()

    val output1 = cmd.test(configFlags("large", "gen-maven-repo"), baos)
    val result1 = timingMatcher.find(output1)
    assertWithMessage("Expected to match ${timingMatcher.pattern}").that(result1)
        .isNotNull()
    val time1 = result1!!.groupValues[1].toFloat()
    assertWithMessage("Expected non-cached first run, but run took $time1 seconds")
        .that(time1)
        .isGreaterThan(4.0f)

    assertThat(Files.exists(cacheDir.resolve("junit/junit/4.13/junit-4.13.pom"))).isTrue()
    val output2 = cmd.test(
      configFlags("large", "gen-maven-repo", customConfig = true, workspace = "workspace2"),
      baos
    )
    val result2 = timingMatcher.find(output2)
    assertWithMessage("Expected to match ${timingMatcher.pattern}").that(result2)
        .isNotNull()
    val time2 = result2!!.groupValues[1].toFloat()
    assertWithMessage("Expected fast cache run but took $time2 seconds")
        .that(time2)
        .isLessThan(3.0f)

    assertThat(output2).contains("Resolved 469 artifacts with 100 threads in ")
  }

  private fun GenerateMavenRepo.readBuildFile(groupId: String): String {
    return maybeReadBuildFile(groupId) { buildFile ->
      assertWithMessage("File does not exist: $buildFile").that(Files.exists(buildFile))
          .isTrue()
    }!!
  }

  private fun GenerateMavenRepo.maybeReadBuildFile(
    groupId: String,
    validate: (Path) -> Unit = {}
  ): String? {
    val groupPath = groupId.replace(".", "/")
    val workspace = workspace.toAbsolutePath()
    val buildFile = workspace.resolve(groupPath)
        .resolve("BUILD.bazel")
    validate(buildFile)
    if (Files.exists(buildFile)) {
      return Files.readAllLines(buildFile)
          .joinToString("\n")
    }
    return null
  }

  private fun readLabelIndexFromConfigOf(label: String): Map<String, MutableSet<String>> {
    val spec = Kontext(localRepository = cacheDir).parseJson(
        FileSystems.getDefault()
            .getPath("$runfiles/$relativeDir/$packageDir/test-$label-config.json"),
        RepositorySpecification::class
    )
    return spec.artifacts.keys.asSequence()
        .map { spec ->
          val (groupId, art, _) = spec.split(":")
          return@map groupId to "\"" + art.replace(".", "_") + "\""
        }
        .fold(mutableMapOf()) { acc, (groupId, lbl) ->
          acc.apply {
            getOrPut(groupId, ::mutableSetOf).add(lbl)
          }
        }
  }

  private fun configFlags(
    label: String,
    command: String,
    threads: Int = 100,
    workspace: String = "workspace",
    customConfig: Boolean = false,
    customSettings: Boolean = false
  ): List<String> {
    val testSourceDir = "$runfiles/$relativeDir/$packageDir"
    val kramerConfig = if (customConfig) "kramer-$label-config.json" else "kramer-config.json"
    val settings =
      if (customSettings) listOf("--settings=$testSourceDir/$label-settings.json")
      else listOf()
    return settings +
      "--local_maven_cache=$cacheDir" +
      "--config=$testSourceDir/$kramerConfig" +
      command +
      "--threads=$threads" +
      "--workspace=$tmpDir/$workspace" +
      "--specification=$testSourceDir/test-$label-config.json"
  }
}
