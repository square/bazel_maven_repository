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
#           "com.google.dagger:dagger": DAGGER_BUILD_SNIPPET_WITH_PLUGIN.format(version = "2.20"),
#       }
#   )
#
DAGGER_BUILD_SNIPPET_WITH_PLUGIN = """
java_library(
   name = "dagger",
   exports = [":dagger_api"],
   exported_plugins = [":dagger_plugin"],
   visibility = ["//visibility:public"],
)

maven_jvm_artifact(
   name = "dagger_api",
   artifact = "com.google.dagger:dagger:{version}",
)

java_plugin(
   name = "dagger_plugin",
   processor_class = "dagger.internal.codegen.ComponentProcessor",
   generates_api = True,
   deps = [":dagger_compiler"],
)
"""

# Description:
#   Substitutes the naive maven_jvm_artifact for com.google.dagger:dagger with a flagor that exports the compiler
#   plugin.  Contains the `dagger_version` substitution variable.
#
# Usage:
#
#   maven_repository_specification(
#       ...
#       build_substitutes = {
#           "com.google.dagger:dagger": DAGGER_BUILD_SNIPPET_WITH_PLUGIN.format(version = "2.20"),
#       }
#   )
#
AUTO_VALUE_BUILD_SNIPPET_WITH_PLUGIN = """
java_library(
   name = "value",
   exports = [":auto_value_annotations"],
   exported_plugins = [":plugin"],
   visibility = ["//visibility:public"],
)

maven_jvm_artifact(
   name = "auto_value_processor",
   artifact = "com.google.auto.value:auto-value:{version}",
)

java_plugin(
   name = "plugin",
   processor_class = "com.google.auto.value.processor.AutoValueProcessor",
   generates_api = True,
   deps = [":auto_value_processor"],
)
"""
