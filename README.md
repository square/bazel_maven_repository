# Bazel Rules for Maven Repositories

A bazel ruleset creating an idiomatic bazel representation of a maven repository using a
pinned list of artifacts.

Release: `1.2.0` <br/>
Prerelease: `2.0.0-alpha-5`

| Version | Sha |
| ------- | --- |
| [Release 1.2.0] | `9e23155895d2bfc60b35d2dfd88c91701892a7efba5afacdf00cebc0982229fe` |
| [Prerelease 2.0.0-alpha-5] | `fde80cafa02a2c034cc8086c158f500e7b6ceb16d251273a6cc82f1c0723e0e8` |

[Release 1.2.0]: https://github.com/square/bazel_maven_repository/archive/1.2.0.zip
[Prerelease 2.0.0-alpha-5]: https://github.com/square/bazel_maven_repository/archive/2.0.0-alpha-5.zip

**[Table of Contents](http://tableofcontent.eu)**

  * [Overview](#overview)
  * [Supported Types](#supported-types)
  * [Inter-artifact dependencies](#inter-artifact-dependencies)
  * [Coordinate Translation](#coordinate-translation)
  * [Artifact Configuration](#artifact-configuration)
    + [Sha verification](#sha-verification)
    + [Testonly](#testonly)
    + [Exclude](#exclude)
    + [Include](#include)
    + [Deps](#deps)
    + [Substitution of build targets](#substitution-of-build-targets)
  * [Caching](#caching)
- [Limitations](#limitations)
  * [Other Usage Notes](#other-usage-notes)
    + [Caches](#caches)
    + [Clogged WORKSPACE files](#clogged-workspace-files)
    + [Kotlin](#kotlin)
  * [License](#license)



## Overview

**Bazel Rules for Maven Repositories** allow the specification of a list of artifacts which
constitute maven repository's universe of deps, and exposes these artifacts via a bazel *external workspace*.  The name of the repository specification rule becomes the repository name in Bazel.
For instance the following specification:
 
```python
MAVEN_REPOSITORY_RULES_VERSION = "1.2.0"
MAVEN_REPOSITORY_RULES_SHA = "9e23155895d2bfc60b35d2dfd88c91701892a7efba5afacdf00cebc0982229fe"
http_archive(
    name = "maven_repository_rules",
    urls = ["https://github.com/square/bazel_maven_repository/archive/%s.zip" % MAVEN_REPOSITORY_RULES_VERSION],
    type = "zip",
    strip_prefix = "bazel_maven_repository-%s" % MAVEN_REPOSITORY_RULES_VERSION,
    sha256 = MAVEN_REPOSITORY_RULES_SHA,
)
load("@maven_repository_rules//maven:maven.bzl", "maven_repository_specification")
maven_repository_specification(
    name = "maven",
    artifacts = {
        "com.google.guava:guava:25.0-jre": { "sha256": "3fd4341776428c7e0e5c18a7c10de129475b69ab9d30aeafbb5c277bb6074fa9" },
    }
)
```
 
... results in deps of the format `@maven//com/google/guava:guava` (which can be abbreviated to 
`@maven//com/google/guava`)

Dependency versions are resolved in the single artifact list.  Only one version is permitted within
a repository.

> Note: bazel_maven_repository has no workspace dependencies, so adding it to your project will not
> result in any additional bazel repositories to be fetched. However, you specify .aars in your list,
> you will need the `rules_android` to be declared in your `WORKSPACE`

## Supported Types

Currently `.aar` and `.jar` artifacts are supported.  OSGI bundles are supported by assuming they
are normal `.jar` artifacts (which they are, just have a packaging property of `bundle` and some
extra metadata in `META-INF` of the `.jar` file).

`.aar` artifacts should be specified as `"some.group:some-artifact:1.0:aar"` (just append `:aar`
onto the artifact spec string). 

For any other types, please file a feature request, or supply a pull request.  So long as there
exists a proper bazel import or library rule to bring the artifact's file into bazel's dependency
graph, it should be possible to support it.

## Inter-artifact dependencies

This rule will, in the generated repository, infer inter-artifact dependencies from pom.xml files
of those artifacts (pulling in only `compile` and `runtime` dependencies, and avoiding any 
`systemPath` dependencies).  This avoids the bazel user having to over-specify the full set of
dependency jars.

All artifacts, even if only transitively depended, must be specified with a pinned version in the
`artifacts` dictionary. Any artifacts discovered in the inferred dependency search, which are not
present in the main rule's artifact list will be flagged and the build will fail with an error. The
error output should suggest configuration to either pin them or exclude them.

## Coordinate Translation

Translation from maven group/artifact coordinates to bazel package/target coordinates is naive but
orderly.  The logic mirrors the layout of a maven repository, with groupId elements (separated by
`.`) turning into a package hierarchy, and the artifactId turning into a bazel target.

For example: `com.google.dagger:dagger-compiler:2.16` turns into `@maven//com/google/dagger:dagger`,
and `javax.inject:javax.inject:1` becomes `@maven//javax/inject:javax_inject` (since `.` is not a
valid character for a target). 

## Artifact Configuration
### Sha verification

Artifacts with SHA256 checksums can be added to `artifacts`, in the form:
```
    artifacts = {
        "com.google.guava:guava:25.0-jre": { "sha256": "3fd4341776428c7e0e5c18a7c10de129475b69ab9d30aeafbb5c277bb6074fa9" },
    }
```
Artifacts without SHA headers should configured as insecure, like so:
```
    artifacts = {
        "com.google.guava:guava:25.0-jre": { "insecure": True },
    }
```

The rules will reject artifacts without SHAs are not marked as "insecure". 

> Note: These rules cannot validate that the checksum is the right one, only that the one supplied
> in configuration matches the checksum of the file downloaded.  It is the responsibility of the
> maintainer to use proper security practices and obtain the expected checksum from a trusted source.

### Testonly

An artifact can be declared testonly - this forces the `testonly = True` flag for the generated target
to be set, requiring that this artifact only be used by other testonly rules (e.g. test-libraries with
`testonly = true` also set, or `*_test` rules.)

```python
maven_repository_specification(
    name = "maven",
    artifacts = {
        "com.google.truth:truth:1.0": {"insecure": True, "testonly": True},
        # ... all the other deps.
    },
)
```

### Exclude

> Since 2.0.0

An artifact can have some (or all) of its direct dependencies pruned by use of the `exclude` property.
For instance:

```python
maven_repository_specification(
    name = "maven",
    artifacts = {
        "com.google.truth:truth:1.0": {
            "insecure": True,
            "exclude": ["com.google.auto.value:auto-value-annotations"],
        },
        # ... all the other deps.
    },
)
```

This results in truth omitting a dependency on the auto-value annotations - useful to avoid
dependencies not specified as `<optional>true</optional>` in the pom.xml, but which are not necessary
for correct operation of the artifact.  A good example of this would be robolectric, which contains
dependencies on a lot of maven download code which is not needed in a bazel build.

> Note: This feature is incompatible with `"deps": [...]` and `"build_snippets": "..."` mechanisms.

### Include

> Since 2.0.0

An artifact can have additional dependencies added using the `include` property. For instance:

```python
maven_repository_specification(
    name = "maven",
    artifacts = {
        "com.helpshift:android-helpshift-aar:7.8.0": {
            "insecure": True,
            "include": [
                # Bazel dependencies 
                "@//some/local/dependency", # in the root workspace of this build
                "@some_workspace//some/other/dep", # in some external workspace of this build

                # While theoretically in the root workspace, because this occurs inside the maven
                # workspace maven may interpret this as being inside the @maven workspace. Use
                # the @// prefix to force it into the root workspace
                "//some/local/dependency",

                # Useful for referencing some custom thing added by a snippet on another artifact.
                ":some_target_in_the_same_package",

                # Maven artifact coordinates, which will be interpreted relative to the presently
                # configured maven workspace. These will also result in errors if their versioned
                # artifacts have not been pinned in the artifact dictionary.
                "androidx.cardview:cardview",
                "androidx.recyclerview:recyclerview",
                "com.google.android.material:material",
            ]
        },
        # ... all the other deps.
    },
)
```

This results in the bazel workspace generating additional dependencies, converting maven-style
`some.group.id:artifactId` pairs to `@maven//some/group/id:artifactId` and passing bazel-style
dependencies (`:foo`, `//foo/bar`, `@someWorkspace//foo/bar:baz`) through as text, relying on
bazel itself to resolve and complain if they are incorrect.

These additions are performed after automatically detected dependencies are processed (and
after excludes are processed).  It can be used to add missing deps from badly specified pom
files, or it can add-back-in optional dependencies (which are not included by default).

> Note: This feature is incompatible with `"deps": [...]` and `"build_snippets": "..."` mechanisms.

### Deps

> Since 2.0.0

An artifact can have its dependencies entirely specified (overriding the automated detection
via maven resolution) using the `deps` property. For instance:

```python
maven_repository_specification(
    name = "maven",
    artifacts = {
        "com.helpshift:android-helpshift-aar:7.8.0": {
            "insecure": True,
            "deps": [
                # Bazel dependencies 
                "@//some/local/dependency", # in the root workspace of this build
                "@some_workspace//some/other/dep", # in some external workspace of this build

                # While theoretically in the root workspace, because this occurs inside the maven
                # workspace maven may interpret this as being inside the @maven workspace. Use
                # the @// prefix to force it into the root workspace
                "//some/local/dependency",

                # Useful for referencing some custom thing added by a snippet on another artifact.
                ":some_target_in_the_same_package",

                # Maven artifact coordinates, which will be interpreted relative to the presently
                # configured maven workspace. These will also result in errors if their versioned
                # artifacts have not been pinned in the artifact dictionary.
                "androidx.cardview:cardview",
                "androidx.recyclerview:recyclerview",
                "com.google.android.material:material",
            ]
        },
        # ... all the other deps.
    },
)
```

This results in the bazel workspace ignoring the dependencies from resolved metadata, and using
the supplied list instead. It converts maven-style `some.group.id:artifactId` pairs to
`@maven//some/group/id:artifactId`.  It passes bazel-style dependencies (`:foo`, `//foo/bar`, 
`@someWorkspace//foo/bar:baz`) through as text, relying on bazel itself to resolve and complain
if they are incorrect.

> Note: This feature is incompatible with `"include": [...]` `"exclude": [...]` and
> `"build_snippets": "..."` mechanisms, as it entirely takes responsibility for the deps
> list.

### Substitution of build targets

> Note: Because this feature entirely takes over snippet generation, it is more brittle than other
> features that may address the relevant use-cases. Please prefer those features over this one,
> if they can solve your problem, as it overrides a lot of validation and guarantees, and a given
> snippet may become stale with version changes of the artifacts specified.
>
> It is useful, however, if you cannot address your case with other features.

One can provide a `BUILD.bazel` target snippet that will be substituted for the auto-generated
target implied by a maven artifact.  This is very useful for providing an
annotation-processor-exporting alternative target.  The substitution is naive, so the string needs
to be appropriate and any rules need to be correct, contain the right dependencies, etc.  To aid
that it's also possible to (on a per-package basis) substitute dependencies on a given
fully-qualified bazel target for another. 

A simple use-case would be to substitute a target name (e.g. "mockito-core" -> "mockito") for
cleaner/easier use in bazel:

```python
maven_repository_specification(
    name = "maven",
    artifacts = {
        "org.mockito:mockito-core:2.20.1": {
            "sha256": "blahblahblah",
            "build_snippet": """maven_jvm_artifact(name = "mockito", artifact = "org.mockito:mockito-core:2.20.1")""",
        },
        # ... all the other deps.
    },
)
```

This would allow the following use in a `BUILD.bazel` file.

```python
java_test(
  name = "MyTest",
  srcs = "MyTest.java",
  deps = [
    # ... other deps
    "@maven//org/mockito" # instead of "@maven//org/mockito:mockito-core"
  ],
)
```

More complex use-cases are possible, such as adding substitute targets with annotation processing
`java_plugin` targets and exports.  An example with Dagger would look like this (with the basic rule
imports assumed):

```python
DAGGER_PROCESSOR_SNIPPET = """
# use this target
java_library(name = "dagger", exports = [":dagger_api"], exported_plugins = [":dagger_plugin"])

# alternatively-named import of the raw dagger library.
raw_jvm_import(
    name = "dagger_api",
    jars = "@com_google_dagger_dagger//maven",    
)

java_plugin(
    name = "dagger_plugin",
    processor_class = "dagger.internal.codegen.ComponentProcessor",
    generates_api = True,
    deps = [":dagger_compiler"],
)
"""
```

The above is given as a substitution in the `maven_repository_specification()` rule.  However,
since the inferred dependencies of `:dagger-compiler` would create a dependency cycle because it
includes `:dagger` as a dep, the specification rule also should include a
`dependency_target_substitution`, to ensures that the inferred rules in the generated
`com/google/dagger/BUILD` file consume `:dagger_api` instead of the wrapper replacement target, or
use `include` and `exclude` statements on the `com.google.dagger:dagger-compiler` artifact to have
it depend on the now-renamed target (see the test/test_workspace for an example of this)

```python
maven_repository_specification(
    name = "maven",
    artifacts = {
        "com.google.dagger:dagger:2.20": {
            "sha256": "blahblahblah",
            "build_snippet": DAGGER_PROCESSOR_SNIPPET,
        },
        "com.google.dagger:dagger-compiler:2.20": { "sha256": "blahblahblah" },
        "com.google.dagger:dagger-producers:2.20": { "sha256": "blahblahblah" },
        "com.google.dagger:dagger-spi:2.20": { "sha256": "blahblahblah" },
        "com.google.code.findbugs:jsr305:3.0.2": { "sha256": "blahblahblah" },
        # ... all the other deps.
    },
    dependency_target_substitutes = {
        "com.google.dagger": {"@maven//com/google/dagger:dagger": "@maven//com/google/dagger:dagger_api"},
    }
)
```

Thereafter, any target with a dependency on (in this example) `@maven//com/google/dagger` will
invoke annotation processing and generate any dagger-generated code. A similar pattern could be
used for [AutoFactory and AutoValue](http://github.com/google/auto), configuring kotlinc 
plugins, etc.

Such snippet constants can be extracted into .bzl files and imported to keep the WORKSPACE file
tidy. In the future some standard templates may be offered by this project, but not until deps
validation is available, as it would be too easy to have templates' deps lists go out of date as
versions bumped, if no other validation prevented it or notified about it.

> Note: This feature is incompatible with `"include": [...]` `"exclude": [...]` and
> `"deps": "..."` mechanisms, as it entirely takes responsibility for the targets written
> into the build file, and therefore, any dependencies.  It also overrides a lot of warnings.

## Caching

**Bazel Maven Repository 1.2.0 and prior:**
Bazel can cache artifacts if you provide sha256 hashes.  These will make the artifacts candidates
for the "content addressable" cache, which is machine-wide, and survives even `bazel clean --expunge`.
The caveat for this is that if you put the wrong hash, and if that hash is to a file you already have
downloaded, bazel's internal download mechanism will serve that file instead of the remote file. This
can cause you to accidentally supply a wrong version, wrong artifact, or wrong kind of file if you're
not careful.  So take caution when recording the sha256 hashes, both for security and performance
reasons.  The hash will be preferred over the artifact as a way to identify the artifact, under the
hood.

Pom.xml files are not cached, and will be re-downloaded when your workspace needs regenerating.


**Bazel Maven Repository 2.0 and later:**
The rules will cache maven artifacts and metadata via the `~/.m2/repository` "local repository"
exactly as maven would. 

# Limitations

  * Doesn't support -SNAPSHOT dependencies (#5) (pending 2.0)
  * Doesn't support multiple versions of a dependency (by design).
  * Doesn't support multiple calls to `maven_repository_specification()` due to collisions in
    the implicit fetching rules it creates. This limitation will be lifted in a version. (#6)
    (pending 2.0)
  * Doesn't support -source.jar downloading and attachment. (#44) (pending 2.0)

## Other Usage Notes

### Caches

Because of the nature of bazel repository/workspace operation, updating the list of artifacts
invalidates the analysis cache, and force a re-run of workspace operations (and possibly reduce
incrementality of the next build).  As of 2.0, the workspace generation is drastically faster.

### Clogged WORKSPACE files

It may make sense, if one's maven universe gets big, to extract the list of artifacts into a 
constant in a separate file (e.g. `maven_artifacts.bzl`) and import it.

### Kotlin

#### ijar (abi-jar) and inline functions

Bazel Maven Repository uses a raw_jvm_import target which does *not* invoke **ijar** as it is
known to break Kotlin artifacts with inlined operators and inlined types. 

#### rules_kotlin and maven integration paths

[rules_kotlin] currently break when running in full sandbox mode (without the kotlin compilation
worker).  Specifically, it misinterprets paths in the sandbox.  Therefore, if using [rules_kotlin]
it is crucial to include `--strategy=KotlinCompile=worker` either on the command-line, or in the
project's .bazelrc or your personal .bazelrc.  Otherwise, the annotation processor will fail to
find the jar contents for annotation processors such as `Dagger 2` or `AutoValue` or `AutoFactory`.

## License

License
Copyright 2018 Square, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
