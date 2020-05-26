load("@bazel_tools//tools/build_defs/repo:http.bzl", _http_archive = "http_archive")
load(":sets.bzl", "sets")

BUILD_FILE_CONTENT = """
java_import(
    name = "jetifier_standalone_jars",
    jars = glob(["lib/*.jar"]),
)
java_binary(
    main_class = "com.android.tools.build.jetifier.standalone.Main",
    name = "jetifier_standalone",
    runtime_deps = [
        ":jetifier_standalone_jars"
    ],
    visibility = ["//visibility:public"],
)
"""

def jetifier_init():
    _http_archive(
        sha256 = "8ef877e8245f8dcf8f379b2cdc4958ba714147eb8d559d8334a1840e137e5a2c",
        strip_prefix = "jetifier-standalone",
        name = "bazel_maven_repository_jetifier",
        url = "https://dl.google.com/dl/android/studio/jetifier-zips/1.0.0-beta08/jetifier-standalone.zip",
        build_file_content = BUILD_FILE_CONTENT,
    )

# _jetify_jar based on https://github.com/bazelbuild/tools_android/pull/5

def _jetify_jar(ctx, jar):
    jetified_outfile = ctx.actions.declare_file("%s-jetified.%s" % (ctx.attr.name, jar.extension))
    jetify_args = ctx.actions.args()
    jetify_args.add_all(["-l", "error"])
    jetify_args.add_all(["-o", jetified_outfile])
    jetify_args.add_all(["-i", jar])
    ctx.actions.run(
        mnemonic = "Jetify",
        inputs = [jar],
        outputs = [jetified_outfile],
        progress_message = "Jetifying {} to create {}.".format(jar.path, jetified_outfile.path),
        executable = ctx.executable._jetifier,
        arguments = [jetify_args],
        use_default_shell_env = True,
    )
    return jetified_outfile

# Literal and glob pattern matches for artifacts that should not have jetifier applied.
# These can be overridden in the main call using maven_repository_specification(jetifier_excludes=)
DEFAULT_JETIFIER_EXCLUDED_ARTIFACTS = [
    "javax.*:*",
    "*:jsr305",
    "*:javac-shaded",
    "*:google-java-format",
    "com.squareup:javapoet",
    "com.google.dagger:*",
    "org.bouncycastle*:*",
    "androidx*:*",
    "org.jetbrains.kotlin*:*",
    "com.android.tools:*",
    "com.android.tools.build:*",
]

def _prepare_jetifier_excludes(ctx):
    literal = []
    id_literal = []
    group_literal = []
    prefix_matches = []
    for exclude in ctx.attr.jetifier_excludes:
        (group_id, artifact_id) = exclude.split(":")
        if artifact_id != "*" and artifact_id.find("*") >= 0:
            fail((
                "Jetifier exclude %s may not include a partial wildcard in its artifact id. " +
                "An exclude artifact_id can only be a string literal or itself be a " +
                "wildcard. E.g.: \"foo:bar\", \"foo:*\". \"foo:ba*\" is not permitted."
            ) % exclude)
        group_wildcard_index = group_id.find("*")
        if group_id == "*":
            if artifact_id == "*":
                fail("*:* is not a valid exclusions match. Just set use_jetifier=False instead.")

            # e.g. "*:dagger"
            id_literal += [artifact_id]
        elif group_wildcard_index >= 0:
            if not group_id == "*" and not group_id.endswith("*"):
                fail((
                    "Jetifier exclude %s may not include a wildcard at the start or in the " +
                    "middle of the group_id. An exclude group_id can only be a string " +
                    "literal or itself be  a wildcard, or end with a wildcard. E.g.: " +
                    "\"foo.bar:baz\", \"foo.b*:baz\" or \"*:baz\". \"foo.b*r:baz\" is not " +
                    "permitted."
                ) % exclude)
            prefix_matches += [struct(
                prefix = group_id[0:group_wildcard_index],
                artifact_id = artifact_id,
            )]
        else:
            # group_id is a literal
            if artifact_id == "*":
                group_literal += [group_id]
            else:
                literal += [exclude]
    return struct(
        literal = sets.copy_of(literal),
        id_literal = sets.copy_of(id_literal),
        group_literal = sets.copy_of(group_literal),
        prefix_matches = prefix_matches,
    )

def _should_use_jetifier(coordinate, enabled, excludes):
    (group_id, artifact_id) = coordinate.split(":")
    should = (
        enabled and
        not sets.contains(excludes.literal, coordinate) and
        not sets.contains(excludes.group_literal, group_id) and
        not sets.contains(excludes.id_literal, artifact_id)
    )
    if should:  # why test more if it's already matched (i.e. already excluded)?
        for match in excludes.prefix_matches:
            if group_id.startswith(match.prefix):
                if match.artifact_id == "*" or match.artifact_id == artifact_id:
                    # Found a match, so we shouldn't do jetifier, so bail early.
                    should = False
                    break
    return should

jetify_utils = struct(
    jetify_jar = _jetify_jar,
    should_use_jetifier = _should_use_jetifier,
    prepare_jetifier_excludes = _prepare_jetifier_excludes,
)
