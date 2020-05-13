#
# Utilities for processing maven artifact coordinates and generating useful structs.
#

# Artifact types supported by maven_jvm_artifact()
_supported_jvm_artifact_packaging = [
    "jar",
    "aar",
]

# All supported artifact types (Can be extended for non-jvm packaging types.)
_supported_artifact_packaging = _supported_jvm_artifact_packaging

_artifact_template = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}.{suffix}"
_artifact_template_with_classifier = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}-{classifier}.{suffix}"
_artifact_pom_template = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}.pom"

# Builds a struct containing the basic coordinate elements of a maven artifact spec.
def _parse_spec(artifact_spec):
    parts = artifact_spec.split(":")
    packaging = "jar"
    classifier = None
    version = "UNKNOWN"

    # parse spec
    if len(parts) == 2:
        group_id, artifact_id = parts
    elif len(parts) == 3:
        group_id, artifact_id, version = parts
    elif len(parts) == 4:
        group_id, artifact_id, version, packaging = parts
    elif len(parts) == 5:
        group_id, artifact_id, version, packaging, classifier = parts
    else:
        fail("Invalid artifact: %s" % artifact_spec)

    return struct(
        original_spec = artifact_spec,
        coordinate = "%s:%s" % (group_id, artifact_id),
        group_id = group_id,
        artifact_id = artifact_id,
        packaging = packaging,
        classifier = classifier,
        version = version,
    )

def _munge_target(artifact_id):
    return artifact_id.replace("-", "_").replace(".", "_")

# Builds an annotated struct from a more basic artifact struct, with standard paths, names, and
# other values derived from the basic artifact spec elements.
def _annotate_artifact(artifact):
    if not bool(artifact.version):
        fail("Error, no version specified for %s:%s" % (artifact.group_id, artifact.artifact_id))

    # assemble paths and target names and such.
    group_elements = artifact.group_id.split(".")
    artifact_id_munged = _munge_target(artifact.artifact_id)
    munged_classifier_if_present = (artifact.classifier.split("-") if artifact.classifier else [])
    maven_target_elements = group_elements + [artifact_id_munged] + munged_classifier_if_present
    maven_target_name = "_".join(maven_target_elements)
    suffix = artifact.packaging  # TODO(cgruber) support better packaging mapping, to handle .bundles etc.
    group_path = "/".join(group_elements)
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
        maven_target_name = maven_target_name,
        third_party_target_name = artifact_id_munged,
        path = path,
        group_path = group_path,
        pom = pom,
        original_spec = artifact.original_spec,
        coordinate = artifact.coordinate,
        group_id = artifact.group_id,
        artifact_id = artifact.artifact_id,
        packaging = artifact.packaging,
        classifier = artifact.classifier,
        version = artifact.version,
    )
    return annotated_artifact

artifacts = struct(
    parse_spec = _parse_spec,
    annotate = _annotate_artifact,
    munge_target = _munge_target,
)
