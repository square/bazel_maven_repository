load(":testing.bzl", "asserts", "test_suite")
load("//maven:poms.bzl", "poms")
load("//maven:utils.bzl", "strings")

simple_fragment = strings.trim("""
<dependency>
    <groupId>foo</groupId>
    <artifactId>bar</artifactId>
    <version>1.0</version>
</dependency>
""")

def simple_pom_fragment_process(env):
    deps = poms.extract_dependencies(simple_fragment)
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


scoped_fragment = strings.trim("""
<dependency>
    <groupId>foo</groupId>
    <artifactId>bar</artifactId>
    <version>1.0</version>
    <scope>test</scope>
</dependency>
""")

def simple_pom_fragment_process_scope(env):
    dep = poms.extract_dependencies(scoped_fragment)[0]
    asserts.equals(env, "test", dep.scope)

system_fragment = strings.trim("""
<dependency>
    <groupId>foo</groupId>
    <artifactId>bar</artifactId>
    <version>1.0</version>
    <systemPath>/blah/foo</systemPath>
</dependency>
""")

def simple_pom_fragment_process_system_path(env):
    dep = poms.extract_dependencies(system_fragment)[0]
    asserts.equals(env, "/blah/foo", dep.system_path)

TESTS = [
    simple_pom_fragment_process,
    simple_pom_fragment_process_scope,
    simple_pom_fragment_process_system_path,
]

# Roll-up function.
def poms_test_suite():
    test_suite("pom processing", tests = TESTS)
