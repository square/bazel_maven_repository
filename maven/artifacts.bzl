#
# Utilities for processing maven artifact specs and generating useful structs.
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
        coordinates = "%s:%s" % (group_id, artifact_id) # versionless coordinates
    )

artifacts = struct(
    parse_spec = _parse_spec,
)
