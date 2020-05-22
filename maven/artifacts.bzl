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

#
# Utilities for processing maven artifact coordinates and generating useful structs.
#

_artifact_template = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}.{suffix}"
_artifact_template_with_classifier = "{group_path}/{artifact_id}/{version}/{artifact_id}-{version}-{classifier}.{suffix}"

# Builds a struct containing the basic coordinate elements of a maven artifact spec.
def _parse_spec(artifact_spec):
    return _parse_elements(artifact_spec.split(":"))

def _parse_elements(parts):
    packaging = "jar"
    classifier = None
    version = "UNKNOWN"

    # parse spec
    if len(parts) == 2:
        group_id, artifact_id = parts
    elif len(parts) == 3:
        group_id, artifact_id, version = parts
    else:
        fail("Invalid artifact (should be \"group_id:artifact_id:version\": %s" % ":".join(parts))

    return struct(
        original_spec = ":".join(parts),
        coordinate = "%s:%s" % (group_id, artifact_id),
        group_id = group_id,
        artifact_id = artifact_id,
        packaging = packaging,
        classifier = classifier,
        version = version,
    )

def _mangle_target(artifact_id):
    return artifact_id.replace(".", "_")

def _fetch_repo(artifact):
    group_elements = artifact.group_id.split(".")
    artifact_elements = artifact.artifact_id.replace("-", ".").split(".")
    munged_classifier_if_present = (artifact.classifier.split("-") if artifact.classifier else [])
    maven_target_elements = group_elements + artifact_elements + munged_classifier_if_present
    return "_".join(maven_target_elements).replace("-", "_")

def _package_path(artifact):
    return artifact.group_id.replace(".", "/")

def _artifact_path(artifact, suffix, classifier = None):
    if classifier:
        return _artifact_template_with_classifier.format(
            group_path = artifacts.package_path(artifact),
            artifact_id = artifact.artifact_id,
            version = artifact.version,
            suffix = suffix,
            classifier = artifact.classifier,
        )
    else:
        return _artifact_template.format(
            group_path = artifacts.package_path(artifact),
            artifact_id = artifact.artifact_id,
            version = artifact.version,
            suffix = suffix,
        )

artifacts = struct(
    mangle_target = _mangle_target,
    artifact_path = _artifact_path,
    package_path = _package_path,
    parse_spec = _parse_spec,
    fetch_repo = _fetch_repo,
)
