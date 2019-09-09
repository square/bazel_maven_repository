load(
    ":poms_for_testing.bzl",
    "COMPLEX_POM",
    "GRANDPARENT_POM",
    "PARENT_POM",
    "SCOPED_DEP_POM",
    "SIMPLE_DEP_POM",
    "SIMPLE_PACKAGING_AAR_POM",
    "SIMPLE_PACKAGING_BUNDLE_POM",
    "SIMPLE_PROPERTIES_POM",
    "SYSTEM_PATH_POM",
)
load(":testing.bzl", "asserts", "test_suite")
load("//maven:artifacts.bzl", "artifacts")
load("//maven:poms.bzl", "for_testing", "poms")
load("//maven:xml.bzl", "xml")

def simple_pom_fragment_process(env):
    deps = poms.extract_dependencies(poms.parse(SIMPLE_DEP_POM))
    asserts.equals(env, 1, len(deps))
    dep = deps[0]
    asserts.equals(env, "foo", dep.group_id)
    asserts.equals(env, "bar", dep.artifact_id)
    asserts.equals(env, "1.0", dep.version)
    asserts.equals(env, "jar", dep.type)
    asserts.equals(env, None, dep.classifier)
    asserts.equals(env, None, dep.system_path)
    asserts.equals(env, "compile", dep.scope)
    asserts.false(env, dep.optional)

def simple_pom_fragment_process_scope(env):
    dep = poms.extract_dependencies(poms.parse(SCOPED_DEP_POM))[0]
    asserts.equals(env, "test", dep.scope)

def simple_pom_fragment_process_system_path(env):
    dep = poms.extract_dependencies(poms.parse(SYSTEM_PATH_POM))[0]
    asserts.equals(env, "/blah/foo", dep.system_path)

def complex_pom_test(env):
    project = poms.parse(COMPLEX_POM)
    dependencies = None
    managed_dependencies = None
    properties = None

    asserts.equals(env, 7, len(project.children), "child nodes of parent")
    asserts.equals(
        env,
        expected = ["modelVersion", "parent", "artifactId", "properties", "dependencies", "foo", "dependencyManagement"],
        actual = [x.label for x in project.children],
    )

    for node in project.children:
        if node.label == "properties":
            properties = node.children
        elif node.label == "dependencyManagement" and len(node.children) > 0:
            managed_dependencies = node.children[0].children
        elif node.label == "dependencies":
            dependencies = node.children

    asserts.true(env, dependencies)
    asserts.equals(env, 4, len(dependencies), "dependencies")  # Superficial dependencies, not fully accounted-for.

    asserts.true(env, properties)
    asserts.equals(env, 1, len(properties), "properties")

    asserts.true(env, managed_dependencies)
    asserts.equals(env, 1, len(managed_dependencies), "managed_dependencies")

def extract_packaging_test(env):
    asserts.equals(env, "pom", poms.extract_packaging(poms.parse(PARENT_POM)))
    asserts.equals(env, "jar", poms.extract_packaging(poms.parse(COMPLEX_POM)))
    asserts.equals(env, "aar", poms.extract_packaging(poms.parse(SIMPLE_PACKAGING_AAR_POM)))
    asserts.equals(env, "bundle", poms.extract_packaging(poms.parse(SIMPLE_PACKAGING_BUNDLE_POM)))

def extract_parent_test(env):
    pom = poms.parse(COMPLEX_POM)
    parent_artifact = poms.extract_parent(pom)
    asserts.equals(env, "parent", parent_artifact.artifact_id)
    pom = poms.parse(PARENT_POM)
    parent_artifact = poms.extract_parent(pom)
    asserts.equals(env, "grandparent", parent_artifact.artifact_id)
    pom = poms.parse(GRANDPARENT_POM)
    parent_artifact = poms.extract_parent(pom)
    asserts.false(env, bool(parent_artifact))

def extract_properties_simple_test(env):
    properties = poms.extract_properties(poms.parse(SIMPLE_PROPERTIES_POM))
    asserts.equals(env, 3, len(properties), "length of properties dictionary")
    asserts.equals(env, "foo", properties["foo"], "property 'foo'")
    asserts.equals(env, "bar", properties["foo.bar"], "property 'foo.bar'")
    asserts.equals(env, "2.0", properties["project.version"], "property 'project.version'")

def extract_properties_complex_pom_test(env):
    properties = poms.extract_properties(poms.parse(COMPLEX_POM))
    asserts.equals(env, 2, len(properties), "length of properties dictionary")
    asserts.equals(env, "5.0", properties["animal.sniffer.version"], "property 'animal.sniffer.version'")

def get_variable_test(env):
    asserts.equals(env, None, for_testing.get_variable("foo"), "assertion 1")
    asserts.equals(env, None, for_testing.get_variable("} ${foo"), "assertion 2")
    asserts.equals(env, None, for_testing.get_variable("foo}"), "assertion 3")
    asserts.equals(env, None, for_testing.get_variable("{foo}"), "assertion 4")
    asserts.equals(env, None, for_testing.get_variable("${foo"), "assertion 5")
    asserts.equals(env, "foo", for_testing.get_variable("${foo}"), "assertion 6")
    asserts.equals(env, "foo", for_testing.get_variable("a${foo}"), "assertion 7")
    asserts.equals(env, "foo", for_testing.get_variable("a${foo}a"), "assertion 8")
    asserts.equals(env, "project.version", for_testing.get_variable("${project.version}"), "assertion 9")

def substitute_variable_test(env):
    properties = {"foo": "bar", "project.groupId": "test.group"}
    asserts.equals(env, "foo", for_testing.substitute_variable("foo", properties))
    asserts.equals(env, "bar", for_testing.substitute_variable("${foo}", properties))
    asserts.equals(env, "abara", for_testing.substitute_variable("a${foo}a", properties))
    asserts.equals(env, "test.group", for_testing.substitute_variable("${project.groupId}", properties))

    # Not in properties
    asserts.equals(env, "${bar}", for_testing.substitute_variable("${bar}", properties))


# Tests issue highlighted in #62 where whitespace and other oddities makes boolean flags parse incorrectly.
def boolean_options_whitespace_test(env):
    OPTIONAL_BOOL_POM = """
        <project><dependencies>
            <dependency>
                <groupId>foo</groupId><artifactId>foo</artifactId><version>1.0</version>
                <optional>false
                </optional> <!-- Add some whitespace per #62 -->
            </dependency>
            <dependency>
                <groupId>bar</groupId><artifactId>bar</artifactId><version>1.0</version>
                <optional>true
                </optional> <!-- Add some whitespace per #62 -->
            </dependency>
        </dependencies></project>
    """
    dependencies = poms.extract_dependencies(poms.parse(OPTIONAL_BOOL_POM))
    asserts.false(env, dependencies[0].optional, "optional should be false for foo")
    asserts.true(env, dependencies[1].optional, "optional should be true for bar")

def merge_inheritance_chain_test(env):
    inheritance_chain = [poms.parse(COMPLEX_POM), poms.parse(PARENT_POM), poms.parse(GRANDPARENT_POM)]

    merged = for_testing.merge_inheritance_chain(inheritance_chain)

    asserts.equals(env, "test.group", xml.find_first(merged, "groupId").content, "groupId")
    asserts.equals(env, "child", xml.find_first(merged, "artifactId").content, "artifactId")
    asserts.equals(env, "1.0", xml.find_first(merged, "version").content, "version")
    asserts.equals(env, "jar", xml.find_first(merged, "packaging").content, "packaging")

# Set up fakes.
def _fake_read(path):
    download_map = {
        "test/group/child/1.0/child-1.0.pom": COMPLEX_POM,
        "test/group/parent/1.0/parent-1.0.pom": PARENT_POM,
        "test/grandparent/1.0/grandparent-1.0.pom": GRANDPARENT_POM,
    }
    return download_map.get(path, None)

def _pass_through_path(label):
    return label.name

def _noop_report(string):
    pass

def get_parent_chain_test(env):
    fake_ctx = struct(path = _pass_through_path, read = _fake_read, report_progress = _noop_report)
    chain = for_testing.get_inheritance_chain(fake_ctx, artifacts.parse_spec("test.group:child:1.0"))
    actual_ids = [poms.extract_artifact_id(x) for x in chain]
    asserts.equals(env, ["child", "parent", "grandparent"], actual_ids)

TESTS = [
    simple_pom_fragment_process,
    simple_pom_fragment_process_scope,
    simple_pom_fragment_process_system_path,
    complex_pom_test,
    extract_parent_test,
    extract_packaging_test,
    extract_properties_simple_test,
    extract_properties_complex_pom_test,
    get_variable_test,
    substitute_variable_test,
    boolean_options_whitespace_test,
    merge_inheritance_chain_test,
    get_parent_chain_test,
]

# Roll-up function.
def suite():
    return test_suite("pom processing", tests = TESTS)
