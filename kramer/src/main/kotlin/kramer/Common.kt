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

import com.google.common.collect.ImmutableListMultimap
import com.squareup.tools.maven.resolution.Artifact
import java.security.MessageDigest
import org.apache.maven.model.Dependency
import org.apache.maven.model.Model

/*
 * Constants
 */

internal const val DOWNLOAD_PREFIX = "maven"
internal const val HEADER = """# Generated build file - do not modify"""
internal const val RAW_LOAD_HEADER_TEMPLATE = """
load("@%s//maven:jvm.bzl", "raw_jvm_import")
"""
internal const val ANDROID_LOAD_HEADER = """ 
load("@build_bazel_rules_android//android:rules.bzl", "android_library")
"""
internal val acceptedScopes = setOf("compile", "runtime")

/*
 * Core Library Stuff
 */

fun <K, V> Iterable<Pair<K, V>>.toImmutableListMultimap(): ImmutableListMultimap<K, V> =
  ImmutableListMultimap.Builder<K, V>().apply { forEach { (k, v) -> put(k, v) } }.build()

fun ByteArray.sha256(): String {
  val md = MessageDigest.getInstance("SHA-256")
  val digest = md.digest(this)
  return digest.fold("", { str, it -> str + "%02x".format(it) })
}

fun zeroOrOneOf(vararg conditions: Boolean): Boolean {
  return conditions.map { if (it) 1 else 0 }.reduce { acc, i -> acc + i } <= 1
}

/*
 *  Utilities to extract bazel paths/packages/targets from maven artifacts and dependencies.
 */

/** Fetch repository package prefix */
internal fun Artifact.fetchRepoPackage(): String {
  // Can't use third-party target formulation of artifactId as this is a repo name, not target.
  val group = groupId.replace(".", "_").replace("-", "_")
  val id = artifactId.replace(".", "_").replace("-", "_")
  return "@${group}_$id//$DOWNLOAD_PREFIX"
}

val Artifact.target: String get() = target(artifactId)
val Artifact.groupPath: String get() = groupPath(groupId)

val Dependency.target: String get() = target(artifactId)
val Dependency.groupPath: String get() = groupPath(groupId)

internal fun groupPath(string: String) = string.replace(".", "/")
internal fun target(string: String) = string.replace(".", "_")

/**
 * Create a dependency from a `groupId:artifactId` pair, with a fake version.
 * Used when rewriting dependencies in contexts where we don't have a version,
 * such as "include" or jetifier deps surgery.
 *
 * This function can take a more narrowly specified artifact, but will ignore
 * anything past groupId/artifactId
 */
internal fun unversionedDependency(it: String): Dependency {
  val (groupId, artifactId) = it.split(":")
  return Dependency().apply {
    this.groupId = groupId
    this.artifactId = artifactId
    this.version = "<SOME_VERSION>"
  }
}

/*
 * Miscellaneous
 */
val Dependency.slug: String get() = "$groupId:$artifactId"

/** Filters out any deps not to be propagated to runtime consumers */
fun filterBuildDeps(model: Model) {
  model.apply {
    dependencies = dependencies.filter { dep ->
      dep.scope.isNullOrBlank() || dep.scope in acceptedScopes
    }
  }
}
