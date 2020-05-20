package kramer

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.findOrSetObject
import com.github.ajalt.clikt.core.subcommands
import com.github.ajalt.clikt.parameters.options.convert
import com.github.ajalt.clikt.parameters.options.counted
import com.github.ajalt.clikt.parameters.options.default
import com.github.ajalt.clikt.parameters.options.multiple
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.types.path
import java.io.PrintStream
import java.nio.file.FileSystem
import java.nio.file.FileSystems
import java.nio.file.Path
import org.apache.maven.model.Repository
import org.apache.maven.model.RepositoryPolicy

fun main(vararg argv: String) = Kramer()
  .subcommands(ResolveArtifact(), GenerateMavenRepo())
  .main(argv.toList())

internal class Kramer(
  fs: FileSystem = FileSystems.getDefault(),
  private val output: PrintStream = System.out
) : CliktCommand() {

  private val repositories: List<Repository> by option("--repository").convert { p ->
    val fragments = p.split("|", limit = 4).toMutableList()
    val (id, url) = fragments
    var snapshots = "false"
    var releases = "true"
    with(fragments) {
      this.removeAt(0)
      this.removeAt(0)
      for (param in this) {
        val elements = param.split("=", limit = 2)
        if (elements.size != 2) fail("Invalid parameter $param to repository spec $p")
        val (type, value) = elements
        if (value !in setOf("true", "false")) fail("Invalid boolean $value in $p")
        when (type) {
          "snapshots" -> snapshots = value
          "releases" -> releases = value
          else -> fail("Invalid repository policy type $type in $p")
        }
      }
    }
    Repository().apply {
      this.id = id
      this.url = url
      this.releases = RepositoryPolicy().apply { this.enabled = releases }
      this.snapshots = RepositoryPolicy().apply { this.enabled = snapshots }
    }
  }.multiple()

  private val verbosity: Int by option(
    "-v", "--verbose",
    help = "Verbosity (can be specified multiple times)"
  ).counted()

  private val localRepository: Path by option(
    "--local_maven_cache",
    help = "The prefix into which maven artifacts will be cached (e.g. @maven//foo/bar). " +
      "The tool will create the local cache directory if it does not exist."
  )
    .path(canBeFile = false, canBeSymlink = false, canBeDir = true)
    .default(fs.getPath("${System.getProperties()["user.home"]}", ".m2/repository"))

  internal val kontext by findOrSetObject { Kontext() }

  override fun run() {
    kontext.output = output
    kontext.repositories = repositories
    kontext.verbosity = verbosity
    kontext.localRepository = localRepository
  }
}

internal class Kontext {
  var output: PrintStream = System.out
  lateinit var repositories: List<Repository>
  var verbosity: Int = 0
  lateinit var localRepository: Path

  fun out(newline: Boolean = true, msg: () -> String) {
    output.print(msg.invoke())
    if (newline) output.println()
  }

  fun info(newline: Boolean = true, msg: () -> String) {
    if (verbosity > 0) {
      output.print(msg.invoke())
      if (newline) output.println()
    }
  }

  fun verbose(newline: Boolean = true, msg: () -> String) {
    if (verbosity > 1) {
      output.print(msg.invoke())
      if (newline) output.println()
    }
  }
}
