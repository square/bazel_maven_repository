#
# Description:
#   Utilities for extracting information from pom files.
#
load(":utils.bzl", "strings")

_maven_dep_properties = ["artifactId", "groupId", "version", "type", "scope", "optional", "classifier", "systemPath"]

def _parse_fragment(deps_fragment):
    for property in _maven_dep_properties:
        deps_fragment = deps_fragment.replace("</%s>" % property, "::")
        deps_fragment = deps_fragment.replace("<%s>" % property, "%s:" % property)
    group_id = None
    artifact_id = None
    version = "INFERRED"
    type = "jar"
    optional = False
    scope = "compile"
    classifier = None
    system_path = None

    for fragment_element in deps_fragment.split("::"):
        if not bool(fragment_element):
            continue
        key, token = fragment_element.split(":")
        if strings.contains(token, "$"):
            token = "INFERRED" # TODO(cgruber) handle property substitution.
            # _substitute_variable(string, variable_key, value)
        if key == "groupId":
            group_id = token
        elif key == "artifactId":
            artifact_id = token
        elif key == "version":
            version = token
        elif key == "classifier":
            classifier = token
        elif key == "type":
            type = token
        elif key == "scope":
            scope = token
        elif key == "optional":
            optional = bool(token)
        elif key == "systemPath":
            systemPath = token

    return struct(
        group_id = group_id,
        artifact_id = artifact_id,
        version = version,
        type = "jar",
        optional = False,
        scope = "compile",
        classifier = None,
        system_path = None,
        coordinate = "%s:%s" % (group_id, artifact_id)
    )

def _parse_fragments(deps_fragments):
    deps = []
    for deps_fragment in deps_fragments:
        deps += [_parse_fragment(deps_fragment)]
    return deps

# extracts dependency coordinates from a given <dependency> section of a pom file.  This only handles
# a repeated set of <dependency> sections, without a parent element.
def _extract_dependencies(xml_fragment):
    if not bool(xml_fragment):
        return []

    # Trim start and end elements.
    if xml_fragment.startswith("<dependency>"):
        xml_fragment = xml_fragment[len("<dependency>"):-len("</dependency>")]
    else:
        fail("Invalid maven dependency xml fragment.  Please file an issue: %s" % xml_fragment)
    deps_fragments = xml_fragment.split("</dependency><dependency>")
    deps = _parse_fragments(deps_fragments)
    return deps

def _format(dep):
    result = "%s:%s:%s" % (dep.group_id, dep.artifact_id, dep.version)
    if bool(dep.classifier):
        type = dep.type if bool(dep.type) else "jar"
        result = "%s:%s" % (result, dep.type)
    else:
        if bool(dep.type) and not dep.type == "jar":
            result = "%s:%s" % (result, dep.type)
    return result

poms = struct(
    extract_dependencies = _extract_dependencies,
    format = _format,
)
