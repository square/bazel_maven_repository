load(":artifacts.bzl", "artifacts")
load(":utils.bzl", "exec")

DOWNLOAD_PREFIX = "maven"

_FORBIDDEN_FILES = [
    ".",
    "WORKSPACE",
    "BUILD",
    "BUILD.bazel",
    "%s/BUILD" % DOWNLOAD_PREFIX,
    "%s/BUILD.bazel" % DOWNLOAD_PREFIX,
]

_ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE = """
package(default_visibility = ["//visibility:public"])
filegroup(
    name = "{prefix}",
    srcs = ["{path}"],
)
"""

_AAR_DOWNLOAD_BUILD_FILE = """
package(default_visibility = ["//visibility:public"])
exports_files(["AndroidManifest.xml", "classes.jar"])

filegroup(
  name = "resources",
  srcs = glob(["res/**/*"])
)

filegroup(
  name = "assets",
  srcs = glob(["assets/**/*"])
)

filegroup(
  name = "proguard",
  srcs = glob(["proguard.txt"])
)

"""

def get_suffix(packaging):
    if packaging == "bundle":
        return "jar"
    return packaging

def _resolve_one(ctx, artifact):
    args = [
        exec.java_bin(ctx),
        "-jar",
        exec.exec_jar(ctx.path("."), ctx.attr._kramer_exec),
    ]
    for repo, url in ctx.attr.repository_urls.items():
        args.append("--repository=%s|%s" % (repo, url))
    args.append("resolve-one")
    args.append(artifact.original_spec)
    result = ctx.execute(args, timeout = 10, quiet = True)
    if result.return_code != 0:
        fail("Could not resolve %s - kramer returned exit code %s: %s%s" % (
            ctx.attr.artifact,
            result.return_code,
            result.stderr,
            result.stdout,
        ))
    return result.stdout

def _validate_download_path(ctx, download_path):
    for file in _FORBIDDEN_FILES:
        if ctx.path(file) == download_path:
            fail("Invalid local_path: %s" % download_path)
    if not str(download_path).startswith(str(ctx.path("."))):
        fail("Invalid local_path: %s" % ctx.attr.local_path)

def _fetch_artifact_impl(ctx):
    repository_root_path = ctx.path(".")
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))

    artifact = artifacts.parse_elements(ctx.attr.artifact.split(":")[0:3])  # Ignore old spec.
    resolved_spec = _resolve_one(ctx, artifact)
    packaging = resolved_spec.split("|")[1].strip()
    package_dir = artifacts.package_path(artifact)
    artifact_path = artifacts.artifact_path(artifact, get_suffix(packaging))
    download_path = ctx.path("%s/%s" % (DOWNLOAD_PREFIX, artifact_path))
    _validate_download_path(ctx, download_path)

    artifact_urls = ["%s/%s" % (repo, artifact_path) for repo in ctx.attr.repository_urls.values()]
    if packaging == "aar":
        ctx.file("%s/BUILD.bazel" % DOWNLOAD_PREFIX, _AAR_DOWNLOAD_BUILD_FILE)
        ctx.download_and_extract(
            url = artifact_urls,
            output = DOWNLOAD_PREFIX,
            sha256 = ctx.attr.sha256,
            type = "zip",
        )
    else:
        ctx.file(
            "%s/BUILD.bazel" % DOWNLOAD_PREFIX,
            _ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE.format(
                prefix = DOWNLOAD_PREFIX,
                path = artifact_path,
            ),
        )
        ctx.download(url = artifact_urls, output = download_path, sha256 = ctx.attr.sha256)

fetch_artifact = repository_rule(
    implementation = _fetch_artifact_impl,
    attrs = {
        "artifact": attr.string(mandatory = True),
        "sha256": attr.string(),
        "repository_urls": attr.string_dict(mandatory = True),
        "_kramer_exec": attr.label(
            executable = True,
            cfg = "host",
            default = Label("//maven:kramer-resolve.jar"),
            allow_single_file = True,
        ),
    },
)
