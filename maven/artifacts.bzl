#
# Utilities for processing maven artifact coordinates and generating useful structs.
#
load(":utils.bzl", "strings")

_artifact_template = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}.{suffix}"
_artifact_template_with_classifier = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}-{classifier}.{suffix}"
_artifact_pom_template = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}.pom"

# Builds a struct containing the basic coordinate elements of a maven artifact spec.
def _parse_spec(artifact_spec):
    parts = artifact_spec.split(":")
    type = "jar"
    classifier = None
    version = "UNKNOWN"

    # parse spec
    if len(parts) == 2:
        group_id, artifact_id = parts
    elif len(parts) == 3:
        group_id, artifact_id, version = parts
    elif len(parts) == 4:
        group_id, artifact_id, version, type = parts
    elif len(parts) == 5:
        group_id, artifact_id, version, type, classifier = parts
    else:
        fail("Invalid artifact: %s" % artifact_spec)

    return struct(
        original_spec = artifact_spec,
        group_id = group_id,
        artifact_id = artifact_id,
        type = type,
        classifier = classifier,
        version = version,
    )

# Builds an annotated struct from a more basic artifact struct, with standard paths, names, and other values
# derived from the basic artifact spec elements.
def _annotate_artifact(artifact):
    if not bool(artifact.version):
        fail("Error, no version specified for %s:%s" % (artifact.group_id, artifact.artifact_id))

    # assemble paths and target names and such.
    suffix = artifact.type
    group_path = "/".join(artifact.group_id.split("."))
    if bool(artifact.classifier):
        path = None if not bool(artifact.version) else _artifact_template_with_classifier.format(
            group_path = group_path,
            artifact_id = artifact.artifact_id,
            version = artifact.version,
            suffix = suffix,
            classifier = artifact.classifier,
        )
    else:
        path = None if not bool(artifact.version) else _artifact_template.format(
            group_path = group_path,
            artifact_id = artifact.artifact_id,
            version = artifact.version,
            suffix = suffix,
        )
    pom = _artifact_pom_template.format(
        group_path = group_path,
        artifact_id = artifact.artifact_id,
        version = artifact.version,
    ) if bool(artifact.version) else None

    annotated_artifact = struct(
        path = path,
        group_path = group_path,
        pom = pom,
        original_spec = artifact.original_spec,
        group_id = artifact.group_id,
        artifact_id = artifact.artifact_id,
        type = artifact.type,
        classifier = artifact.classifier,
        version = artifact.version,
    )
    return annotated_artifact

artifacts = struct(
    parse_spec = _parse_spec,
    annotate = _annotate_artifact,
)
