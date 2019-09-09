#
# Description:
#   Utilities for extracting information from pom xml trees.
#
load(":globals.bzl", "DOWNLOAD_PREFIX", "fetch_repo")
load(":packaging_type.bzl", "packaging_type")
load(":utils.bzl", "strings")
load(":xml.bzl", "xml")

# An enum of known labels
labels = struct(
    # Structural tags
    PROJECT = "project",
    PARENT = "parent",
    DEPENDENCY_MANAGEMENT = "dependencyManagement",
    DEPENDENCIES = "dependencies",
    DEPENDENCY = "dependency",
    PROPERTIES = "properties",

    # Identifiers
    ARTIFACT_ID = "artifactId",
    GROUP_ID = "groupId",
    VERSION = "version",
    TYPE = "type",
    SCOPE = "scope",
    OPTIONAL = "optional",
    CLASSIFIER = "classifier",
    SYSTEM_PATH = "systemPath",
    PACKAGING = "packaging",  # The same as type, but in the main section.
)

def _process_dependency(dep_node):
    group_id = None
    artifact_id = None
    version = None
    type = None
    optional = False
    scope = None
    classifier = None
    system_path = None

    for c in dep_node.children:
        if c.label == labels.GROUP_ID:
            group_id = c.content
        elif c.label == labels.ARTIFACT_ID:
            artifact_id = c.content
        elif c.label == labels.VERSION:
            version = c.content
        elif c.label == labels.CLASSIFIER:
            classifier = c.content
        elif c.label == labels.TYPE:
            type = c.content
        elif c.label == labels.SCOPE:
            scope = c.content
        elif c.label == labels.OPTIONAL:
            optional = strings.trim(c.content).lower() == "true"
        elif c.label == labels.SYSTEM_PATH:
            system_path = c.content

    return _dependency(
        group_id = group_id,
        artifact_id = artifact_id,
        version = version,
        type = type,
        optional = optional,
        scope = scope,
        classifier = classifier,
        system_path = system_path,
    )

def _dependency(
        group_id,
        artifact_id,
        version = None,
        type = None,
        optional = None,
        scope = None,
        classifier = None,
        system_path = None):
    return struct(
        group_id = group_id,
        artifact_id = artifact_id,
        version = version,
        type = type,
        optional = optional,
        scope = scope,
        classifier = classifier,
        system_path = system_path,
        coordinates = "%s:%s" % (group_id, artifact_id),
    )

# A set of property defaults for dependencies, to be merged at the last minute.  Omits the groupId
# and artifactId so it will blow up if used anywhere but in the final merge step.
_DEPENDENCY_DEFAULT = struct(
    version = None,
    type = packaging_type.DEFAULT.name,
    optional = False,
    scope = "compile",
    classifier = None,
    system_path = None,
)

# Extracts dependency coordinates from a given <dependencies> node of a pom node.
# The parameter should be an xml node containing the tag <dependencies>
def _extract_dependencies(parent_node):
    node = xml.find_first(parent_node, labels.DEPENDENCIES)
    return [_process_dependency(x) for x in node.children] if bool(node) else []

# Extracts dependency coordinates from a given <dependencies> node within a <dependencyManagement> node of a pom node.
# The parameter should be an xml node containing the tag <dependencyManagement>
def _extract_dependency_management(project_node):
    node = xml.find_first(project_node, labels.DEPENDENCY_MANAGEMENT)
    return _extract_dependencies(node) if bool(node) else []

def _merge_dependency(fallback, dependency):
    if not bool(fallback):
        return dependency

    # If this were a node tree, we could re-use the leaf element merging, but it's a struct. :(
    # groupid and artifactid are always present, so don't bother merging them.
    return _dependency(
        group_id = dependency.group_id,
        artifact_id = dependency.artifact_id,
        version = dependency.version if bool(dependency.version) else fallback.version,
        type = dependency.type if bool(dependency.type) else fallback.type,
        optional = dependency.optional if bool(dependency.optional) else fallback.optional,
        scope = dependency.scope if bool(dependency.scope) else fallback.scope,
        classifier = dependency.classifier if bool(dependency.classifier) else fallback.classifier,
        system_path = dependency.system_path if bool(dependency.system_path) else fallback.system_path,
    )

def _get_variable(string):
    start = string.find("${")
    end = string.find("}")
    return string[start + 2:end] if start >= 0 and end >= 0 and start < end - 3 else None

def _substitute_variable_if_present(string, properties):
    if not bool(string):
        return None
    variable_label = _get_variable(string)
    if bool(variable_label):
        substitution = properties.get(variable_label, None)
        if bool(substitution):
            string = string.replace("${%s}" % variable_label, substitution)
    return string

def _apply_property(dependency, properties):
    # For now just check <version> and <groupId>
    return _dependency(
        group_id = _substitute_variable_if_present(dependency.group_id, properties),
        artifact_id = dependency.artifact_id,
        version = _substitute_variable_if_present(dependency.version, properties),
        type = dependency.type,
        optional = dependency.optional,
        scope = dependency.scope,
        classifier = dependency.classifier,
        system_path = dependency.system_path,
    )

# Merges any information from <dependencyManagement> and <properties> sections and returns the
# resulting processed dependencies.
def _get_processed_dependencies(project_node):
    result = []
    dependency_management = {}
    for dep in _extract_dependency_management(project_node):
        dependency_management[dep.coordinates] = dep
    dependencies = _extract_dependencies(project_node)
    properties = _extract_properties(project_node)
    for dep in dependencies:
        dep = _merge_dependency(dependency_management.get(dep.coordinates, None), dep)
        dep = _apply_property(dep, properties)
        dep = _merge_dependency(_DEPENDENCY_DEFAULT, dep)  # fill in any needed default values.
        result.append(dep)
    return result

# Extracts artifact_id for the project metadata given.
# The parameter should be the project node of a parsed xml document tree, returned by poms.parse(xml_text). Any
# metadata merging (inherited metadata) should be done before calling this, to avoid missing out inherited packaging.
def _extract_artifact_id(node):
    for child_node in node.children:
        if child_node.label == "artifactId":
            return child_node.content
    return None

# Extracts packaging specification for the project metadata given.
# The parameter should be the project node of a parsed xml document tree, returned by poms.parse(xml_text). Any
# metadata merging (inherited metadata) should be done before calling this, to avoid missing out inherited packaging.
def _extract_packaging(project):
    if project.label != "project":
        fail("Attempted to extract a packaging tag from a %s node, instead of a <project> node." % project.label)
    for node in project.children:
        if node.label == labels.PACKAGING:
            if bool(node.content):
                return node.content
    return packaging_type.DEFAULT.name

def _process_parent(dep_node):
    group_id = None
    artifact_id = None
    version = None
    for c in dep_node.children:
        if c.label == labels.GROUP_ID:
            group_id = c.content
        elif c.label == labels.ARTIFACT_ID:
            artifact_id = c.content
        elif c.label == labels.VERSION:
            version = c.content
    return struct(
        group_id = group_id,
        artifact_id = artifact_id,
        version = version,
        type = "pom",  # Parent POMs must be pure metadata artifacts (only a .pom, no .jar/.aar, etc.)
        original_spec = "%s:%s:%s:pom" % (group_id, artifact_id, version),
        classifier = None,
    )

# Extracts parent specification for the supplied pom file.
# The parameter should be the project node of a parsed xml document tree, returned by poms.parse(xml_text)
def _extract_parent(project):
    if project.label != "project":
        fail("Attempted to extract a parent tag from a %s node, instead of a <project> node." % project.label)
    for node in project.children:
        if node.label == labels.PARENT:
            return _process_parent(node)
    return None

def _extract_properties(project):
    if project.label != "project":
        fail("Attempted to extract properties from a %s node, instead of a <project> node." % project.label)
    properties_nodes = []
    for node in project.children:
        if node.label == labels.PROPERTIES:
            properties_nodes = node.children
    properties = {}
    for node in properties_nodes:
        properties[node.label] = node.content

    # Generate maven's implicit properties from the project itself.
    for label in [labels.GROUP_ID, labels.ARTIFACT_ID, labels.VERSION]:
        node = xml.find_first(project, label)
        if bool(node):
            properties["project.%s" % label] = node.content
    return properties

def _format_dependency(dep):
    result = "%s:%s:%s" % (dep.group_id, dep.artifact_id, dep.version)
    if bool(dep.classifier):
        type = dep.type if bool(dep.type) else packaging_type.DEFAULT.name
        result = "%s:%s" % (result, dep.type)
    elif bool(dep.type) and not dep.type == packaging_type.DEFAULT.name:
        result = "%s:%s" % (result, dep.type)
    return result

def _parse(xml_text):
    root = xml.parse(xml_text)
    project = xml.find_first(root, "project")
    if not bool(project):
        fail("No <project> tag found in supplied xml: %s" % xml_text)
    return project

# A pom-specific node-merge algorith,
def _merge_content_last_wins(a, b):
    if not bool(a):
        return b
    if not bool(b):
        return a
    if a.label != b.label:
        fail("Attempt to merge to different pom elements: %s, %s", (a, b))
    return xml.new_node(
        label = a.label,
        content = b.content if bool(b.content) else a.content,
    )

# This could be 100% reusable, except for the limit on recursion.  The strategy can't loop back and call this. :/
def _merge_leaf_elements(parent_list, child_list):
    index = {}
    merged = []
    for i in range(len(parent_list)):
        merged.append(parent_list[i])
        index[parent_list[i].label] = i
    for i in range(len(child_list)):
        index_of_property = index.get(child_list[i].label, -1)
        if index_of_property >= 0:
            merged[index_of_property] = child_list[i]
        else:
            merged.append(child_list[i])
            index[child_list[i].label] = len(merged)
    return merged

def _children_if_exists(node):
    return node.children if bool(node) else []

def _merge_properties_section(parent_node, child_node):
    if not bool(parent_node):
        return child_node
    if not bool(child_node):
        return parent_node
    children = _merge_leaf_elements(
        _children_if_exists(xml.find_first(parent_node, labels.PROPERTIES)),
        _children_if_exists(xml.find_first(child_node, labels.PROPERTIES)),
    )
    return xml.new_node(label = labels.PROPERTIES, children = children)


# Description:
#   Merges the dependency section of the pom.  This makes an assumption that deps sections won't have both the main
#   artifact for a group_id/artifact_id pair AND one of the same pom's classified artifacts.  It is possible, and in
#   those cases, the deps will be wrong and the build snippet should be explicitly substituted.
def _merge_dependency_section(parent, child):
    if not bool(parent):
        return child if bool(child) else xml.new_node(label = labels.DEPENDENCIES)
    if not bool(child):
        return parent if bool(parent) else xml.new_node(label = labels.DEPENDENCIES)
    if parent.label != labels.DEPENDENCIES:
        fail("Parent node in merged dependency operation not a <dependencies> node: %s" % parent)
    if child.label != labels.DEPENDENCIES:
        fail("Child node in merged dependency operation not a <dependencies> node: %s" % child)

    # index the <dependency> nodes by groupId:artifactId
    parent_deps = {}
    for node in _children_if_exists(parent):
        key = "%s:%s" % (xml.find_first(node, labels.GROUP_ID), xml.find_first(node, labels.ARTIFACT_ID))
        parent_deps[key] = node
    child_deps = {}
    for node in _children_if_exists(child):
        key = "%s:%s" % (xml.find_first(node, labels.GROUP_ID), xml.find_first(node, labels.ARTIFACT_ID))
        child_deps[key] = node

    merged = {}
    for key in parent_deps:
        merged[key] = parent_deps[key]
    for key in child_deps:
        if bool(merged.get(key, None)):
            existing_node = merged[key]
            merged[key] = xml.new_node(
                label = labels.DEPENDENCY,
                children = _merge_leaf_elements(
                    _children_if_exists(merged[key]),
                    _children_if_exists(child_deps[key]),
                ),
            )
        else:
            merged[key] = child_deps[key]

    dependency_items = []
    for key, node in merged.items():
        dependency_items.append(node)
    return xml.new_node(
        label = labels.DEPENDENCIES,
        children = dependency_items,
    )

# A highly constrained merge (only merges core metadata, properties, dependency_management, and dependency sections.
# It drops all other sections on the floor, including parent pom metadata.  It is also not as efficient as it could be,
# because pom sections are unordered, so there's a lot of scanning.  It also requires lots of targetted methods since
# starlark has no recursion, so this code cannot be generalized without becoming a hellish batch of insane iteration.
def _merge_parent(parent, child):
    merged = xml.new_node(label = labels.PROJECT, children = [])

    # merge core identity metadata
    for label in [labels.GROUP_ID, labels.ARTIFACT_ID, labels.VERSION]:
        merged_node = _merge_content_last_wins(xml.find_first(parent, label), xml.find_first(child, label))
        if bool(merged_node):
            merged.children.append(merged_node)

    # merge packaging with jar special cased.
    child_packaging_node = xml.find_first(child, labels.PACKAGING)
    merged.children.append(
        child_packaging_node if bool(child_packaging_node) else (
            xml.new_node(label = labels.PACKAGING, content = packaging_type.DEFAULT.name)
        ),
    )

    # merge properties
    merged.children.append(_merge_properties_section(parent, child))

    # merge dependencies
    merged.children.append(_merge_dependency_section(
        xml.find_first(parent, labels.DEPENDENCIES),
        xml.find_first(child, labels.DEPENDENCIES),
    ))

    # merge dependencyManagement->dependencies
    merged.children.append(xml.new_node(label = labels.DEPENDENCY_MANAGEMENT, children = [
        _merge_dependency_section(
            xml.find_first(parent, labels.DEPENDENCY_MANAGEMENT, labels.DEPENDENCIES),
            xml.find_first(child, labels.DEPENDENCY_MANAGEMENT, labels.DEPENDENCIES),
        ),
    ]))
    return merged


# Builds a chain of nodes representing pom xml data in a hierarchical inheritance relationship which
# can be collapsed or wrapped.
def _get_inheritance_chain(ctx, artifact):
    inheritance_chain = []
    current = artifact
    for _ in range(100):  # Can't use recursion, so just iterate
        if not bool(current):
            ctx.report_progress("Merging poms for %s" % artifact.original_spec)
            return inheritance_chain
        path = ctx.path(fetch_repo.pom_target_relative_to(current, fetch_repo.pom_repo_name(artifact)))
        ctx.report_progress("Reading pom for %s" % current.original_spec)
        xml_text = ctx.read(path)
        ctx.report_progress("Parsing pom for %s" % current.original_spec)
        current_node = _parse(xml_text)
        inheritance_chain += [current_node]
        current = _extract_parent(current_node)
    fail("Iterations exceeded. %s has more than 100 super-poms." % artifact.original_spec)

# Take an inheritance chain of xml trees (Fetched by _get_inheritance_chain) and merge them from
# the top (the end of the list) to the bottom (the beginning of the list)
def _merge_inheritance_chain(inheritance_chain):
    merged = inheritance_chain.pop()
    for next in reversed(inheritance_chain):
        merged = _merge_parent(parent = merged, child = next)
    return merged

# Get the merged metadata for the pom.xml and its parents.
def _get_project_metadata(ctx, artifact):
    # The two steps are extracted for testability.
    return _merge_inheritance_chain(_get_inheritance_chain(ctx, artifact))

for_testing = struct(
    get_variable = _get_variable,
    substitute_variable = _substitute_variable_if_present,
    merge_inheritance_chain = _merge_inheritance_chain,
    get_inheritance_chain = _get_inheritance_chain,
)

# Exposes the namespace for the poms functions.
poms = struct(
    # Returns an xml element tree of the supplied pom text corresponding to the project
    parse = _parse,

    extract_artifact_id = _extract_artifact_id,

    # Returns a list of structs containing each dependency declared pom xml tree.
    extract_dependencies = _get_processed_dependencies,

    # Returns a list of structs each dependency declared in the dependencyManagement of the pom xml tree.
    extract_dependency_management = _extract_dependency_management,

    # Returns a struct containing the critical elements of a parent in the pom tree, sutable for pom fetching.
    extract_parent = _extract_parent,

    # Returns a dictionary containing the properties of the pom xml tree.
    extract_properties = _extract_properties,

    # Returns a string representing the packaging type of the pom (jar, aar, etc.)
    extract_packaging = _extract_packaging,

    # Returns a string representation of the supplied dependency
    format_dependency = _format_dependency,

    # Merges a parent pom xml tree with a child xml tree.
    merge_parent = _merge_parent,

    # Get the effective (inheritance-merged) pom node tree, against which other functions in this struct can be
    # performed.  This function assumes that a fetch.pom_rule has been setup for the artifact in question, that it has
    # been passed to the rules invoking this function, and will fail with a missing workspace if that is not the case.
    get_project_metadata = _get_project_metadata,
)
