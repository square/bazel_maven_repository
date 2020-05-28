#
# Copyright (C) 2020 Square, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
# in compliance with the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License
# is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing permissions and limitations under
# the License.
load("@bazel_tools//tools/build_defs/repo:http.bzl", _http_archive = "http_archive")
load(":sets.bzl", "sets")

# Literal and glob pattern matches for artifacts that should not have jetifier applied.
# These can be overridden in the main call using maven_repository_specification(jetifier_excludes=)
DEFAULT_JETIFIER_EXCLUDED_ARTIFACTS = [
    "javax.*:*",
    "*:jsr305",
    "*:javac-shaded",
    "*:google-java-format",
    "com.squareup:javapoet",
    "com.google.dagger:*",
    "org.bouncycastle*:*",
    "androidx*:*",
    "org.jetbrains.kotlin*:*",
    "com.android.tools:*",
    "com.android.tools.build:*",
]

BUILD_FILE_CONTENT = """
java_import(
    name = "jetifier_standalone_jars",
    jars = glob(["lib/*.jar"]),
)
java_binary(
    main_class = "com.android.tools.build.jetifier.standalone.Main",
    name = "jetifier_standalone",
    runtime_deps = [
        ":jetifier_standalone_jars"
    ],
    visibility = ["//visibility:public"],
)
"""

def jetifier_init():
    _http_archive(
        sha256 = "8ef877e8245f8dcf8f379b2cdc4958ba714147eb8d559d8334a1840e137e5a2c",
        strip_prefix = "jetifier-standalone",
        name = "bazel_maven_repository_jetifier",
        url = "https://dl.google.com/dl/android/studio/jetifier-zips/1.0.0-beta08/jetifier-standalone.zip",
        build_file_content = BUILD_FILE_CONTENT,
    )

# jetify_jar based on https://github.com/bazelbuild/tools_android/pull/5
def jetify_jar(ctx, jar):
    basename = jar.basename.rsplit(".", 1)[0]
    jetified_outfile = ctx.actions.declare_file("%s-jetified.%s" % (basename, jar.extension))
    jetify_args = ctx.actions.args()
    jetify_args.add_all(["-l", "error"])
    jetify_args.add_all(["-o", jetified_outfile])
    jetify_args.add_all(["-i", jar])
    ctx.actions.run(
        mnemonic = "Jetify",
        inputs = [jar],
        outputs = [jetified_outfile],
        progress_message = "Jetifying {} to create {}.".format(jar.path, jetified_outfile.path),
        executable = ctx.executable._jetifier,
        arguments = [jetify_args],
        use_default_shell_env = True,
    )
    return jetified_outfile
