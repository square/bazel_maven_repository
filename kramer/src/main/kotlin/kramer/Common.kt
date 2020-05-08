package kramer

import com.google.common.collect.ImmutableListMultimap
import com.squareup.tools.maven.resolution.Artifact
import org.apache.maven.model.Dependency

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

// h/t swankjesse
data class Quad<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)
infix fun <A, B, C> Pair<A, B>.tre(c: C) = Triple(first, second, c)
infix fun <A, B, C, D> Triple<A, B, C>.fo(d: D) = Quad(first, second, third, d)

fun <K, V> Iterable<Pair<K, V>>.toImmutableListMultimap(): ImmutableListMultimap<K, V> =
  ImmutableListMultimap.Builder<K, V>().apply { forEach { (k, v) -> put(k, v) } }.build()

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

internal fun groupPath(string: String) = string.replace(".", "/").replace("-", "_")
internal fun target(string: String) = string.replace(".", "_")
