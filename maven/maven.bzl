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

_artifact_template = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}.{suffix}"
_artifact_template_with_classifier = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}-{classifier}.{suffix}"
_artifact_pom_template = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}.pom"

# Artifact types supported by maven_jvm_artifact()
_supported_jvm_artifact_packaging = [
    "jar",
    "aar",
]
# All supported artifact types (Can be extended for non-jvm packaging types.)
_supported_artifact_packaging = _supported_jvm_artifact_packaging

_DOWNLOAD_PREFIX = "file"

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

def _maven_repository_impl(ctx):
    repository_root_path = ctx.path(".")
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))

    artifacts = ctx.attr.artifacts
    groups = ctx.attr.groups
    for group_id, specs in groups.items():
        specs = sets.add_all(sets.new(), specs)
        prefix = _MAVEN_REPO_BUILD_PREFIX.format(
            group_id = group_id, maven_rules_repository = ctx.attr.maven_rules_repository)
        target_definitions = []
        for spec in specs:
            artifact = _parse_maven_artifact_spec(spec)
            group_path = "/".join(artifact.group_id.split("."))
            target_definitions += [
                _MAVEN_REPO_TARGET_TEMPLATE.format(
                    target = artifact.third_party_target_name,
                    artifact_coordinates = artifact.spec,
                )
            ]
        ctx.file(
            "%s/BUILD" % group_path,
            "\n".join([prefix] + target_definitions),
        )

_internal_maven_repository = repository_rule(
    implementation = _maven_repository_impl,
    attrs = {
        "artifacts": attr.string_dict(mandatory = True),
        "groups": attr.string_list_dict(mandatory = True),
        "maven_rules_repository": attr.string(mandatory = False, default = "maven_repository_rules"),
    },
)

def _parse_maven_artifact_spec(artifact_spec):
    """ Builds a struct containing various paths, target names, and other derivatives from the artifact spec.

        Intended only for use in other maven-oriented rules.
    """
    parts = artifact_spec.split(":")
    packaging = "jar"
    classifier = None

    # parse spec
    if len(parts) == 3:
        group_id, artifact_id, version = parts
    elif len(parts) == 4:
        group_id, artifact_id, version, packaging = parts
    elif len(parts) == 5:
        group_id, artifact_id, version, packaging, classifier = parts
    else:
        fail("Invalid artifact: %s" % artifact_spec)

    # assemble paths and target names and such.
    group_elements = group_id.split(".")
    artifact_id_elements = artifact_id.split("-")
    artifact_id_elements = "_".join(artifact_id_elements).split(".")
    maven_target_elements = group_elements + artifact_id_elements + (classifier.split("-") if classifier else [])
    maven_target_name = "_".join(maven_target_elements)
    third_party_target_name = "_".join(artifact_id_elements)
    suffix = packaging # TODO(cgruber) support better packaging mapping, to handle .bundles which return jars, etc.
    group_path = "/".join(group_elements)
    if classifier:
        artifact_relative_path = None if not version else _artifact_template_with_classifier.format(
            group_path = group_path,
            artifact_id = artifact_id,
            version = version,
            suffix = suffix,
            classifier = classifier,
        )
    else:
        artifact_relative_path = None if not version else _artifact_template.format(
            group_path = group_path,
            artifact_id = artifact_id,
            version = version,
            suffix = suffix,
        )
    artifact_relative_pom_path = _artifact_pom_template.format(
        group_path = group_path,
        artifact_id = artifact_id,
        version = version,
    ) if version else None

    return struct(
        maven_target_name = maven_target_name,
        third_party_target_name = third_party_target_name,
        artifact_relative_path = artifact_relative_path,
        artifact_relative_pom_path = artifact_relative_pom_path,
        spec = artifact_spec,
        group_id = group_id,
        artifact_id = artifact_id,
        packaging = packaging,
        classifier = classifier,
        version = version,
    )

def _maven_jvm_artifact(artifact_spec, name, visibility, deps = [], exports = [],  **kwargs):
    artifact = _parse_maven_artifact_spec(artifact_spec)
    maven_target = "@%s//%s:%s" % (artifact.maven_target_name, _DOWNLOAD_PREFIX, artifact.artifact_relative_path)
    import_target = artifact.maven_target_name + "_import"
    target_name = name if name else artifact.third_party_target_name
    exports = exports + deps # A temporary hack since the existing third_party artifacts use exports instead of deps.
    if artifact.packaging == "jar":
        native.java_import(name = target_name, deps = exports, exports = exports, visibility = visibility, jars = [maven_target], **kwargs)
    elif artifact.packaging == "aar":
        native.aar_import(name = target_name, deps = exports, exports = exports, visibility = visibility, aar = maven_target, **kwargs)
    else:
        fail("Packaging %s not supported by maven_jvm_artifact." % artifact.packaging)

def maven_jvm_artifact(artifact, name = None, deps = [], exports = [], visibility = ["//visibility:public"], **kwargs):
    """Creates java or android library targets from maven_hosted .jar/.aar files."""
    # redirect to _maven_jvm_artifact, so we can externally use the name "artifact" but internally use artifact_spec
    _maven_jvm_artifact(artifact_spec = artifact, name = name, deps = deps, exports = exports, visibility = visibility, **kwargs)

def _check_for_duplicates(artifacts):
    distinct_artifacts = {}
    for artifact_spec in artifacts:
        artifact = _parse_maven_artifact_spec(artifact_spec)
        distinct = "%s:%s" % (artifact.group_id, artifact.artifact_id)
        if not distinct_artifacts.get(distinct):
            distinct_artifacts[distinct] = {}
        sets.add(distinct_artifacts[distinct], artifact.version)
    for artifact, versions in distinct_artifacts.items():
        if len(versions.keys()) > 1:
            fail("Several versions of %s are specified in maven_artifacts.bzl: %s" % (artifact, versions.keys()))
        elif sets.pop(versions).endswith("-SNAPSHOT"):
            fail("Snapshot versions are not supported in maven_artifacts.bzl.  Please fix %s to a pinned version." % artifact);

def _validate_not_insecure_artifacts(artifacts = {}):
    insecure_artifacts = {}
    for spec, sha in artifacts.items():
        if not bool(sha):
            insecure_artifacts += { spec : sha }
    if bool(insecure_artifacts):
        fail("\n%s %s [\n%s]" % (
             "These artifacts were specified without sha256 hashes.",
             "Either add hashes or move to insecure_artifacts:",
             "".join(sorted(["    \"%s\",\n" % x for x in insecure_artifacts.keys()]))
        ))

def maven_repository_specification(
        name,
        artifacts = {},
        insecure_artifacts = [],
        repository_urls = ["https://repo1.maven.org/maven2"]):
    """Generates the bazel repo and download logic for each artifact (and repository URL prefixes) in the WORKSPACE."""

    _validate_not_insecure_artifacts(artifacts)

    for spec in insecure_artifacts:
        artifacts += { spec : "" }
    if len(repository_urls) == 0:
        fail("You must specify at least one repository root url.")
    if len(artifacts) == 0:
        fail("You must register at least one artifact.")
    _check_for_duplicates(artifacts)
    group_ids = {}
    for artifact_spec, sha256 in artifacts.items():
        artifact = _parse_maven_artifact_spec(artifact_spec)

        # Track group_ids in order to build per-group BUILD files.
        group_ids[artifact.group_id] = group_ids.get(artifact.group_id, default = []) + [artifact.spec]

        if not bool(sha256):
            sha256 = None
        urls = []
        for repo in repository_urls:
            urls += ["%s/%s" % (repo, artifact.artifact_relative_path)]
        _fetch_artifact(
            name = artifact.maven_target_name,
            urls = urls,
            local_path = artifact.artifact_relative_path,
            sha256 = sha256,
        )
    _internal_maven_repository(name = name, artifacts = artifacts, groups = group_ids)
