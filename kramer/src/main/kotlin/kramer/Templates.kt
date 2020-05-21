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

internal fun aarTemplate(
  target: String,
  coordinate: String,
  customPackage: String,
  jetify: String,
  deps: String,
  fetchRepo: String,
  testonly: String,
  visibility: String
) = """
# $coordinate raw classes
raw_jvm_import(
    name = "${target}_classes",
    jar = "$fetchRepo:classes.jar",$jetify
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
    deps = [":${target}_classes"] + [$deps],$testonly
)
"""

internal fun jarTemplate(
  target: String,
  coordinate: String,
  jarPath: String,
  jetify: String,
  deps: String,
  fetchRepo: String,
  testonly: String,
  visibility: String
) = """
# $coordinate
raw_jvm_import(
    name = "$target",
    jar = "$fetchRepo:$jarPath",
    visibility = $visibility,$jetify
    deps = [$deps],$testonly
)
"""
