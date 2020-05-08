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
load(":fetch.bzl", "DOWNLOAD_PREFIX", "fetch_artifact")
load(":sets.bzl", "sets")
load(":utils.bzl", "exec")
load(
    ":jetifier.bzl",
    "DEFAULT_JETIFIER_EXCLUDED_ARTIFACTS",
    "jetifier_init",
)

#enum
artifact_config_properties = struct(
    SHA256 = "sha256",
    INSECURE = "insecure",
    BUILD_SNIPPET = "build_snippet",
    TESTONLY = "testonly",
    EXCLUDE = "exclude",
    values = ["sha256", "insecure", "build_snippet", "testonly", "exclude"],
)

def _generate_maven_repository_impl(ctx):
    workspace_root = ctx.path(".")
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))
    config_json = ctx.path("config.json")
    ctx.file(config_json, "%s" % ctx.attr.config)
    args = [
        exec.java_bin(ctx),
        "-jar",
        exec.exec_jar(workspace_root, ctx.attr._kramer_exec),
    ]
    for repo, url in ctx.attr.repository_urls.items():
        args.append("--repository=%s|%s" % (repo, url))
    args.append("gen-maven-repo")
    args.append("--threads=100")
    args.append("--workspace=%s" % workspace_root)
    args.append("--configuration=%s" % config_json)
    ctx.report_progress("Preparing maven repository")
    result = ctx.execute(args, timeout = 600, quiet = False)
    if result.return_code != 0:
        fail("Could not generate workspace - kramer returned exit code %s: %s%s" % (
            result.return_code,
            result.stderr,
            result.stdout,
        ))

_generate_maven_repository = repository_rule(
    implementation = _generate_maven_repository_impl,
    attrs = {
        "repository_urls": attr.string_dict(mandatory = True),
        "config": attr.string(mandatory = True),
        "maven_rules_repository": attr.string(mandatory = False, default = "maven_repository_rules"),
        "_kramer_exec": attr.label(
            executable = True,
            cfg = "host",
            default = Label("//maven:kramer-resolve.jar"),
            allow_single_file = True,
        ),
    },
)

# Legacy implementation of the maven_jvm_artifact rule (for snippet use only)
def _maven_jvm_artifact(coordinates, name, visibility, deps = [], use_jetifier = False, **kwargs):
    print("WARNING: maven_jvm_artifact is deprecated, please use raw_jvm_import")
    artifact = artifacts.annotate(artifacts.parse_spec(coordinates))
    file_target = "@%s//%s:%s" % (artifact.maven_target_name, DOWNLOAD_PREFIX, artifact.path)
    import_target = artifact.maven_target_name + "_import"
    target_name = name if name else artifact.third_party_target_name
    coordinate = "%s:%s" % (artifact.group_id, artifact.artifact_id)

    raw_jvm_import(
        name = target_name,
        deps = deps,
        visibility = visibility,
        jar = file_target,
        jetify = use_jetifier,
        **kwargs
    )

def _unsupported_keys(keys_list):
    return sets.difference(sets.copy_of(artifact_config_properties.values), sets.copy_of(keys_list))

def _fix_string_booleans(value):
    if type(value) == type(""):
        return value.lower() == "true"
    return bool(value)

# If artifact/sha pair has missing sha hashes, reject it.
def _validate_artifacts(artifact_definitions):
    errors = []
    if not bool(artifact_definitions):
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
        if artifact.version.endswith("-SNAPSHOT"):
            errors += ["""Snapshot versions not supported: "%s" """ % spec]
        if (not properties.get(artifact_config_properties.SHA256, None) and
            not _fix_string_booleans(properties.get(artifact_config_properties.INSECURE, False))):
            errors += ["""Artifact "%s" is missing a sha256. Either supply it or mark it "insecure".""" % spec]
        if (properties.get(artifact_config_properties.SHA256, None) and
            _fix_string_booleans(properties.get(artifact_config_properties.INSECURE, False))):
            errors += ["""Artifact "%s" cannot be both insecure and have a sha256.  Specify one or the other.""" % spec]
    if bool(errors):
        fail("Errors found:\n    %s" % "\n    ".join(errors))

# The implementation of maven_repository_specification.
#
# Validates that all artifacts have sha hashes (or are in insecure_artifacts), splits artifacts into groups based on
# their groupId, generates a fetch rule for each artifact, and calls the rule which generates the internal bazel
# repository which replicates the maven repo structure.
#
def _maven_repository_specification(
        name,
        use_jetifier,
        jetifier_excludes,
        legacy_underscore,
        artifact_declarations = {},
        insecure_artifacts = [],
        build_substitutes = {},
        dependency_target_substitutes = {},
        repository_urls = {"central": "https://repo1.maven.org/maven2"}):
    if len(repository_urls) == 0:
        fail("You must specify at least one repository root url.")
    if len(artifact_declarations) == 0:
        fail("You must register at least one artifact.")

    _validate_artifacts(artifact_declarations)

    for artifact_spec, properties in artifact_declarations.items():
        artifact = artifacts.annotate(artifacts.parse_spec(artifact_spec))
        sha256 = properties.get(artifact_config_properties.SHA256, None)
        fetch_artifact(
            name = artifact.maven_target_name,
            # Don't use the spec, because it may have the type which we shouldn't have.
            artifact = artifact.original_spec,
            sha256 = sha256,
            repository_urls = repository_urls,
        )

    config = struct(
        name = name,
        target_substitutes = dependency_target_substitutes,
        use_jetifier = use_jetifier,
        jetifier_excludes = jetifier_excludes if use_jetifier else [],
        maven_rules_repository = "maven_repository_rules",
        artifacts = artifact_declarations,
    )
    _generate_maven_repository(
        name = name,
        config = config.to_json(),
        repository_urls = repository_urls,
    )

####################
# PUBLIC FUNCTIONS #
####################

# Creates java or android library targets from maven_hosted .jar/.aar files. This should only
# be used in build_snippets, as it is no longer the solution the underlying code generates.
def maven_jvm_artifact(artifact, name = None, deps = [], visibility = ["//visibility:public"], **kwargs):
    # redirect to _maven_jvm_artifact, so we can externally use the name "artifact" but internally use artifact_spec
    _maven_jvm_artifact(coordinates = artifact, name = name, deps = deps, visibility = visibility, **kwargs)

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
        legacy_underscore = False,

        # The dictionary of build-file substitutions (per-target) which will replace the auto-generated target
        # statements in the generated repository
        build_substitutes = {},

        # The dictionary of per-group target substitutions.  These must be in the format:
        # "@myreponame//path/to/package:target": "@myrepotarget//path/to/package:alternate"
        dependency_target_substitutes = {},

        # Activate jetifier on maven artifacts, except where excluded
        use_jetifier = False,

        # A list of artifacts to be excluded from jetifier processing, in the form "group:artifact"
        # Note this is an exact group/artifact match. Future versions may support wildcards.
        jetifier_excludes = DEFAULT_JETIFIER_EXCLUDED_ARTIFACTS,

        # Optional list of repositories which the build rule will attempt to fetch maven artifacts and metadata.
        repository_urls = ["https://repo1.maven.org/maven2"]):
    # Define repository rule for the jetifier tooling. It may end up unused, but the repo needs to
    # be defined.
    jetifier_init()

    # Redirected to _maven_repository_specification to allow the public parameter "artifacts" without conflicting
    # with the artifact utility struct.
    _maven_repository_specification(
        name = name,
        artifact_declarations = artifacts,
        insecure_artifacts = insecure_artifacts,
        legacy_underscore = legacy_underscore,
        build_substitutes = build_substitutes,
        dependency_target_substitutes = dependency_target_substitutes,
        use_jetifier = use_jetifier,
        repository_urls = repository_urls,
        jetifier_excludes = jetifier_excludes,
    )
