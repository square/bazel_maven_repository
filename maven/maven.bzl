#
# Copyright (C) 2018 Square, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
# in compliance with the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License
# is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing permissions and limitations under
# the License.

# Description:
#   A repository rule intended to be used in populating @maven_repository.
#
load(":artifacts.bzl", artifact_utils = "artifacts")
load(":globals.bzl", "DOWNLOAD_PREFIX", "fetch_repo")
load(":fetch.bzl", "fetch_artifact", "fetch_pom")
load(":jvm.bzl", "raw_jvm_import")
load(":packaging_type.bzl", "packaging_type")
load(":poms.bzl", "poms")
load(":sets.bzl", "sets")
load(":utils.bzl", "dicts", "paths", "strings")

#enum
artifact_config_properties = struct(
    SHA256 = "sha256",
    POM_SHA256 = "pom_sha256",
    INSECURE = "insecure",
    EXCLUDE = "exclude",
    BUILD_SNIPPET = "build_snippet",
    TEST_ONLY = "testonly",
    values = ["sha256", "pom_sha256", "insecure", "exclude", "build_snippet", "testonly"],
)

_RUNTIME_DEPENDENCY_SCOPES = sets.new("compile", "runtime")
_POM_XPATH_DEPENDENCIES_QUERY = """/project/dependencies/dependency[not(scope) or scope/text()="compile"]"""
_INSECURE_DEPRECATION_WARNING = """WARNING: Using "insecure_artifacts" is deprecated.
Please use the regular artifacts and set insecure to true. e.g.:
artifacts = {
    "%s": { "insecure" : True }
}"""
_STRING_SHA_VALUE_DEPRECATION_WARNING = """WARNING: Passing the sha256 as the dictionary value for an artifact is deprecated.
Please pass in a dictionary for the artifact like this:
artifacts = {
    "%s": { "sha256" : "%s" }
}"""
_LEGACY_BUILD_SUBSTITUTIONS_DEPRECATION_WARNING = """WARNING: Passing the build snippet via build_substitutes is deprecated.
Please pass the snippet for %s as a configuration property in the artifact dictionary."""

_MAVEN_REPO_BUILD_PREFIX = """# Generated bazel build file for maven group {group_id}

load("@{maven_rules_repository}//maven:maven.bzl", "maven_jvm_artifact")
"""

_MAVEN_REPO_TARGET_TEMPLATE = """maven_jvm_artifact(
    name = "{target}",{test_only}
    artifact = "{artifact_spec}",
    type = "{type}",
{deps})
"""

_LEGACY_NAME_MANGLING_ALIAS = """alias(
    name = "{name}",
    actual = ":{actual}",
    visibility = ["//visibility:public"],
)
"""

def _convert_maven_dep(repo_name, artifact):
    group_path = artifact.group_id.replace(".", "/")
    target = strings.munge(artifact.artifact_id, ".")
    return "@{repo}//{group_path}:{target}".format(repo = repo_name, group_path = group_path, target = target)

def _normalize_target(full_target_spec, current_package, target_substitutions):
    full_target_spec = target_substitutions.get(full_target_spec, full_target_spec)
    full_package, target = full_target_spec.split(":")
    local_package = full_package.split("//")[1]  # @maven//blah/foo -> blah/foo
    if local_package == current_package:
        return ":%s" % target  # Trim to a local reference.
    return full_package if paths.filename(full_package) == target else full_target_spec

def _get_dependencies_from_project(ctx, exclusions, project):
    exclusions = sets.copy_of(exclusions)
    maven_deps = [d for d in poms.extract_dependencies(project) if not sets.contains(exclusions, d.coordinates)]
    return maven_deps

def _deps_string(bazel_deps):
    if not bool(bazel_deps):
        return ""
    bazel_deps = ["""        "%s",""" % x for x in bazel_deps]
    return "    deps = [\n%s\n    ]\n" % "\n".join(bazel_deps) if bool(bazel_deps) else ""

def _should_include_dependency(dep):
    return (
        sets.contains(_RUNTIME_DEPENDENCY_SCOPES, dep.scope) and
        not bool(dep.system_path) and
        not dep.optional
    )

def _generate_maven_repository_impl(ctx):
    # Generate the root WORKSPACE file
    repository_root_path = ctx.path(".")
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))

    # Generate the per-group_id BUILD.bazel files.
    build_snippets = ctx.attr.build_snippets
    target_substitutes = dicts.decode_nested(ctx.attr.dependency_target_substitutes)
    test_only_artifacts = sets.copy_of(ctx.attr.test_only_artifacts)
    known_artifacts = sets.new()
    processed_artifacts = sets.new()
    for grouped_specs in ctx.attr.grouped_artifacts.values():
        for spec in grouped_specs:
            sets.add(known_artifacts, artifact_utils.parse_spec(spec).coordinates)
    build_files = {}
    for group_id, specs_list in ctx.attr.grouped_artifacts.items():
        package_target_substitutes = target_substitutes.get(group_id, {})
        specs = sets.copy_of(specs_list)
        ctx.report_progress("Generating build details for %s artifacts in %s" % (len(specs), group_id))
        prefix = _MAVEN_REPO_BUILD_PREFIX.format(
            group_id = group_id,
            maven_rules_repository = ctx.attr.maven_rules_repository,
        )
        target_definitions = []
        group_path = group_id.replace(".", "/")
        for spec in specs:
            artifact = artifact_utils.parse_spec(spec)
            if processed_artifacts.get(artifact.coordinates):
                fail("Already processed %s!!!!!" % artifact.coordinates)
            sets.add(processed_artifacts, artifact.coordinates)
            snippet = build_snippets.get(artifact.coordinates)
            if snippet:
                target_definitions.append(snippet)
            else:
                exclusions = ctx.attr.exclusions.get(artifact.original_spec, [])
                pom = poms.get_project_metadata(ctx, artifact)
                maven_deps = _get_dependencies_from_project(ctx, exclusions, pom)
                maven_deps = [x for x in maven_deps if _should_include_dependency(x)]
                found_artifacts = {}
                bazel_deps = []
                for dep in maven_deps:
                    found_artifacts[dep.coordinates] = dep
                    bazel_deps += [_convert_maven_dep(ctx.attr.name, dep)]
                normalized_deps = [_normalize_target(x, group_path, package_target_substitutes) for x in bazel_deps]
                unregistered = sets.difference(known_artifacts, sets.copy_of(found_artifacts))
                if bool(unregistered):
                    unregistered_deps = [
                        poms.format_dependency(x)
                        for x in maven_deps
                        if sets.contains(unregistered, x.coordinates)
                    ]
                    fail("Some dependencies of %s were not pinned in the artifacts list:\n%s" % (
                        spec,
                        list(unregistered_deps),
                    ))
                test_only_subst = (
                    "\n    testonly = True," if sets.contains(test_only_artifacts, spec) else ""
                )
                target_definitions.append(
                    _MAVEN_REPO_TARGET_TEMPLATE.format(
                        target = strings.munge(artifact.artifact_id, "."),
                        deps = _deps_string(normalized_deps),
                        artifact_spec = artifact.original_spec,
                        type = poms.extract_packaging(pom),
                        test_only = test_only_subst,
                    ),
                )

                # Optionally add a legacy munge target
                # TODO(cgruber) Rip this out after a few versions.
                if ctx.attr.legacy_artifact_id_munge:
                    legacy = strings.munge(artifact.artifact_id, ".", "-")
                    new = strings.munge(artifact.artifact_id, ".")
                    if (legacy != new):
                        target_definitions.append(
                            _LEGACY_NAME_MANGLING_ALIAS.format(name = legacy, actual = new),
                        )
        file = "%s/BUILD.bazel" % group_path
        content = "\n".join([prefix] + target_definitions)
        ctx.file(file, content)

_generate_maven_repository = repository_rule(
    implementation = _generate_maven_repository_impl,
    attrs = {
        "grouped_artifacts": attr.string_list_dict(),
        "maven_rules_repository": attr.string(mandatory = False, default = "maven_repository_rules"),
        "dependency_target_substitutes": attr.string_list_dict(),
        "build_snippets": attr.string_dict(),
        "test_only_artifacts": attr.string_list(),
        "exclusions": attr.string_list_dict(),
        "legacy_artifact_id_munge": attr.bool(mandatory = False, default = False),
        "poms": attr.label_list(),
    },
)

# Check... you know... for duplicates.  And fail if there are any, listing the extra artifacts.  Also fail if
# there are -SNAPSHOT versions, since bazel requires pinned versions.
def _check_for_duplicates(artifact_specs):
    distinct_artifacts = {}
    for artifact_spec in artifact_specs:
        artifact = artifact_utils.parse_spec(artifact_spec)
        distinct = "%s:%s" % (artifact.group_id, artifact.artifact_id)
        if not distinct_artifacts.get(distinct):
            distinct_artifacts[distinct] = {}
        sets.add(distinct_artifacts[distinct], artifact.version)
    for artifact, versions in distinct_artifacts.items():
        if len(versions.keys()) > 1:
            fail("Several versions of %s are specified in maven_artifacts.bzl: %s" % (artifact, versions.keys()))
        elif sets.pop(versions).endswith("-SNAPSHOT"):
            fail("Snapshot versions are not supported in maven_artifacts.bzl.  Please fix %s to a pinned version." % artifact)

def _unsupported_keys(keys_list):
    return sets.difference(sets.copy_of(artifact_config_properties.values), sets.copy_of(keys_list))

def _fix_string_booleans(value):
    return value.lower() == "true" if type(value) == type("") else bool(value)

# If artifact/sha pair has missing sha hashes, reject it.
def _validate_artifacts(artifacts):
    errors = []
    if not bool(artifacts):
        errors += ["At least one artifact must be specified."]
    for spec, properties in artifacts.items():
        if type(properties) != type({}):
            errors += ["""Artifact %s has an invalid property dictionary. Should not be a %s""", (spec, type(properties))]
        unsupported_keys = _unsupported_keys(properties.keys())
        if bool(unsupported_keys):
            errors += ["""Artifact %s has unsupported property keys: %s. Only %s are supported""" % (
                spec,
                list(unsupported_keys),
                list(artifact_config_properties.values),
            )]
        artifact = artifact_utils.parse_spec(spec)  # Basic sanity check.
        if not bool(artifact.version):
            errors += ["""Artifact "%s" missing version""" % spec]
        if (not properties.get(artifact_config_properties.SHA256) and
            not _fix_string_booleans(properties.get(artifact_config_properties.INSECURE, False))):
            errors += ["""Artifact "%s" is mising a sha256. Either supply it or mark it "insecure".""" % spec]
        if (properties.get(artifact_config_properties.SHA256) and
            _fix_string_booleans(properties.get(artifact_config_properties.INSECURE, False))):
            errors += ["""Artifact "%s" cannot be both insecure and have a sha256.  Specify one or the other.""" % spec]
    if bool(errors):
        fail("Errors found:\n    %s" % "\n    ".join(errors))

# Pre-process the artifacts dictionary and handle older APIs that are now deprecated, until we
# delete them.
def _handle_legacy_specifications(artifacts, insecure_artifacts, build_snippets):
    # Legacy deprecated feature backwards compatibility
    for spec in insecure_artifacts:
        print(_INSECURE_DEPRECATION_WARNING % spec)
        artifacts += {spec: {"insecure": "true"}}
    for key in artifacts.keys():
        value = artifacts[key]
        if type(value) == type(""):
            print(_STRING_SHA_VALUE_DEPRECATION_WARNING % (key, value))
            artifacts[key] = {artifact_config_properties.SHA256: value}

    # map versioned artifacts to versionless
    versionless_mapping = {}
    for key in artifacts:
        artifact = artifact_utils.parse_spec(key)
        versionless_mapping[artifact.coordinates] = key
    for key, snippet in build_snippets.items():
        versioned_key = versionless_mapping.get(key)
        if not bool(versioned_key):
            fail("Artifact %s listed in build_substitutions not present in main artifact list.", key)
        config = artifacts[versioned_key]
        config[artifact_config_properties.BUILD_SNIPPET] = snippet
        print(_LEGACY_BUILD_SUBSTITUTIONS_DEPRECATION_WARNING % versioned_key)
    return artifacts

####################
# PUBLIC FUNCTIONS #
####################

# Creates java or android library targets from maven_hosted .jar/.aar files.
def maven_jvm_artifact(
        # The specification of the artifact (e.g. "com.google.guava:guava:1.2.3")
        artifact,

        # The name of this target, typically the same as the artifact_id of the artifact.
        name = None,

        # the packaging type (suffix) of the file
        type = None,

        # Visibility of this target (default: ["//visibility:public"])
        visibility = ["//visibility:public"],

        # Any dependencies of this artifact.
        deps = [],

        # Extra arguments passed through to the raw import rules that underly this macro.
        **kwargs):
    artifact_struct = artifact_utils.parse_spec(artifact)
    artifact_type = packaging_type.value_of(type) if bool(type) else packaging_type.value_of(artifact_struct.type)
    maven_target = fetch_repo.artifact_target(artifact_struct, artifact_type.suffix)
    if artifact_type.suffix == "jar":
        raw_jvm_import(name = name, deps = deps, visibility = visibility, jar = maven_target, **kwargs)
    elif artifact_type.suffix == "aar":
        native.aar_import(name = name, deps = deps, visibility = visibility, aar = maven_target, **kwargs)
    else:
        fail("%s is not a supported artifact type. Currently only jar/aar are supported." % artifact_struct.type.name)

# Description:
#   Generates the bazel repo and download logic for each artifact (and repository URL prefixes) in the WORKSPACE
#   Makes a bazel repository out of the artifacts supplied, downloading them into a well-ordered repository structure,
#   targets (by default, including name mangling).
#
#   A substitution mechanism is present to permit swapping in alternative build rules, say for cases where you need
#   to use an `exported_plugins` property, e.g. using dagger.  The text supplied naively replaces the automatically
#   generated `maven_jvm_artifact()` rule.
#
def maven_repository_specification(
        # The name of the repository
        name,

        # The dictionary of artifact -> properties which allows us to specify artifacts with more details.  These
        # properties don't include the group, artifact name, version, classifier, or type, which are all specified
        # by the artifact key itself.
        #
        # The currently supported properties are:
        #    sha256 -> the hash of the artifact file to be downloaded. (Incompatible with "insecure")
        #    insecure -> if true, don't fail on a missing sha256 hash. (Incompatible with "sha256")
        artifacts = {},

        # The list of artifacts (without sha256 hashes) that will be used without file hash checking.
        # DEPRECATED: Please use artifacts with an "insecure = true" property.
        insecure_artifacts = [],

        # The dictionary of build-file substitutions (per-target) which will replace the auto-generated target
        # statements in the generated repository
        build_substitutes = {},

        # The dictionary of per-group target substitutions.  These must be in the format:
        # "@myreponame//path/to/package:target": "@myrepotarget//path/to/package:alternate"
        dependency_target_substitutes = {},

        # Optional list of repositories which the build rule will attempt to fetch maven artifacts and metadata.
        repository_urls = ["https://repo1.maven.org/maven2"],

        # If True, then generate a legacy target with the older artifact-id munging, to allow migration to the newer
        # target naming. (Specifically, do we turn "-" into "_" in the target naming).
        legacy_artifact_id_munge = False,

        # If True, then cache poms based on the sha256 of the first downloaded occurrance.
        cache_poms_insecurely = False,

        # Supply a cache directory (relative to $HOME of the current user, or absolute) into which
        # to cache the pom file hashes, which will enable them to participate in the content-
        # addressable cache.  By default they are not cached locally unless pom_sha256 is supplied
        # for that artifact.
        insecure_cache = ".cache/bazel_maven_repository/hashes"):
    _handle_legacy_specifications(artifacts, insecure_artifacts, build_substitutes)

    if len(repository_urls) == 0:
        fail("You must specify at least one repository root url.")
    if len(artifacts) == 0:
        fail("You must register at least one artifact.")

    _validate_artifacts(artifacts)

    _check_for_duplicates(artifacts)
    grouped_artifacts = {}
    build_snippets = {}
    pom_sha256_hashes = {}
    test_only_artifacts = []
    exclusions = {}
    artifact_structs = {}
    poms = []

    # First pass, since some thing need to be globally available to each (like explicit pom shas)
    for artifact_spec, properties in artifacts.items():
        artifact_structs[artifact_spec] = artifact_utils.parse_spec(artifact_spec)
        pom_hash = properties.get(artifact_config_properties.POM_SHA256)
        if bool(pom_hash):
            pom_sha256_hashes[artifact_spec] = pom_hash

    for artifact_spec, properties in artifacts.items():
        artifact = artifact_structs[artifact_spec]

        # Track group_ids in order to build per-group BUILD.bazel files.
        grouped_artifacts[artifact.group_id] = (
            grouped_artifacts.get(artifact.group_id, default = []) + [artifact.original_spec]
        )
        pom_sha256_hash = properties.get(artifact_config_properties.POM_SHA256)
        fetch_pom(
            name = fetch_repo.pom_repo_name(artifact),
            artifact = artifact_spec,
            repository_urls = repository_urls,
            cache_poms_insecurely = cache_poms_insecurely,
            insecure_cache = insecure_cache,
            pom_hashes = pom_sha256_hashes,
        )
        poms.append(fetch_repo.pom_target(artifact))

        sha256 = properties.get(artifact_config_properties.SHA256)
        fetch_artifact(
            name = fetch_repo.artifact_repo_name(artifact),
            artifact = artifact_spec,
            repository_urls = repository_urls,
            sha256 = sha256,
            pom = fetch_repo.pom_target(artifact),
        )

        snippet = properties.get(artifact_config_properties.BUILD_SNIPPET)
        if bool(snippet):
            build_snippets[artifact.coordinates] = snippet

        if bool(properties.get(artifact_config_properties.TEST_ONLY)):
            test_only_artifacts += [artifact_spec]

        if bool(properties.get(artifact_config_properties.EXCLUDE)):
            exclusions[artifact_spec] = properties.get(artifact_config_properties.EXCLUDE)

    # Skylark rules can't take in arbitrarily deep dicts, so we rewrite dict(string->dict(string, string)) to an
    # encoded (but trivially splittable) dict(string->list(string)).  Yes it's gross.
    dependency_target_substitutes_rewritten = dicts.encode_nested(dependency_target_substitutes)
    _generate_maven_repository(
        name = name,
        grouped_artifacts = grouped_artifacts,
        dependency_target_substitutes = dependency_target_substitutes_rewritten,
        build_snippets = build_snippets,
        test_only_artifacts = test_only_artifacts,
        exclusions = exclusions,
        legacy_artifact_id_munge = legacy_artifact_id_munge,
        poms = poms,
    )

####################
# Test-only Struct #
####################
for_testing = struct(
    unsupported_keys = _unsupported_keys,
    handle_legacy_specifications = _handle_legacy_specifications,
    get_dependencies_from_project = _get_dependencies_from_project,
)
