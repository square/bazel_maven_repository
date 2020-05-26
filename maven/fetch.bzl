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
load(":exec.bzl", "exec")

def _fetch_artifact_impl(ctx):
    repository_root_path = ctx.path(".")
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))
    spec = ":".join(ctx.attr.artifact.split(":")[0:3])  # Strip extra artifact elements.
    args = [
        exec.java_bin(ctx),
        "-jar",
        exec.exec_jar(ctx.path("."), ctx.attr._kramer_exec),
    ]
    for repo, url in ctx.attr.repository_urls.items():
        args.append("--repository=%s|%s" % (repo, url))
    args.append("fetch-artifact")
    args.append("--workspace=%s" % ctx.path("."))
    if bool(ctx.attr.sha256):
        args.append("--sha256=%s" % ctx.attr.sha256)
    args.append(spec)
    result = ctx.execute(args, timeout = 300, quiet = False)
    if result.return_code != 0:
        fail("Could not download %s - exit code %s:\n %s%s" % (
            ctx.attr.artifact,
            result.return_code,
            result.stderr,
            result.stdout,
        ))

fetch_artifact = repository_rule(
    implementation = _fetch_artifact_impl,
    attrs = {
        "artifact": attr.string(mandatory = True),
        "sha256": attr.string(),
        "repository_urls": attr.string_dict(mandatory = True),
        "_kramer_exec": attr.label(
            executable = True,
            cfg = "host",
            default = Label("//maven:kramer-resolve.jar"),
            allow_single_file = True,
        ),
    },
)
