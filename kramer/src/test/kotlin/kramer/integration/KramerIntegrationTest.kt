package kramer.integration

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.ProgramResult
import com.github.ajalt.clikt.core.subcommands
import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import com.squareup.tools.maven.resolution.Repositories.GOOGLE_ANDROID
import com.squareup.tools.maven.resolution.Repositories.MAVEN_CENTRAL
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.nio.file.Files
import java.nio.file.Paths
import kramer.GenerateMavenRepo
import kramer.Kramer
import kramer.ResolveArtifactCommand
import org.junit.After
import org.junit.Ignore
import org.junit.Test

/**
 * Integration tests for Kramer. These are dependent on access to the network and to the maven
 * repositories it fetches from. It's runtime depends on latencies and throughput to the above
 * repositories. That said, from a home office internet it completes in less than 10 seconds
 * on average (which includes 2 large no-cache scenarios).
 */

class KramerIntegrationTest {
  private val relativeDir = "test_workspace/src/test/kotlin"
  private val packageDir = this.javaClass.`package`!!.name.replace(".", "/")
  private val tmpDir = Files.createTempDirectory("resolution-test-")
  private val cacheDir = tmpDir.resolve("localcache")
  private val runfiles = Paths.get(System.getenv("JAVA_RUNFILES")!!)
  val repoArgs = listOf(
    "--repository=${MAVEN_CENTRAL.id}|${MAVEN_CENTRAL.url}",
    "--repository=${GOOGLE_ANDROID.id}|${GOOGLE_ANDROID.url}",
    "--repository=spring_io_plugins|https://repo.spring.io/plugins-release",
    "--local_maven_cache=$cacheDir"
  )
  private val baos = ByteArrayOutputStream()
  private val cmd = Kramer(output = PrintStream(baos))
    .subcommands(ResolveArtifactCommand(), GenerateMavenRepo())

  @After fun tearDown() {
    cacheDir.toFile().deleteRecursively()
    check(!Files.exists(cacheDir)) { "Failed to tear down and delete temp directory." }
  }

  @Test fun simpleResolution() {
    val args = configFlags("simple", "gen-maven-repo")
    val output = cmd.test(args)
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("Generated 1 build files in workspace")
    assertThat(output).contains("Resolved 1 artifacts with 100 threads in")
  }

  @Test fun excludesSuccess() {
    val args = configFlags("excludes-success", "gen-maven-repo")
    val output = cmd.test(args)
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("Generated 1 build files in workspace")
    assertThat(output).contains("Resolved 1 artifacts with 100 threads in")
  }

  @Test fun excludesFailure() {
    val args = configFlags("excludes-failure", "gen-maven-repo")
    val output = cmd.fail(args)
    assertThat(output).contains("Building workspace for 1 artifacts")
    assertThat(output).contains("Generated 1 build files in workspace")
    assertThat(output).contains("Resolved 1 artifacts with 100 threads in")

    assertThat(output)
      .contains("ERROR: Un-declared artifacts referenced in the dependencies of some artifacts.")
    assertThat(output)
      .contains(""""org.apache.maven:maven-builder-support:3.6.3": {"insecure": True}""")
    assertThat(output).contains(""""exclude": ["org.apache.maven:maven-builder-support"]""")
  }

  @Test fun largeListOfArtifacts() {
    val args = configFlags("large", "gen-maven-repo")
    val output = cmd.test(args)
    assertThat(output).contains("Building workspace for 468 artifacts")
    assertThat(output).contains("Generated 229 build files in workspace")
    assertThat(output).contains("Resolved 468 artifacts with 100 threads in")
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

    val output1 = cmd.test(configFlags("large", "gen-maven-repo"))
    val result1 = timingMatcher.find(output1)
    assertWithMessage("Expected to match ${timingMatcher.pattern}").that(result1).isNotNull()
    val time1 = result1!!.groupValues[1].toFloat()
    assertWithMessage("Expected non-cached first run, but run took $time1 seconds")
      .that(time1)
      .isGreaterThan(4.0f)

    assertThat(Files.exists(cacheDir.resolve("junit/junit/4.13/junit-4.13.pom"))).isTrue()
    val output2 = cmd.test(
      configFlags(
        "large",
        "gen-maven-repo",
        workspace = "workspace2",
        kramerArgs = listOf(
          "--repository=foo|localhost:0", // force fake repo for this run - all cache.
          "--local_maven_cache=$cacheDir"
        )
      )
    )
    val result2 = timingMatcher.find(output2)
    assertWithMessage("Expected to match ${timingMatcher.pattern}").that(result2).isNotNull()
    val time2 = result2!!.groupValues[1].toFloat()
    assertWithMessage("Expected fast cache run but took $time2 seconds")
      .that(time2)
      .isLessThan(3.0f)

    assertThat(output2).contains("Resolved 469 artifacts with 100 threads in ")
  }

  private fun configFlags(
    label: String,
    command: String,
    threads: Int = 100,
    workspace: String = "workspace",
    kramerArgs: List<String> = repoArgs
  ) =
    kramerArgs +
      command +
      "--threads=$threads" +
      "--workspace=$workspace" +
      "--configuration=$runfiles/$relativeDir/$packageDir/test-$label-config.json"

  /**
   * Executes a non-terminating run (via [CliktCommand.parse]) which traps any exceptions and
   * reports them, returning the output print stream as a string for assertions.
   *
   * For expected-errors, call [CliktCommand.fail].]
   */
  private fun CliktCommand.test(args: List<String>): String {
    println("Testing with args: [\n    ${args.joinToString("\n    ")}\n]")
    try {
      parse(args)
      return baos.toString()
    } catch (e: ProgramResult) {
      throw AssertionError("Program exited with unexpected code: ${e.statusCode}. output: $baos")
    } catch (e: Exception) {
      throw AssertionError("Exception running command:\n $baos", e)
    }
  }

  /**
   * Executes a non-terminating run (via [CliktCommand.parse]) asserts that the command failed
   * with a ProgramResult with a non-0 exit code, and returns the output stream, throwing an
   * [AssertionError] if the program returns without error.
   *
   * For regular no-error-expected tests, call [CliktCommand.test].]
   */
  private fun CliktCommand.fail(args: List<String>): String {
    println("Testing with args: [\n    ${args.joinToString("\n    ")}\n]")
    try {
      parse(args)
      throw AssertionError("Expected program to fail, but returned normally:\n $baos")
    } catch (e: ProgramResult) {
      if (e.statusCode == 0)
        throw AssertionError("Expected program to fail, but returned a 0 exit status:\n $baos")
      return baos.toString()
    } catch (e: Exception) {
      throw AssertionError("Unexpected exception running command:\n $baos", e)
    }
  }
}
