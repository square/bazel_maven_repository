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
# Utilities for processing maven artifact coordinates.
#

# Builds a struct containing the basic coordinate elements of a maven artifact spec.
def _parse_spec(artifact_spec):
    parts = artifact_spec.split(":")

    # parse spec
    if len(parts) == 3:
        group_id, artifact_id, version = parts
    else:
        fail("Invalid artifact (should be \"group_id:artifact_id:version\": %s" % artifact_spec)

    return struct(
        original_spec = artifact_spec,
        coordinate = "%s:%s" % (group_id, artifact_id),
        group_id = group_id,
        artifact_id = artifact_id,
        version = version,
    )

def _fetch_repo(artifact):
    group_elements = artifact.group_id.split(".")
    artifact_elements = artifact.artifact_id.replace("-", ".").split(".")
    return "_".join(group_elements + artifact_elements).replace("-", "_")

artifacts = struct(
    parse_spec = _parse_spec,
    fetch_repo = _fetch_repo,
)
