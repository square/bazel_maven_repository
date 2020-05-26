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
import com.github.ajalt.clikt.core.ProgramResult
import com.github.ajalt.clikt.core.requireObject
import com.github.ajalt.clikt.parameters.arguments.argument
import com.github.ajalt.clikt.parameters.options.default
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.options.required
import com.github.ajalt.clikt.parameters.types.path
import com.squareup.tools.maven.resolution.ArtifactResolver
import com.squareup.tools.maven.resolution.FetchStatus
import com.squareup.tools.maven.resolution.FetchStatus.ERROR
import com.squareup.tools.maven.resolution.FetchStatus.INVALID_HASH
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.FETCH_ERROR
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.NOT_FOUND
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.SUCCESSFUL
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.SUCCESSFUL.FOUND_IN_CACHE
import com.squareup.tools.maven.resolution.FileSpec
import com.squareup.tools.maven.resolution.Repositories.Companion.DEFAULT
import com.squareup.tools.maven.resolution.ResolvedArtifact
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Files.copy
import java.nio.file.Files.createDirectories
import java.nio.file.Files.newInputStream
import java.nio.file.Files.write
import java.nio.file.Path
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import java.nio.file.StandardOpenOption.CREATE
import java.util.zip.ZipInputStream
import kotlin.system.measureTimeMillis

internal class FetchArtifactCommand() : CliktCommand(name = "fetch-artifact") {
  internal val workspace: Path by option(
    "--workspace",
    help = "Path to the workspace to be generated."
  )
    .path(canBeFile = false, canBeSymlink = false, canBeDir = true)
    .required()

  private val sha256: String? by option(
    "--sha256",
    help = "A sha to which the main artifact content is expected to hash."
  )

  internal val prefix: String by option(
    "--prefix",
    help = "Folder under the workspace into which the artifact will be downloaded."
  ).default("maven")

  private val artifactSpec: String by argument()

  private val kontext by requireObject<Kontext>()

  private fun Kontext.exit(code: Int, msg: () -> String): Nothing {
    out(msg = msg)
    throw ProgramResult(code)
  }

  data class FetchResult(
    val resolved: ResolvedArtifact,
    val status: FetchStatus
  )

  private fun fetch(spec: String): FetchResult {
    val repoList = if (kontext.repositories.isNotEmpty()) kontext.repositories else DEFAULT
    val resolver = ArtifactResolver(
      cacheDir = kontext.localRepository,
      suppressAddRepositoryWarnings = true,
      repositories = repoList
    )
    val artifact = resolver.artifactFor(spec)
    val resolved: ResolvedArtifact = resolver.resolveArtifact(artifact) ?: kontext.exit(1) {
      "ERROR: Could not resolve $spec! Attempted from ${repoList.map { it.url }}"
    }
    val status = resolver.downloadArtifact(artifact = resolved)
    when (status) {
      is SUCCESSFUL -> {}
      is INVALID_HASH ->  kontext.exit(1) {
        "ERROR: Invalid maven hashes for $spec from ${repoList.map { it.url }}. " +
          "Check that ${resolved.main.localFile} is the expected file."
      }
      is FETCH_ERROR -> kontext.exit(1) {
        "ERROR: Problem fetching main artifact for $spec from ${status.repository}: " +
          "(${status.responseCode}) ${status.message}"
      }
      is NOT_FOUND -> kontext.exit(1) {
        "ERROR: Artifact $spec not found at ${repoList.first().url}/${resolved.main.path}"
      }
      is ERROR -> kontext.exit(1) {
        // Errors from all download attempts, so enumerate them.
        "ERROR: Problem fetching main artifact for $spec:\n" +
          status.errors.entries.joinToString("\n") { (repoId, status) ->
            val repo = repoList.find { it.id == repoId }!!
            val message =
              when (status) {
                is NOT_FOUND -> "(404 - not found)"
                is FETCH_ERROR -> "(${status.responseCode}) \"${status.message}\""
                is SUCCESSFUL ->
                  throw AssertionError("Successful should not be returned in an error case.")
              }
            "    - $message from ${repo.url}/${resolved.main.path}"
          }
      }
    }
    return FetchResult(resolved, status)
  }

  override fun run() {
    var result: FetchResult? = null
    val benchmark = measureTimeMillis {
      result = fetch(artifactSpec)
      with(result!!) {
        if (sha256 != null) {
          val hash = Files.readAllBytes(resolved.main.localFile).sha256()
          if (hash != sha256) kontext.exit(1) {
            val file = resolved.main.localFile
            "ERROR: $file hash ($hash) is not the expected hash ($sha256)"
          }
        }
        val buildFile = workspace.resolve(prefix).resolve("BUILD.bazel")
        when (resolved.model.packaging.trim()) {
          "aar" -> {
            linkOrCopy(resolved.pom)
            unzip(resolved.main.localFile, buildFile.parent)
            write(buildFile, AAR_DOWNLOAD_BUILD_FILE.lines(), CREATE)
          }
          else -> {
            linkOrCopy(resolved.pom)
            linkOrCopy(resolved.main)
            write(buildFile, fetchArtifactTemplate(prefix, resolved.main.path).lines(), CREATE)
          }
        }
      }
    }
    with(result!!) {
      kontext.info {
        val fromCache = if (status == FOUND_IN_CACHE) " from cache" else ""
        val insecurely = if (sha256.isNullOrBlank()) " insecurely" else ""
        "Fetched $artifactSpec$insecurely$fromCache in ${benchmark / 1000.0} seconds."
      }
    }
  }

  private fun linkOrCopy(file: FileSpec) {
    createDirectories(workspace.resolve(prefix).resolve(file.path).parent)
    val destination = workspace.resolve(prefix).resolve(file.path)
    val source = file.localFile
    try {
      Files.createLink(destination, source)
      kontext.verbose { "Hard link created from $source to $destination" }
    } catch (e: Exception) {
      try {
        Files.createSymbolicLink(destination, source)
        kontext.verbose { "Symbolic link created from $source to $destination" }
      } catch (e: Exception) {
        copy(source, destination, REPLACE_EXISTING)
        kontext.verbose { "File copied from $source to $destination" }
      }
    }
  }

  fun unzip(zipfile: Path, dir: Path) {
    val root: Path = dir.normalize()
    newInputStream(zipfile).use { input ->
      ZipInputStream(input).use { stream ->
        var entry = stream.nextEntry
        while (entry != null) {
          val path = root.resolve(entry.name).normalize()
          if (!path.startsWith(root)) throw IOException("Invalid ZIP")
          if (entry.isDirectory) createDirectories(path)
          else Files.newOutputStream(path).use { out ->
            var len: Int
            val buffer = ByteArray(1024)
            while (stream.read(buffer).also { len = it } > 0) {
              out.write(buffer, 0, len)
            }
          }
          entry = stream.nextEntry
        }
        stream.closeEntry()
      }
    }
  }
}
