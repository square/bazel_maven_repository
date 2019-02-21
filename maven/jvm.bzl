#
# Copyright (C) 2019 Square, Inc.
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

# Description:
#   A custom import rule that doesn't return an ijar, instead returning the raw .jar file as
#   the "compile_jar".  This avoids issues with kotlin and inline functions.  Inspired by
#   kt_jvm_import in bazelbuild/rules_kotlin.
#   (see bazelbuild/bazel#4549)
#
def _raw_jvm_import(ctx):
    jars = []
    source_jars = []

    for file in ctx.files.jar:
        if file.basename.endswith("-sources.jar"):
            source_jars.append(file)
        elif file.basename.endswith(".jar"):
            jars.append(file)
        else:
            fail("a jar contained in a filegroup must either end with -sources.jar or .jar")

    if JavaInfo in ctx.attr.jar:
        fail("""
    raw_jvm_import(jars=%s) must point to a filegroup containing one binary .jar and optionally one
    -sources.jar. Found a java library or import instead: %s %s""" % (ctx.attr.jar, jars, source_jars))
    if len(jars) != 1 or len(source_jars) > 1:
        fail("""
    Supplied jar parameter (%s) transitively included more than one binary jar and one (optional)
    source jar.  Found: %s, %s""" % (ctx.file.jar, jars, source_jars))

    return [
        DefaultInfo(files = depset(jars)),
        JavaInfo(
            output_jar = jars[0],
            compile_jar = jars[0],
            source_jar = source_jars[0] if bool(source_jars) else None,
            deps = [dep[JavaInfo] for dep in ctx.attr.deps if JavaInfo in dep],
            runtime_deps = [dep[JavaInfo] for dep in ctx.attr.runtime_deps if JavaInfo in dep],
            neverlink = getattr(ctx.attr, "neverlink", False),
        ),
    ]

raw_jvm_import = rule(
    attrs = {
        "jar": attr.label(
            allow_files = True,
            mandatory = True,
            cfg = "target",
        ),
        "deps": attr.label_list(
            default = [],
            mandatory = False,
            providers = [JavaInfo],
        ),
        "runtime_deps": attr.label_list(
            default = [],
            mandatory = False,
            providers = [JavaInfo],
        ),
        "neverlink": attr.bool(default = False),
    },
    implementation = _raw_jvm_import,
    provides = [JavaInfo],
)
