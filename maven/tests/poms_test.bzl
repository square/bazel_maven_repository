load(
    ":poms_for_testing.bzl",
    "COMPLEX_POM",
    "GRANDPARENT_POM",
    "PARENT_POM",
    "SCOPED_DEP_POM",
    "SIMPLE_DEP_POM",
    "SIMPLE_PROPERTIES_POM",
    "SYSTEM_PATH_POM",
)
load(":testing.bzl", "asserts", "test_suite")
load("//maven:poms.bzl", "for_testing", "poms")

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

def extract_parent_test(env):
    pom = poms.parse(COMPLEX_POM)
    parent_artifact = poms.extract_parent(pom)
    asserts.equals(env, "parent", parent_artifact.artifact_id)
    pom = poms.parse(PARENT_POM)
    parent_artifact = poms.extract_parent(pom)
    asserts.equals(env, "grandparent", parent_artifact.artifact_id)
    pom = poms.parse(GRANDPARENT_POM)
    parent_artifact = poms.extract_parent(pom)
    asserts.false(env, parent_artifact)

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

TESTS = [
    simple_pom_fragment_process,
    simple_pom_fragment_process_scope,
    simple_pom_fragment_process_system_path,
    complex_pom_test,
    extract_parent_test,
    extract_properties_simple_test,
    extract_properties_complex_pom_test,
    get_variable_test,
    substitute_variable_test,
    boolean_options_whitespace_test,
]

# Roll-up function.
def suite():
    return test_suite("pom processing", tests = TESTS)
