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
load(":jvm.bzl", "raw_jvm_import")
load(":fetch.bzl", "fetch_artifact")
load(":sets.bzl", "sets")
load(":exec.bzl", "exec")
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
    threads = ctx.os.environ.get("BAZEL_MAVEN_FETCH_THREADS", "%s" % ctx.attr.fetch_threads)
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
    args.append("--threads=%s" % threads)
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
        "fetch_threads": attr.int(mandatory = True),
        "maven_rules_repository": attr.string(mandatory = False, default = "maven_repository_rules"),
        "_kramer_exec": attr.label(
            executable = True,
            cfg = "host",
            default = Label("//maven:kramer-resolve.jar"),
            allow_single_file = True,
        ),
    },
)

def _unsupported_keys(keys_list):
    return sets.difference(sets.copy_of(artifact_config_properties.values), sets.copy_of(keys_list))

def _fix_string_booleans(value):
    if type(value) == type(""):
        return value.lower() == "true"
    return bool(value)

# Validate artifact configurations.
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
        artifact = artifact_utils.parse_spec(spec)  # Basic sanity check.

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
        if (properties.get(artifact_config_properties.BUILD_SNIPPET, None) and
            properties.get(artifact_config_properties.EXCLUDE)):
            errors += ["""Artifact "%s" cannot both have a build snippet and declare an exclusion list.""" % spec]

    if bool(errors):
        fail("Errors found:\n    %s" % "\n    ".join(errors))

####################
# PUBLIC FUNCTIONS #
####################

# Creates java or android library targets from maven_hosted .jar/.aar files. This should only
# be used in build_snippets, as it is no longer the solution that the underlying code generates.
# All raw_jvm_import properties are passed through.
#
# For rare cases where the packaging isn't jar, use packaging=. e.g. Guava, which is a "bundle"
def maven_jvm_artifact(artifact, packaging = "jar", visibility = ["//visibility:public"], **kwargs):
    print("WARNING: maven_jvm_artifact is deprecated, please use raw_jvm_import")
    artifact_struct = artifact_utils.parse_spec(artifact)
    dir = "{group_path}/{artifact_id}/{version}".format(
        group_path = artifact_struct.group_id.replace(".", "/"),
        artifact_id = artifact_struct.artifact_id,
        version = artifact_struct.version,
    )
    path = "{dir}/maven-{packaging}-{artifact_id}-{version}-classes.{suffix}".format(
        dir = dir,
        packaging = packaging,
        artifact_id = artifact_struct.artifact_id,
        version = artifact_struct.version,
        suffix = "jar",
    )
    file_target = "@%s//%s:%s" % (artifact_utils.fetch_repo(artifact_struct), "maven", path)
    raw_jvm_import(
        visibility = visibility,
        jar = file_target,
        **kwargs
    )

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

        # Activate jetifier on maven artifacts, except where excluded
        use_jetifier = False,

        # A list of artifacts to be excluded from jetifier processing, in the form "group:artifact"
        # Note this is an exact group/artifact match. Future versions may support wildcards.
        jetifier_excludes = DEFAULT_JETIFIER_EXCLUDED_ARTIFACTS,

        # If use_jetifier = True the tool will reject legacy android support artifacts in the
        # artifact list. During migrations, this setting can cause it to simply ignore them. If
        # an androidx artifact ought to be there, it will still error, but the mere presence of
        # an older artifact will not trigger an error.
        ignore_legacy_android_support_artifacts = False,

        # Optional list of repositories which the build rule will attempt to fetch maven artifacts and metadata.
        repository_urls = {"central": "https://repo1.maven.org/maven2"},

        # Optional number of threads to use while fetching and generating build targets for maven artifacts.
        fetch_threads = 100):
    # Define repository rule for the jetifier tooling. It may end up unused, but the repo needs to
    # be defined.
    jetifier_init()

    if len(repository_urls) == 0:
        fail("You must specify at least one repository root url.")
    if len(artifacts) == 0:
        fail("You must register at least one artifact.")

    _validate_artifacts(artifacts)

    for artifact_spec, properties in artifacts.items():
        artifact_struct = artifact_utils.parse_spec(artifact_spec)
        sha256 = properties.get(artifact_config_properties.SHA256, None)
        fetch_artifact(
            name = artifact_utils.fetch_repo(artifact_struct),
            # Don't use the un-parsed spec, because it may have the type which we shouldn't have.
            artifact = artifact_struct.original_spec,
            sha256 = sha256,
            repository_urls = repository_urls,
        )

    config = struct(
        name = name,
        target_substitutes = dependency_target_substitutes,
        use_jetifier = use_jetifier,
        jetifier_excludes = jetifier_excludes if use_jetifier else [],
        ignore_legacy_android_support_artifacts = ignore_legacy_android_support_artifacts,
        maven_rules_repository = "maven_repository_rules",
        artifacts = artifacts,
    )

    _generate_maven_repository(
        name = name,
        config = config.to_json(),
        repository_urls = repository_urls,
        fetch_threads = fetch_threads,
    )
