load(
    ":poms_for_testing.bzl",
    "COMPLEX_POM",
    "GRANDPARENT_POM",
    "MERGED_EXPECTED_POM",
    "PARENT_POM",
)
load(":testing.bzl", "asserts", "test_suite")
load("//maven:poms.bzl", "poms")
load("//maven:xml.bzl", "xml")

def merge_properties_test(env):
    parent = """<project><properties>
        <foo>foo</foo>
        <bar>bar</bar>
    </properties></project>"""
    child = """<project><properties>
        <baz>baz</baz>
        <bar>blah</bar>
    </properties></project>"""
    merged = poms.merge_parent(parent = poms.parse(parent), child = poms.parse(child))

    properties = poms.extract_properties(merged)
    asserts.equals(env, 3, len(properties), "number of properties")
    asserts.equals(env, "foo", properties["foo"], "property foo")
    asserts.equals(env, "blah", properties["bar"], "property bar")
    asserts.equals(env, "baz", properties["baz"], "property baz")

def merge_dependency_test(env):
    parent = """<project><dependencies><dependency>
        <groupId>foo</groupId><artifactId>bar</artifactId><version>1.0</version><scope>test</scope>
    </dependency></dependencies></project>"""
    child = """<project><dependencies><dependency>
        <groupId>foo</groupId><artifactId>bar</artifactId><version>2.0</version>
    </dependency></dependencies></project>"""
    merged = poms.merge_parent(parent = poms.parse(parent), child = poms.parse(child))

    dependencies = poms.extract_dependencies(merged)
    asserts.equals(env, 1, len(dependencies), "number of dependencies")
    dependency = dependencies[0]
    asserts.equals(env, "foo", dependency.group_id, "groupId")
    asserts.equals(env, "bar", dependency.artifact_id, "artifactId")
    asserts.equals(env, "2.0", dependency.version, "version")
    asserts.equals(env, "test", dependency.scope, "scope")

def merge_simpler_grandparent_parent_test(env):
    grandparent = poms.parse(GRANDPARENT_POM)
    parent = poms.parse(PARENT_POM)

    # verify precondition
    asserts.equals(env, "foo", poms.extract_properties(grandparent).get("foo", None), "original value of 'foo'")

    merged = poms.merge_parent(parent = grandparent, child = parent)

    asserts.equals(env, "test.group", xml.find_first(merged, "groupId").content, "merged groupId")
    asserts.equals(env, "parent", xml.find_first(merged, "artifactId").content, "merged artifactId")
    asserts.equals(env, "1.0", xml.find_first(merged, "version").content, "merged version")
    asserts.equals(env, "pom", xml.find_first(merged, "packaging").content, "merged packaging")

    properties = poms.extract_properties(merged)
    asserts.equals(env, 3, len(properties), "number of properties")
    asserts.equals(env, "bar", properties["foo"], "merged value of 'foo'")
    asserts.equals(env, "1.0", properties["findbugs.jsr305"], "merged value of 'findbugs.jsr305'")
    asserts.equals(env, "blah", properties["baz"], "merged value of 'baz'")

    dependencies = poms.extract_dependencies(merged)
    asserts.equals(env, 1, len(dependencies), "number of dependencies")

    deps_mgt = poms.extract_dependency_management(merged)
    asserts.equals(env, 1, len(deps_mgt), "number of dependency management")
    asserts.equals(env, "test", deps_mgt[0].scope)

def merge_full_chain_test(env):
    grandparent = poms.parse(GRANDPARENT_POM)
    parent = poms.parse(PARENT_POM)
    child = poms.parse(COMPLEX_POM)
    expected = poms.parse(MERGED_EXPECTED_POM)

    merged_parents = poms.merge_parent(parent = grandparent, child = parent)
    merged = poms.merge_parent(parent = merged_parents, child = child)

    asserts.equals(env, "test.group", xml.find_first(merged, "groupId").content, "merged groupId")
    asserts.equals(env, "child", xml.find_first(merged, "artifactId").content, "merged artifactId")
    asserts.equals(env, "1.0", xml.find_first(merged, "version").content, "merged version")
    asserts.equals(env, "jar", xml.find_first(merged, "packaging").content, "merged packaging")

    properties = poms.extract_properties(merged)
    asserts.equals(env, 4, len(properties), "number of properties")
    asserts.equals(env, "bar", properties["foo"], "merged value of 'foo'")
    asserts.equals(env, "1.0", properties["findbugs.jsr305"], "merged value of 'findbugs.jsr305'")
    asserts.equals(env, "blah", properties["baz"], "merged value of 'baz'")
    asserts.equals(env, "5.0", properties["animal.sniffer.version"], "merged value of 'animal.sniffer.version'")

    dependencies = poms.extract_dependencies(merged)
    asserts.equals(env, 5, len(dependencies), "number of dependencies")

    deps_mgt = poms.extract_dependency_management(merged)
    print(deps_mgt)
    asserts.equals(env, 1, len(deps_mgt), "number of dependency management")
    asserts.equals(env, "test", deps_mgt[0].scope)

    # A bit of a brittle "Golden" file test, but order does end up being deterministic based on xml content
    # Spits out JSON if not matching which can be cut-and-pasted into a file, formatted, and compared.
    # The core functionality should be asserted about more precisely in the above assertions.
    asserts.equals(env, expected.to_json(), merged.to_json(), "merged pom node tree")

TESTS = [
    merge_properties_test,
    merge_dependency_test,
    merge_simpler_grandparent_parent_test,
    merge_full_chain_test,
]

# Roll-up function.
def suite():
    return test_suite("pom merging", tests = TESTS)
