#
# Values and global functions shared across the whole infrastructure.  Local constants should stay defined in their
# own file.  This file includes functions with shared business logic, whereas pure utilities should go in utils, etc.
#
load(":utils.bzl", "strings")

DOWNLOAD_PREFIX = "maven"
PACKAGING_TYPE_FILE = "packaging_type"

_REPO_PREFIX = "maven_fetch"

def _group_path(artifact):
    return "/".join(artifact.group_id.split("."))

def _artifact_repo_name(artifact):
    # Extra empty strings are there to force "__" in between sections (to disambiguate
    # "foo:bar-parent:1.0" from "foo.bar:parent:1.0" in fetch repos.
    artifact_id_munged = strings.munge(artifact.artifact_id, ".", "-")
    munged_classifier_if_present = [strings.munge(artifact.classifier, ".", "-")] if artifact.classifier else []
    group_elements = artifact.group_id.split(".")
    return "_".join([_REPO_PREFIX, ""] + group_elements + ["", artifact_id_munged] + munged_classifier_if_present)

def _pom_repo_name(artifact):
    return "%s__pom" % _artifact_repo_name(artifact)

# The local path to a pom according to the standard maven layout.
def _artifact_path(artifact, suffix):
    return "{group_id}/{artifact_id}/{version}/{artifact_id}-{version}.{suffix}".format(
        group_id = _group_path(artifact),
        artifact_id = artifact.artifact_id,
        version = artifact.version,
        suffix = suffix,
    )

# The local path to a pom according to the standard maven layout.
def _pom_path(artifact):
    return "{group_id}/{artifact_id}/{version}/{artifact_id}-{version}.pom".format(
        group_id = _group_path(artifact),
        artifact_id = artifact.artifact_id,
        version = artifact.version,
    )

def _artifact_target(artifact, suffix):
    return Label("@%s//%s:%s" % (_artifact_repo_name(artifact), DOWNLOAD_PREFIX, _artifact_path(artifact, suffix)))

def _pom_target(artifact):
    return _pom_target_relative_to(artifact, _pom_repo_name(artifact))

def _pom_target_relative_to(artifact, workspace):
    return Label("@%s//%s:%s" % (workspace, DOWNLOAD_PREFIX, _pom_path(artifact)))

fetch_repo = struct(
    artifact_path = _artifact_path,
    artifact_repo_name = _artifact_repo_name,
    artifact_target = _artifact_target,
    pom_path = _pom_path,
    pom_target = _pom_target,
    pom_target_relative_to = _pom_target_relative_to,
    pom_repo_name = _pom_repo_name,
)
