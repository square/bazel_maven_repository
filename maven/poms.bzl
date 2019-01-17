#
# Description:
#   Utilities for extracting information from pom files.
#
load(":utils.bzl", "strings")
load(":xml.bzl", "xml")

_maven_dep_properties = ["artifactId", "groupId", "version", "type", "scope", "optional", "classifier", "systemPath"]

def _process_dependency(dep_node):
    group_id = None
    artifact_id = None
    version = "INFERRED"
    type = "jar"
    optional = False
    scope = "compile"
    classifier = None
    system_path = None

    for c in dep_node.children:
        if c.label == "groupId":
            group_id = c.content
        elif c.label == "artifactId":
            artifact_id = c.content
        elif c.label == "version":
            # TODO(cgruber) handle property substitution.
            version = "INFERRED" if strings.contains(c.content, "$") else c.content
        elif c.label == "classifier":
            classifier = c.content
        elif c.label == "type":
            type = c.content
        elif c.label == "scope":
            scope = c.content
        elif c.label == "optional":
            optional = bool(c.content)
        elif c.label == "systemPath":
            system_path = c.content

    return struct(
        group_id = group_id,
        artifact_id = artifact_id,
        version = version,
        type = type,
        optional = optional,
        scope = scope,
        classifier = classifier,
        system_path = system_path,
        coordinate = "%s:%s" % (group_id, artifact_id)
    )

# Extracts dependency coordinates from a given <dependencies> node of a pom node.  The parameter should be the project
# node of a parsed xml document tree, returned by poms.parse(xml_text)
def _extract_dependencies(project):
    dependencies = []
    for node in project.children:
        if node.label == "dependencies":
            dependencies = node.children
    return [_process_dependency(x) for x in dependencies]

def _format_dependency(dep):
    result = "%s:%s:%s" % (dep.group_id, dep.artifact_id, dep.version)
    if bool(dep.classifier):
        type = dep.type if bool(dep.type) else "jar"
        result = "%s:%s" % (result, dep.type)
    else:
        if bool(dep.type) and not dep.type == "jar":
            result = "%s:%s" % (result, dep.type)
    return result

def _parse(xml_text):
    root = xml.parse(xml_text)
    for node in root.children:
        if node.label == "project":
            return node
    fail("No <project> tag found in supplied xml: %s" % xml)


poms = struct(
    parse = _parse,
    extract_dependencies = _extract_dependencies,
    format_dependency = _format_dependency,
)
