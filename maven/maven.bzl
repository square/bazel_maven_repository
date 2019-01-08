#
# Copyright (C) 2018 Square, Inc.
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
#   A repository rule intended to be used in populating @maven_repository.
#
load(":sets.bzl", "sets")
load(":artifacts.bzl", "artifacts")

_DOWNLOAD_PREFIX = "maven"

_ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE = """
package(default_visibility = ["//visibility:public"])
filegroup(
    name = "{prefix}",
    srcs = ["{path}"],
)
"""

def _fetch_artifact_impl(ctx):
    repository_root_path = ctx.path(".")
    forbidden_files = [
        repository_root_path,
        ctx.path("WORKSPACE"),
        ctx.path("BUILD"),
        ctx.path("BUILD.bazel"),
        ctx.path("%s/BUILD" % _DOWNLOAD_PREFIX),
        ctx.path("%s/BUILD.bazel" % _DOWNLOAD_PREFIX),
    ]
    local_path = "%s/%s" % (_DOWNLOAD_PREFIX, ctx.attr.local_path)
    download_path = ctx.path(local_path)
    if download_path in forbidden_files or not str(download_path).startswith(str(repository_root_path)):
        fail("Invalid local_path: %s" % ctx.attr.local_path)
    ctx.download(url = ctx.attr.urls, output = local_path, sha256 = ctx.attr.sha256)
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))
    ctx.file(
        "%s/BUILD" % _DOWNLOAD_PREFIX,
        _ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE.format(prefix = _DOWNLOAD_PREFIX, path = ctx.attr.local_path)
    )

_fetch_artifact = repository_rule(
    implementation = _fetch_artifact_impl,
    attrs = {
        "local_path": attr.string(),
        "sha256": attr.string(),
        "urls": attr.string_list(mandatory = True),
    },
)

_MAVEN_REPO_BUILD_PREFIX = """# Generated bazel build file for maven group {group_id}

load("@{maven_rules_repository}//maven:maven.bzl", "maven_jvm_artifact")
"""

_MAVEN_REPO_TARGET_TEMPLATE = """maven_jvm_artifact(
    name = "{target}",
    artifact = "{artifact_coordinates}",
)
"""

def _generate_maven_repository_impl(ctx):
    # Generate the root WORKSPACE file
    repository_root_path = ctx.path(".")
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))

    # Generate the per-group_id BUILD files.
    build_substitutes = ctx.attr.build_substitutes
    for group_id, specs in ctx.attr.grouped_artifacts.items():
        ctx.report_progress("Generating build details for artifacts in %s" % group_id)
        specs = sets.add_all(sets.new(), specs)
        prefix = _MAVEN_REPO_BUILD_PREFIX.format(
            group_id = group_id, maven_rules_repository = ctx.attr.maven_rules_repository)
        target_definitions = []
        group_path = group_id.replace(".", "/")
        for spec in specs:
            artifact = artifacts.annotate(artifacts.parse_spec(spec))
            target_definitions += [
                build_substitutes.get(
                    "%s:%s" % (artifact.group_id, artifact.artifact_id),
                    _MAVEN_REPO_TARGET_TEMPLATE.format(
                        target = artifact.third_party_target_name,
                        artifact_coordinates = artifact.original_spec,
                    )
                )
            ]
        ctx.file(
            "%s/BUILD" % group_path,
            "\n".join([prefix] + target_definitions),
        )

_generate_maven_repository = repository_rule(
    implementation = _generate_maven_repository_impl,
    attrs = {
        "grouped_artifacts": attr.string_list_dict(mandatory = True),
        "maven_rules_repository": attr.string(mandatory = False, default = "maven_repository_rules"),
        "build_substitutes": attr.string_dict(mandatory = True),
    },
)

# Implementation of the maven_jvm_artifact rule.
def _maven_jvm_artifact(artifact_spec, name, visibility, deps = [], exports = [],  **kwargs):
    artifact = artifacts.annotate(artifacts.parse_spec(artifact_spec))
    maven_target = "@%s//%s:%s" % (artifact.maven_target_name, _DOWNLOAD_PREFIX, artifact.path)
    import_target = artifact.maven_target_name + "_import"
    target_name = name if name else artifact.third_party_target_name
    exports = exports + deps # A temporary hack since the existing third_party artifacts use exports instead of deps.
    if artifact.packaging == "jar":
        native.java_import(name = target_name, deps = exports, exports = exports, visibility = visibility, jars = [maven_target], **kwargs)
    elif artifact.packaging == "aar":
        native.aar_import(name = target_name, deps = exports, exports = exports, visibility = visibility, aar = maven_target, **kwargs)
    else:
        fail("Packaging %s not supported by maven_jvm_artifact." % artifact.packaging)

# Check... you know... for duplicates.  And fail if there are any, listing the extra artifacts.  Also fail if
# there are -SNAPSHOT versions, since bazel requires pinned versions.
def _check_for_duplicates(artifact_specs):
    distinct_artifacts = {}
    for artifact_spec in artifact_specs:
        artifact = artifacts.parse_spec(artifact_spec)
        distinct = "%s:%s" % (artifact.group_id, artifact.artifact_id)
        if not distinct_artifacts.get(distinct):
            distinct_artifacts[distinct] = {}
        sets.add(distinct_artifacts[distinct], artifact.version)
    for artifact, versions in distinct_artifacts.items():
        if len(versions.keys()) > 1:
            fail("Several versions of %s are specified in maven_artifacts.bzl: %s" % (artifact, versions.keys()))
        elif sets.pop(versions).endswith("-SNAPSHOT"):
            fail("Snapshot versions are not supported in maven_artifacts.bzl.  Please fix %s to a pinned version." % artifact);

# If artifact/sha pair has missing sha hashes, reject it.
def _validate_no_insecure_artifacts(artifact_specs = {}):
    insecure_artifacts = {}
    for spec, sha in artifact_specs.items():
        if not bool(sha):
            insecure_artifacts += { spec : sha }
    if bool(insecure_artifacts):
        fail("\n%s %s [\n%s]" % (
             "These artifacts were specified without sha256 hashes.",
             "Either add hashes or move to insecure_artifacts:",
             "".join(sorted(["    \"%s\",\n" % x for x in insecure_artifacts.keys()]))
        ))

# The implementation of maven_repository_specification.
#
# Validates that all artifacts have sha hashes (or are in insecure_artifacts), splits artifacts into groups based on
# their groupId, generates a fetch rule for each artifact, and calls the rule which generates the internal bazel
# repository which replicates the maven repo structure.
#
def _maven_repository_specification(
        name,
        artifact_specs = {},
        insecure_artifacts = [],
        build_substitutes = {},
        repository_urls = ["https://repo1.maven.org/maven2"]):

    _validate_no_insecure_artifacts(artifact_specs)

    for spec in insecure_artifacts:
        artifact_specs += { spec : "" }
    if len(repository_urls) == 0:
        fail("You must specify at least one repository root url.")
    if len(artifact_specs) == 0:
        fail("You must register at least one artifact.")
    _check_for_duplicates(artifact_specs)
    grouped_artifacts = {}
    for artifact_spec, sha256 in artifact_specs.items():
        artifact = artifacts.annotate(artifacts.parse_spec(artifact_spec))

        # Track group_ids in order to build per-group BUILD files.
        grouped_artifacts[artifact.group_id] = (
            grouped_artifacts.get(artifact.group_id, default = []) + [artifact.original_spec])

        if not bool(sha256):
            sha256 = None # tidy empty strings - invalid shas will be rejected by the repository_ctx.download function.
        urls = ["%s/%s" % (repo, artifact.path) for repo in repository_urls]
        _fetch_artifact(
            name = artifact.maven_target_name,
            urls = urls,
            local_path = artifact.path,
            sha256 = sha256,
        )
    _generate_maven_repository(
        name = name,
        grouped_artifacts = grouped_artifacts,
        build_substitutes = build_substitutes,
    )


####################
# PUBLIC FUNCTIONS #
####################

# Creates java or android library targets from maven_hosted .jar/.aar files.
def maven_jvm_artifact(artifact, name = None, deps = [], exports = [], visibility = ["//visibility:public"], **kwargs):
    # redirect to _maven_jvm_artifact, so we can externally use the name "artifact" but internally use artifact_spec
    _maven_jvm_artifact(artifact_spec = artifact, name = name, deps = deps, exports = exports, visibility = visibility, **kwargs)


# Description:
#   Generates the bazel repo and download logic for each artifact (and repository URL prefixes) in the WORKSPACE
#   Makes a bazel repository out of the artifacts supplied, downloading them into a well-ordered repository structure,
#   targets (by default, including name mangling).
#
#   A substitution mechanism is present to permit swapping in alternative build rules, say for cases where you need
#   to use an `exported_plugins` property, e.g. using dagger.  The text supplied naively replaces the automatically
#   generated `maven_jvm_artifact()` rule.
#
def maven_repository_specification(
        name,
        artifacts = {},
        insecure_artifacts = [],
        build_substitutes = {},
        repository_urls = ["https://repo1.maven.org/maven2"]):
    # Redirected to _maven_repository_specification to allow the public parameter "artifacts" without conflicting
    # with the artifact utility struct.
    _maven_repository_specification(
        name = name,
        artifact_specs = artifacts,
        insecure_artifacts = insecure_artifacts,
        build_substitutes = build_substitutes,
        repository_urls = repository_urls,
    )
