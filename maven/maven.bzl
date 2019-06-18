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
load(":artifacts.bzl", "artifacts")
load(":jvm.bzl", "raw_jvm_import")
load(":poms.bzl", "poms")
load(":sets.bzl", "sets")
load(":utils.bzl", "dicts", "paths", "strings")

#enum
artifact_config_properties = struct(
    SHA256 = "sha256",
    POM_SHA256 = "pom_sha256",
    INSECURE = "insecure",
    BUILD_SNIPPET = "build_snippet",
    values = ["sha256", "pom_sha256", "insecure", "build_snippet"],
)

_DOWNLOAD_PREFIX = "maven"
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
_ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE = """
package(default_visibility = ["//visibility:public"])
filegroup(
    name = "{prefix}",
    srcs = ["{path}"],
)
"""

_POM_HASH_CACHE_WRITE_SCRIPT = "bin/pom_hash_cache_write.sh"

#TODO(cgruber) move this into a toolchain (and make a windows equivalent)
_POM_HASH_CACHE_WRITE_SCRIPT_CONTENT = """#!/bin/sh
content="$1"
cache_file="$2"
mkdir -p $(dirname "${cache_file}")
echo "${content}" > ${cache_file}
"""

_POM_HASH_INFIX = "sha256"

def _fetch_artifact_impl(ctx):
    repository_root_path = ctx.path(".")
    forbidden_files = [
        repository_root_path,
        ctx.path("WORKSPACE"),
        ctx.path("BUILD"),
        ctx.path("BUILD.bazel"),
        ctx.path("%s/BUILD" % _DOWNLOAD_PREFIX),
        ctx.path("%s/BUILD.bazel" % _DOWNLOAD_PREFIX),
    ]
    local_path = "%s/%s" % (_DOWNLOAD_PREFIX, ctx.attr.local_path)
    download_path = ctx.path(local_path)
    if download_path in forbidden_files or not str(download_path).startswith(str(repository_root_path)):
        fail("Invalid local_path: %s" % ctx.attr.local_path)
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))
    ctx.file(
        "%s/BUILD.bazel" % _DOWNLOAD_PREFIX,
        _ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE.format(prefix = _DOWNLOAD_PREFIX, path = ctx.attr.local_path),
    )
    ctx.download(url = ctx.attr.urls, output = local_path, sha256 = ctx.attr.sha256)

_fetch_artifact = repository_rule(
    implementation = _fetch_artifact_impl,
    attrs = {
        "local_path": attr.string(),
        "sha256": attr.string(),
        "urls": attr.string_list(mandatory = True),
    },
)

_MAVEN_REPO_BUILD_PREFIX = """# Generated bazel build file for maven group {group_id}

load("@{maven_rules_repository}//maven:maven.bzl", "maven_jvm_artifact")
"""

_MAVEN_REPO_TARGET_TEMPLATE = """maven_jvm_artifact(
    name = "{target}",
    artifact = "{artifact_coordinates}",
{deps})
"""

def _convert_maven_dep(repo_name, artifact):
    group_path = artifact.group_id.replace(".", "/")
    target = artifacts.munge_target(artifact.artifact_id)
    return "@{repo}//{group_path}:{target}".format(repo = repo_name, group_path = group_path, target = target)

def _normalize_target(full_target_spec, current_package, target_substitutions):
    full_target_spec = target_substitutions.get(full_target_spec, full_target_spec)
    full_package, target = full_target_spec.split(":")
    local_package = full_package.split("//")[1]  # @maven//blah/foo -> blah/foo
    if local_package == current_package:
        return ":%s" % target  # Trim to a local reference.
    return full_package if paths.filename(full_package) == target else full_target_spec

# Try to obtain the sha256 of the pom file, so it can be resolved from the CA cache (if
# present).
#
# Note, this is strictly insecure, insofar as we are trusting the first download and caching the
# sha of the file first downloaded.  However, this is not the artifact, and even if hostile pom
# metadata were introduced, it could only point at dependencies listed in the master list, or else
# errors will be surfaced, so there is a signal that something has intercepted.  More rigorous
# usage is possible by setting the pom_sha256 property in the configuration of the artifact.
def _get_pom_sha256(ctx, artifact, urls, file):
    ctx.report_progress("Obtaining hash for %s" % file)
    explicit_sha256 = ctx.attr.pom_sha256_hashes.get(artifact.original_spec)
    if explicit_sha256:
        return explicit_sha256
    if ctx.attr.insecure_cache.startswith("/"):
        cache_dir = "%s/%s" % (ctx.attr.insecure_cache, _POM_HASH_INFIX)
    else:
        cache_dir = "%s/%s/%s" % (ctx.os.environ["HOME"], ctx.attr.insecure_cache, _POM_HASH_INFIX)
    cached_file = "%s/%s.sha256" % (cache_dir, file)
    sha_cache_result = ctx.execute(["cat", cached_file])
    if sha_cache_result.return_code != 0:
        # This will result in a CA cache miss and an extra download on first use, since the first
        # (non-sha-attributed) download won't store anything in the CA cache.
        ctx.report_progress("%s not locally cached, fetching and hashing" % cached_file)
        pom_result = ctx.download(url = urls, output = file)
        result = ctx.execute([_POM_HASH_CACHE_WRITE_SCRIPT, pom_result.sha256, cached_file])
        if result.return_code != 0:
            fail("Cache write failed with code %s, stderr: %s", (result.return_code, result.stderr))
        return pom_result.sha256
    else:
        return strings.trim(sha_cache_result.stdout)

# Fetch the pom for the artifact.  First see if a cached hash is available for it. If so, use
# that hash to try a download with the sha, to get a hit on the content addressable cache. If not
# fetch normally and write that hash to the pom hash cache for next time.
#
# This should be in poms.bzl, but we want to keep ctx/network/file operations separate,
# and Starlark is constrained enough that creating a "downloader" struct is more trouble than
# it's worth.
def _fetch_pom(ctx, artifact):
    urls = ["%s/%s" % (repo, artifact.pom) for repo in ctx.attr.repository_urls]
    file = "{group_id}/{artifact_id}-{version}.pom".format(
        group_id = artifact.group_path,
        artifact_id = artifact.artifact_id,
        version = artifact.version,
    )
    ctx.report_progress("Fetching %s" % file)

    sha256 = _get_pom_sha256(ctx, artifact, urls, file) if ctx.attr.cache_poms_insecurely else None
    if sha256:
        ctx.download(url = urls, sha256 = sha256, output = file)
    else:
        ctx.download(url = urls, output = file)
    return ctx.read(file)

# In theory, this logic should live in poms.bzl, but bazel makes it harder to use the strategy pattern (to pass in a
# downloader) and we want to keep file and network code out of the poms processing code.
def _get_inheritance_chain(ctx, xml_text):
    inheritance_chain = [poms.parse(xml_text)]
    current = inheritance_chain[0]
    for _ in range(100):  # Can't use recursion, so just iterate
        raw_parent_artifact = poms.extract_parent(current)
        if not bool(raw_parent_artifact):
            break
        parent_artifact = artifacts.annotate(raw_parent_artifact)
        parent_node = poms.parse(_fetch_pom(ctx, parent_artifact))
        inheritance_chain += [parent_node]
        current = parent_node
    return inheritance_chain

# Take an inheritance chain of xml trees (Fetched by _get_inheritance_chain) and merge them from
# the top (the end of the list) to the bottom (the beginning of the list)
def _get_effective_pom(inheritance_chain):
    merged = inheritance_chain.pop()
    for next in reversed(inheritance_chain):
        merged = poms.merge_parent(parent = merged, child = next)
    return merged

def _get_dependencies_from_pom_files(ctx, artifact):
    inheritance_chain = _get_inheritance_chain(ctx, _fetch_pom(ctx, artifact))
    project = _get_effective_pom(inheritance_chain)
    maven_deps = poms.extract_dependencies(project)
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
    ctx.file(
        _POM_HASH_CACHE_WRITE_SCRIPT,
        content = _POM_HASH_CACHE_WRITE_SCRIPT_CONTENT,
        executable = True,
    )

    # Generate the per-group_id BUILD.bazel files.
    build_snippets = ctx.attr.build_snippets
    target_substitutes = dicts.decode_nested(ctx.attr.dependency_target_substitutes)
    processed_artifacts = sets.new()
    for specs in ctx.attr.grouped_artifacts.values():
        artifact_structs = [artifacts.parse_spec(s) for s in specs]
        sets.add_all(processed_artifacts, ["%s:%s" % (a.group_id, a.artifact_id) for a in artifact_structs])
    build_files = {}
    for group_id, specs_list in ctx.attr.grouped_artifacts.items():
        package_target_substitutes = target_substitutes.get(group_id, {})
        ctx.report_progress("Generating build details for artifacts in %s" % group_id)
        specs = sets.copy_of(specs_list)
        prefix = _MAVEN_REPO_BUILD_PREFIX.format(
            group_id = group_id,
            maven_rules_repository = ctx.attr.maven_rules_repository,
        )
        target_definitions = []
        group_path = group_id.replace(".", "/")
        for spec in specs:
            artifact = artifacts.annotate(artifacts.parse_spec(spec))
            coordinates = "%s:%s" % (artifact.group_id, artifact.artifact_id)
            sets.add(processed_artifacts, coordinates)
            snippet = build_snippets.get(coordinates)
            if snippet:
                target_definitions.append(snippet)
            else:
                maven_deps = _get_dependencies_from_pom_files(ctx, artifact)
                maven_deps = [x for x in maven_deps if _should_include_dependency(x)]
                found_artifacts = {}
                bazel_deps = []
                for dep in maven_deps:
                    found_artifacts[dep.coordinate] = dep
                    bazel_deps += [_convert_maven_dep(ctx.attr.name, dep)]
                normalized_deps = [_normalize_target(x, group_path, package_target_substitutes) for x in bazel_deps]
                unregistered = sets.difference(processed_artifacts, sets.copy_of(found_artifacts))
                if bool(unregistered):
                    unregistered_deps = [
                        poms.format_dependency(x)
                        for x in maven_deps
                        if sets.contains(unregistered, x.coordinate)
                    ]
                    fail("Some dependencies of %s were not pinned in the artifacts list:\n%s" % (
                        spec,
                        list(unregistered_deps),
                    ))
                target_definitions.append(
                    _MAVEN_REPO_TARGET_TEMPLATE.format(
                        target = artifact.third_party_target_name,
                        deps = _deps_string(normalized_deps),
                        artifact_coordinates = artifact.original_spec,
                    ),
                )
        file = "%s/BUILD.bazel" % group_path
        content = "\n".join([prefix] + target_definitions)
        ctx.file(file, content)

# build_files[build_file] = build_content

_generate_maven_repository = repository_rule(
    implementation = _generate_maven_repository_impl,
    attrs = {
        "grouped_artifacts": attr.string_list_dict(mandatory = True),
        "repository_urls": attr.string_list(mandatory = True),
        "maven_rules_repository": attr.string(mandatory = False, default = "maven_repository_rules"),
        "dependency_target_substitutes": attr.string_list_dict(mandatory = True),
        "build_snippets": attr.string_dict(mandatory = True),
        "cache_poms_insecurely": attr.bool(mandatory = True),
        "insecure_cache": attr.string(mandatory = False),
        "pom_sha256_hashes": attr.string_dict(mandatory = True),
    },
)

# Implementation of the maven_jvm_artifact rule.
def _maven_jvm_artifact(artifact_spec, name, visibility, deps = [], **kwargs):
    artifact = artifacts.annotate(artifacts.parse_spec(artifact_spec))
    maven_target = "@%s//%s:%s" % (artifact.maven_target_name, _DOWNLOAD_PREFIX, artifact.path)
    import_target = artifact.maven_target_name + "_import"
    target_name = name if name else artifact.third_party_target_name
    if artifact.packaging == "jar":
        raw_jvm_import(name = target_name, deps = deps, visibility = visibility, jar = maven_target, **kwargs)
    elif artifact.packaging == "aar":
        native.aar_import(name = target_name, deps = deps, visibility = visibility, aar = maven_target, **kwargs)
    else:
        fail("Packaging %s not supported by maven_jvm_artifact." % artifact.packaging)

# Check... you know... for duplicates.  And fail if there are any, listing the extra artifacts.  Also fail if
# there are -SNAPSHOT versions, since bazel requires pinned versions.
def _check_for_duplicates(artifact_specs):
    distinct_artifacts = {}
    for artifact_spec in artifact_specs:
        artifact = artifacts.parse_spec(artifact_spec)
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
    if type(value) == type(""):
        return value.lower() == "true"
    return bool(value)

# If artifact/sha pair has missing sha hashes, reject it.
def _validate_artifacts(artifact_definitions):
    errors = []
    if not bool(artifacts):
        errors += ["At least one artifact must be specified."]
    for spec, properties in artifact_definitions.items():
        if type(properties) != type({}):
            errors += ["""Artifact %s has an invalid property dictionary. Should not be a %s""", (spec, type(properties))]
        unsupported_keys = _unsupported_keys(properties.keys())
        if bool(unsupported_keys):
            errors += ["""Artifact %s has unsupported property keys: %s. Only %s are supported""" % (
                spec,
                list(unsupported_keys),
                list(artifact_config_properties.values),
            )]
        artifact = artifacts.parse_spec(spec)  # Basic sanity check.
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

# Pre-process the artifact_declarations dictionary and handle older APIs that are now deprecated, until we
# delete them.
def _handle_legacy_specifications(artifact_declarations, insecure_artifacts, build_snippets):
    # Legacy deprecated feature backwards compatibility
    for spec in insecure_artifacts:
        print(_INSECURE_DEPRECATION_WARNING % spec)
        artifact_declarations += {spec: {"insecure": "true"}}
    for key in artifact_declarations.keys():
        value = artifact_declarations[key]
        if type(value) == type(""):
            print(_STRING_SHA_VALUE_DEPRECATION_WARNING % (key, value))
            artifact_declarations[key] = {artifact_config_properties.SHA256: value}

    # map versioned artifacts to versionless
    versionless_mapping = {}
    for key in artifact_declarations:
        artifact = artifacts.parse_spec(key)
        versionless_mapping["%s:%s" % (artifact.group_id, artifact.artifact_id)] = key
    for key, snippet in build_snippets.items():
        versioned_key = versionless_mapping.get(key)
        if not bool(versioned_key):
            fail("Artifact %s listed in build_substitutions not present in main artifact list.", key)
        config = artifact_declarations[versioned_key]
        config[artifact_config_properties.BUILD_SNIPPET] = snippet
        print(_LEGACY_BUILD_SUBSTITUTIONS_DEPRECATION_WARNING % versioned_key)
    return artifact_declarations

# The implementation of maven_repository_specification.
#
# Validates that all artifacts have sha hashes (or are in insecure_artifacts), splits artifacts into groups based on
# their groupId, generates a fetch rule for each artifact, and calls the rule which generates the internal bazel
# repository which replicates the maven repo structure.
#
def _maven_repository_specification(
        name,
        artifact_declarations = {},
        insecure_artifacts = [],
        build_substitutes = {},
        dependency_target_substitutes = {},
        repository_urls = ["https://repo1.maven.org/maven2"],
        cache_poms_insecurely = False,
        insecure_cache = None):
    _handle_legacy_specifications(artifact_declarations, insecure_artifacts, build_substitutes)

    if len(repository_urls) == 0:
        fail("You must specify at least one repository root url.")
    if len(artifact_declarations) == 0:
        fail("You must register at least one artifact.")

    _validate_artifacts(artifact_declarations)

    _check_for_duplicates(artifact_declarations)
    grouped_artifacts = {}
    build_snippets = {}
    pom_sha256_hashes = {}
    for artifact_spec, properties in artifact_declarations.items():
        artifact = artifacts.annotate(artifacts.parse_spec(artifact_spec))

        # Track group_ids in order to build per-group BUILD.bazel files.
        grouped_artifacts[artifact.group_id] = (
            grouped_artifacts.get(artifact.group_id, default = []) + [artifact.original_spec]
        )
        sha256 = properties.get(artifact_config_properties.SHA256)
        urls = ["%s/%s" % (repo, artifact.path) for repo in repository_urls]
        _fetch_artifact(
            name = artifact.maven_target_name,
            urls = urls,
            local_path = artifact.path,
            sha256 = sha256,
        )
        snippet = properties.get(artifact_config_properties.BUILD_SNIPPET)
        if bool(snippet):
            build_snippets["%s:%s" % (artifact.group_id, artifact.artifact_id)] = snippet

        pom_sha256_hash = properties.get(artifact_config_properties.POM_SHA256)
        if bool(pom_sha256_hash):
            pom_sha256_hashes[artifact_spec] = pom_sha256_hash

    # Skylark rules can't take in arbitrarily deep dicts, so we rewrite dict(string->dict(string, string)) to an
    # encoded (but trivially splittable) dict(string->list(string)).  Yes it's gross.
    dependency_target_substitutes_rewritten = dicts.encode_nested(dependency_target_substitutes)

    _generate_maven_repository(
        name = name,
        grouped_artifacts = grouped_artifacts,
        repository_urls = repository_urls,
        dependency_target_substitutes = dependency_target_substitutes_rewritten,
        build_snippets = build_snippets,
        cache_poms_insecurely = cache_poms_insecurely,
        insecure_cache = insecure_cache,
        pom_sha256_hashes = pom_sha256_hashes,
    )

for_testing = struct(
    unsupported_keys = _unsupported_keys,
    handle_legacy_specifications = _handle_legacy_specifications,
    fetch_pom = _fetch_pom,
    get_pom_sha256 = _get_pom_sha256,
    get_inheritance_chain = _get_inheritance_chain,
    get_effective_pom = _get_effective_pom,
)

####################
# PUBLIC FUNCTIONS #
####################

# Creates java or android library targets from maven_hosted .jar/.aar files.
def maven_jvm_artifact(artifact, name = None, deps = [], visibility = ["//visibility:public"], **kwargs):
    # redirect to _maven_jvm_artifact, so we can externally use the name "artifact" but internally use artifact_spec
    _maven_jvm_artifact(artifact_spec = artifact, name = name, deps = deps, visibility = visibility, **kwargs)

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

        # If True, then cache poms based on the sha256 of the first downloaded occurrance.
        cache_poms_insecurely = False,

        # Supply a cache directory (relative to $HOME of the current user, or absolute) into which
        # to cache the pom file hashes, which will enable them to participate in the content-
        # addressable cache.  By default they are not cached locally unless pom_sha256 is supplied
        # for that artifact.
        insecure_cache = ".cache/bazel_maven_repository/hashes"):
    # Redirected to _maven_repository_specification to allow the public parameter "artifacts" without conflicting
    # with the artifact utility struct.
    _maven_repository_specification(
        name = name,
        artifact_declarations = artifacts,
        insecure_artifacts = insecure_artifacts,
        build_substitutes = build_substitutes,
        dependency_target_substitutes = dependency_target_substitutes,
        repository_urls = repository_urls,
        cache_poms_insecurely = cache_poms_insecurely,
        insecure_cache = insecure_cache,
    )
