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
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.SUCCESSFUL
import com.squareup.tools.maven.resolution.FetchStatus.RepositoryFetchStatus.SUCCESSFUL.FOUND_IN_CACHE
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
    val status: FetchStatus,
    val hash: String
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
    if (status !is SUCCESSFUL) kontext.exit(1) {
      "ERROR: Could not resolve $spec! Attempted from ${repoList.map { it.url }}"
    }
    val hash = Files.readAllBytes(resolved.main.localFile).sha256()
    return FetchResult(resolved, status, hash)
  }

  override fun run() {
    var result: FetchResult? = null
    val benchmark = measureTimeMillis {
      result = fetch(artifactSpec)
      with(result!!) {
        if (sha256 != null && hash != sha256) kontext.exit(1) {
          val file = resolved.main.localFile
          "ERROR: $file hash ($hash) is not the expected hash ($sha256)"
        }
        for (file in listOf(resolved.pom, resolved.main)) {
          createDirectories(workspace.resolve(prefix).resolve(file.path).parent)
          copy(file.localFile, workspace.resolve(prefix).resolve(file.path), REPLACE_EXISTING)
        }
        val buildFile = workspace.resolve(prefix).resolve("BUILD.bazel")
        when (resolved.model.packaging.trim()) {
          "aar" -> {
            unzip(resolved.main.localFile, buildFile.parent)
            write(buildFile, AAR_DOWNLOAD_BUILD_FILE.lines(), CREATE)
          }
          else -> {
            write(buildFile, fetchArtifactTemplate(prefix, resolved.main.path).lines(), CREATE)
          }
        }
      }
    }
    with(result!!) {
      kontext.out {
        val fromCache = if (status == FOUND_IN_CACHE) " from cache" else ""
        val insecurely = if (sha256.isNullOrBlank()) " insecurely" else ""
        val shaOut = if (sha256 == null) "SHA256: $hash" else ""
        "Resolved $artifactSpec$insecurely$fromCache in ${benchmark / 1000.0} seconds. $shaOut"
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
