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

import java.nio.file.Path

internal fun fetchArtifactTemplate(prefix: String, jars: List<Path>): String {
  val srcsText = jars.joinToString("") { "\n            \"$it\"," }

  return """
    package(default_visibility = ["//visibility:public"])
    filegroup(
        name = "$prefix",
        srcs = [$srcsText
        ],
    )
    """.trimIndent()
}

internal fun aarArtifactTemplate(prefix: String, jars: List<Path>): String {
  val srcsText = jars.joinToString("") { "\n            \"$it\"," }

  return """
    package(default_visibility = ["//visibility:public"])
    exports_files(["AndroidManifest.xml"] + glob(["libs/*.jar"]))

    filegroup(
        name = "$prefix",
        srcs = [$srcsText
        ],
    )

    filegroup(
        name = "resources",
        srcs = glob(["res/**/*"])
    )

    filegroup(
        name = "assets",
        srcs = glob(["assets/**/*"])
    )

    filegroup(
        name = "proguard",
        srcs = glob(["proguard.txt"])
    )
    """.trimIndent()
}

internal fun mavenAarTemplate(
  target: String,
  coordinate: String,
  customPackage: String,
  jetify: String,
  deps: String,
  fetchRepo: String,
  testonly: String,
  visibility: String,
  libs: List<Path>
) = """
# $coordinate raw classes
raw_jvm_import(
    name = "${target}_classes",
    jar = "$fetchRepo",$jetify
    deps = [$deps],
)

# $coordinate library target
android_library(
    name = "$target",
    manifest = "$fetchRepo:AndroidManifest.xml",
    custom_package = "$customPackage",
    visibility = $visibility,
    resource_files = ["$fetchRepo:resources"],
    assets = ["$fetchRepo:assets"],
    assets_dir = "assets",
    deps = [":${target}_classes"] + [${libTargets(target, libs)}] + [$deps],$testonly
    exports = [":${target}_classes"] + [${libTargets(target, libs)}],
)
${mavenAarLibsTemplate(target, jetify, fetchRepo, libs)}
"""

private fun libTargets(target: String, libs: List<Path>) =
  if (libs.isEmpty()) ""
  else libs.joinToString("\n", prefix = "\n", postfix = "\n    ") {
    """        ":${libTarget(target, it)}","""
  }

private fun libTarget(target: String, jar: Path) =
  "${target}_libs_${jar.fileName.toString().replace(".jar", "")}"

internal fun mavenAarLibsTemplate(
  target: String,
  jetify: String,
  fetchRepo: String,
  jars: List<Path>
) = jars.joinToString("\n") { jar -> """
raw_jvm_import(
    name = "${libTarget(target, jar)}",
    jar = "$fetchRepo:libs/${jar.fileName}",$jetify
)"""
}

internal fun mavenJarTemplate(
  target: String,
  coordinate: String,
  jetify: String,
  deps: String,
  fetchRepo: String,
  testonly: String,
  visibility: String
) = """
# $coordinate
raw_jvm_import(
    name = "$target",
    jar = "$fetchRepo",
    visibility = $visibility,$jetify
    deps = [$deps],$testonly
)
"""

internal fun mavenFileTemplate(
  target: String,
  coordinate: String,
  deps: String,
  fetchRepo: String,
  testonly: String,
  visibility: String
) = """
# $coordinate
filegroup(
    name = "$target",
    srcs = ["$fetchRepo"],
    visibility = $visibility,
    data = [$deps],$testonly
)
"""
