load(":constants.bzl", "DOWNLOAD_PREFIX")

_ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE = """
package(default_visibility = ["//visibility:public"])
exports_files([
    "{path}",
])
"""

# Validate that the path being fetched isn't a bazel-critical file we need to write.
def _validate_path(ctx, path):
    forbidden = [
        ctx.path("."),
        ctx.path("WORKSPACE"),
        ctx.path("BUILD"),
        ctx.path("BUILD.bazel"),
        ctx.path("%s/BUILD" % DOWNLOAD_PREFIX),
        ctx.path("%s/BUILD.bazel" % DOWNLOAD_PREFIX),
    ]
    if path in forbidden or not str(path).startswith(str(ctx.path("."))):
        fail("Invalid local_path: %s" % ctx.attr.local_path)
    return path

# Downloads an artifact and exports it into the build language.
# TODO: consume an artifact spec and a metadata file label, and infer information like path and file extension.
def _fetch_artifact_impl(ctx):
    local_path = "%s/%s" % (DOWNLOAD_PREFIX, ctx.attr.local_path)
    download_path = _validate_path(ctx, ctx.path(local_path))
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))
    ctx.file(
        "%s/BUILD.bazel" % DOWNLOAD_PREFIX,
        _ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE.format(prefix = DOWNLOAD_PREFIX, path = ctx.attr.local_path),
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

fetch = struct(
    artifact = _fetch_artifact,
)