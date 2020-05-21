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
import com.github.ajalt.clikt.core.requireObject
import com.github.ajalt.clikt.parameters.arguments.argument
import com.squareup.tools.maven.resolution.ArtifactResolver
import com.squareup.tools.maven.resolution.Repositories
import com.squareup.tools.maven.resolution.ResolvedArtifact
import kotlin.system.exitProcess
import kotlin.system.measureTimeMillis
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.runBlocking

internal class ResolveArtifactCommand() : CliktCommand(name = "resolve-artifact") {
  private val artifactSpec: String by argument()

  private val kontext by requireObject<Kontext>()

  @FlowPreview
  @ExperimentalCoroutinesApi
  override fun run() {
    val benchmark = measureTimeMillis {
      runBlocking {
        val resolver = ArtifactResolver(
          cacheDir = kontext.localRepository,
          suppressAddRepositoryWarnings = true,
          repositories =
          if (kontext.repositories.isNotEmpty()) kontext.repositories
          else Repositories.DEFAULT
        )
        val artifact = resolver.artifactFor(artifactSpec)
        val resolved: ResolvedArtifact? = resolver.resolveArtifact(artifact)
        if (resolved == null) {
          issueMessage("Could not resolve ${artifact.coordinate}!")
          exitProcess(1)
        }
        with(resolved) {
          println("$groupId:$artifactId:$version|${model.packaging}")
        }
      }
    }
    if (kontext.verbosity > 0) println("Resolved $artifactSpec in ${benchmark / 1000.0} seconds.")
  }
}
