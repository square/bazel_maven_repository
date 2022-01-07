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

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.findOrSetObject
import com.github.ajalt.clikt.core.subcommands
import com.github.ajalt.clikt.parameters.options.*
import com.github.ajalt.clikt.parameters.types.path
import com.squareup.tools.maven.resolution.GlobalConfig
import com.squareup.tools.maven.resolution.Repositories
import java.io.PrintStream
import org.apache.maven.model.Repository
import java.nio.file.FileSystem
import java.nio.file.FileSystems
import java.nio.file.Files
import java.nio.file.Path

fun main(vararg argv: String) = Kramer()
  .subcommands(FetchArtifactCommand(), GenerateMavenRepo())
  .main(argv.toList())

internal class Kramer(
  val fs: FileSystem = FileSystems.getDefault(),
  private val output: PrintStream = System.out
) : CliktCommand() {

  /** the settings overrides that might be supplied differently in different environments */
  private val settingsFile by option(
    "--settings",
    envvar = "BAZEL_MAVEN_SETTINGS",
    help = "Settings which can be optionally specified, which override values in the main config"
  ).path()

  /** the settings from the main specification that are used by all commands */
  private val configFile by option(
    "--config",
    help = "Settings which can be optionally specified, which override values in the main config"
  ).path(mustExist = true).required()

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

  internal val kontext by findOrSetObject {
    Kontext(verbosity = verbosity, localRepository = localRepository, output = output)
  }


  override fun run() {
    GlobalConfig.verbose = verbosity > 0
    GlobalConfig.debug = verbosity > 1
    val defaultSettingsFile = fs.getPath("${System.getProperties()["user.home"]}", ".m2/settings.json")
    kontext.settings = kontext.parseJson(
      settingsFile ?: if(Files.exists(defaultSettingsFile)) defaultSettingsFile else null,
      Settings()
    )
    kontext.config = kontext.parseJson(configFile, KramerConfig::class)
  }
}

internal class Kontext(
  val verbosity: Int = 0,
  val localRepository: Path,
  val output: PrintStream = System.out
) {
  lateinit var settings: Settings

  lateinit var config: KramerConfig

  val repositories: List<Repository> by lazy {
    val mirrors = settings.mirrors.map { it.id to it.url }.toMap()
    val repositories = config.repositories.ifEmpty { Repositories.DEFAULT }
    repositories.map { repo ->
      mirrors[repo.id]?.let { mirror ->
        Repository().apply {
          id = repo.id
          url = mirror
          releases = repo.releases
          snapshots = repo.snapshots
        }
      } ?: repo
    }
  }

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
