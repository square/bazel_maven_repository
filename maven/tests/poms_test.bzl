load(":testing.bzl", "asserts", "test_suite")
load("//maven:poms.bzl", "poms")
load("//maven:utils.bzl", "strings")

SIMPLE_DEP_POM = """
<project>
  <dependencies>
    <dependency>
      <groupId>foo</groupId>
      <artifactId>bar</artifactId>
      <version>1.0</version>
    </dependency>
  </dependencies>
</project>
"""

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


SCOPED_DEP_POM = """
<project>
  <dependencies>
    <dependency>
      <groupId>foo</groupId>
      <artifactId>bar</artifactId>
      <version>1.0</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
"""

def simple_pom_fragment_process_scope(env):
    dep = poms.extract_dependencies(poms.parse(SCOPED_DEP_POM))[0]
    asserts.equals(env, "test", dep.scope)

SYSTEM_PATH_POM = """
<project>
  <dependencies>
    <dependency>
      <groupId>foo</groupId>
      <artifactId>bar</artifactId>
      <version>1.0</version>
      <systemPath>/blah/foo</systemPath>
    </dependency>
  </dependencies>
</project>
"""

def simple_pom_fragment_process_system_path(env):
    dep = poms.extract_dependencies(poms.parse(SYSTEM_PATH_POM))[0]
    asserts.equals(env, "/blah/foo", dep.system_path)



COMPLEX_POM = """
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.google.guava</groupId>
    <artifactId>guava-parent</artifactId>
    <version>25.0-jre</version>
  </parent>
  <artifactId>guava</artifactId>
  <packaging>bundle</packaging>
  <properties>
    <!-- Properties for versions. -->
    <animal.sniffer.version>5.0</animal.sniffer.version>
  </properties>
  <dependencies>
    <!-- dependency>
      <groupId>com.google.guava</groupId>
      <artifactId>guava</artifactId>
    </dependency-->
    <dependency>
      <groupId>com.google.code.findbugs</groupId>
      <artifactId>jsr305</artifactId>
    </dependency>
    <dependency>
      <groupId>org.checkerframework</groupId>
      <artifactId>checker-compat-qual</artifactId>
    </dependency>
    <dependency>
      <groupId>com.google.errorprone</groupId>
      <artifactId>error_prone_annotations</artifactId>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>com.google.j2objc</groupId>
      <artifactId>j2objc-annotations</artifactId>
      <optional>true</optional>
    </dependency>
    <!-- Some random comment -->
    <dependency>
      <groupId>org.codehaus.mojo</groupId>
      <artifactId>animal-sniffer-annotations</artifactId>
      <version>${animal.sniffer.version}</version>
    </dependency>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
    </dependency>
  </dependencies>
  <foo />
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.checkerframework</groupId>
        <artifactId>checker-compat-qual</artifactId>
      </dependency>
      <dependency>
        <groupId>junit</groupId>
        <artifactId>junit</artifactId>
        <version>4.12</version>
        <scope>test</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
"""


def complex_pom_test(env):
    project = poms.parse(COMPLEX_POM)
    dependencies = None
    managed_dependencies = None
    properties = None
    for node in project.children:
        if node.label == "properties":
            properties = node.children
        elif node.label == "dependencyManagement" and len(node.children) > 0:
            managed_dependencies = node.children[0].children
        elif node.label == "dependencies":
            dependencies = node.children

    asserts.true(env, dependencies)
    asserts.equals(env, 6, len(dependencies))

    asserts.true(env, properties)
    asserts.equals(env, 1, len(properties))

    asserts.true(env, managed_dependencies)
    asserts.equals(env, 2, len(managed_dependencies))


TESTS = [
    simple_pom_fragment_process,
    simple_pom_fragment_process_scope,
    simple_pom_fragment_process_system_path,
    complex_pom_test,
]

# Roll-up function.
def suite():
    return test_suite("pom processing", tests = TESTS)
