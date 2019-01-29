# Description:
#   Shared Maven POM content needed in different tests.

POM_PREFIX = """
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
"""

POM_SUFFIX = """</project>
"""

SIMPLE_DEP_POM = POM_PREFIX + """
  <dependencies>
    <dependency>
      <groupId>foo</groupId>
      <artifactId>bar</artifactId>
      <version>1.0</version>
    </dependency>
  </dependencies>
""" + POM_SUFFIX

SCOPED_DEP_POM = POM_PREFIX + """
  <dependencies>
    <dependency>
      <groupId>foo</groupId>
      <artifactId>bar</artifactId>
      <version>1.0</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
""" + POM_SUFFIX

SYSTEM_PATH_POM = POM_PREFIX + """
  <dependencies>
    <dependency>
      <groupId>foo</groupId>
      <artifactId>bar</artifactId>
      <version>1.0</version>
      <systemPath>/blah/foo</systemPath>
    </dependency>
  </dependencies>
""" + POM_SUFFIX

SIMPLE_PROPERTIES_POM = POM_PREFIX + """
  <properties>
    <foo>foo</foo>
    <foo.bar>bar</foo.bar>
  </properties>
""" + POM_SUFFIX

GRANDPARENT_POM = POM_PREFIX + """
  <modelVersion>4.0.0</modelVersion>
  <groupId>test</groupId>
  <artifactId>grandparent</artifactId>
  <version>1.0</version>
  <packaging>pom</packaging>
  <properties>
    <!-- Properties for versions. -->
    <foo>foo</foo>
    <findbugs.jsr305>1.0</findbugs.jsr305>
  </properties>
""" + POM_SUFFIX

PARENT_POM = POM_PREFIX + """
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>test</groupId>
    <artifactId>grandparent</artifactId>
    <version>1.0</version>
  </parent>
  <groupId>test.group</groupId>
  <artifactId>parent</artifactId>
  <packaging>pom</packaging>
  <properties>
    <foo>bar</foo> <!-- Property override -->
    <baz>blah</baz>
  </properties>
  <dependencies>
    <dependency>
      <groupId>com.google.guava</groupId>
      <artifactId>guava</artifactId>
      <version>25.0-jre</version>
    </dependency>
  </dependencies>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>junit</groupId>
        <artifactId>junit</artifactId>
        <version>4.12</version>
        <scope>test</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
""" + POM_SUFFIX

COMPLEX_POM = POM_PREFIX + """
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>test.group</groupId>
    <artifactId>parent</artifactId>
    <version>1.0</version>
  </parent>
  <artifactId>child</artifactId>
  <properties>
    <!-- Properties for versions. -->
    <animal.sniffer.version>5.0</animal.sniffer.version>
  </properties>
  <dependencies>
    <!-- test comment processing -->
    <dependency>
      <groupId>com.google.code.findbugs</groupId>
      <artifactId>jsr305</artifactId>
      <version>${findbugs.jsr305}</version>
    </dependency>
    <dependency>
      <groupId>com.google.dagger</groupId>
      <artifactId>dagger</artifactId>
      <version>2.16</version>
    </dependency>
    <dependency>
      <groupId>org.codehaus.mojo</groupId>
      <artifactId>animal-sniffer-annotations</artifactId>
      <version>${animal.sniffer.version}</version>
    </dependency>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <!-- implicitly test scoped and 4.13-beta1 -->
    </dependency>
  </dependencies>
  <foo />
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>junit</groupId>
        <artifactId>junit</artifactId>
        <version>4.13-beta-1</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
""" + POM_SUFFIX

MERGED_EXPECTED_POM = POM_PREFIX + """
  <groupId>test.group</groupId>
  <artifactId>child</artifactId>
  <version>1.0</version>
  <packaging>jar</packaging>
  <properties>
    <foo>bar</foo>
    <findbugs.jsr305>1.0</findbugs.jsr305>
    <baz>blah</baz>
    <animal.sniffer.version>5.0</animal.sniffer.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>com.google.guava</groupId>
      <artifactId>guava</artifactId>
      <version>25.0-jre</version>
    </dependency>
    <dependency>
      <groupId>com.google.code.findbugs</groupId>
      <artifactId>jsr305</artifactId>
      <version>${findbugs.jsr305}</version>
    </dependency>
    <dependency>
      <groupId>com.google.dagger</groupId>
      <artifactId>dagger</artifactId>
      <version>2.16</version>
    </dependency>
    <dependency>
      <groupId>org.codehaus.mojo</groupId>
      <artifactId>animal-sniffer-annotations</artifactId>
      <version>${animal.sniffer.version}</version>
    </dependency>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <!-- should be test scoped and 4.12 -->
    </dependency>
  </dependencies>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>junit</groupId>
        <artifactId>junit</artifactId>
        <version>4.13-beta-1</version>
        <scope>test</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
""" + POM_SUFFIX
