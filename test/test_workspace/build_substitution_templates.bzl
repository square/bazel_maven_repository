# Description:
#   String variables containing build-file segment substitutes, to be used with the
#   `maven_repository_specification(build_substitutes = {...})` dictionary property.  These have specific documentation
#   on any template variables
#
#   Given the volatility (and lack of automation) of the deps lists in these substitutions, these templates aren't
#   intended for generic usage.  They can be freely cut-and-pasted as given in this example file, but the deps list
#   needs curation.  Indeed, it mostly only has variable substitution because the unversioned coordinates don't change
#   so frequently.


# Description:
#   Substitutes the naive maven_jvm_artifact for com.google.dagger:dagger with a flagor that exports the compiler
#   plugin.  Contains the `dagger_version` substitution variable.
#
# Usage:
#
#   maven_repository_specification(
#       ...
#       build_substitutes = {
#           "com.google.dagger:dagger": DAGGER_PLUGIN_BUILD_SUBSTITUTE.format(dagger_version = "2.20", repo = "maven"),
#       }
#   )
#
# Note:
#   This set of internal dependencies is valid as of dagger 2.20. Other versions may require different deps.
#
DAGGER_PLUGIN_BUILD_SUBSTITUTE = """
java_library(
    name = "dagger",
    exports = [
        ":dagger_api",
        "@maven//javax/inject:javax_inject",
    ],
    exported_plugins = [":dagger_plugin"],
    visibility = ["//visibility:public"],
)

maven_jvm_artifact(
    name = "dagger_api",
    artifact = "com.google.dagger:dagger:{dagger_version}",
)

java_plugin(
    name = "dagger_plugin",
    processor_class = "dagger.internal.codegen.ComponentProcessor",
    generates_api = True,
    deps = [
        ":dagger_api",
        ":dagger_compiler",
        ":dagger_producers",
        ":dagger_spi",
        "@{repo}//com/google/code/findbugs:jsr305",
        "@{repo}//com/google/errorprone:javac_shaded",
        "@{repo}//com/google/googlejavaformat:google_java_format",
        "@{repo}//com/google/guava",
        "@{repo}//com/squareup:javapoet",
        "@{repo}//org/checkerframework:checker_compat_qual",
        "@{repo}//javax/annotation:jsr250_api",
        "@{repo}//javax/inject:javax_inject",
    ],
)
"""
