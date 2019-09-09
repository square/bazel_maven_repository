#
# Description:
#   Utilities and rules concerning the actual fetch of artifacts and sub-artifacts and metadata.
#
load(":artifacts.bzl", "artifacts")
load(":globals.bzl", "DOWNLOAD_PREFIX", "PACKAGING_TYPE_FILE", "fetch_repo")
load(":packaging_type.bzl", "packaging_type")
load(":poms.bzl", "poms")
load(":utils.bzl", "strings")
load(":xml.bzl", "xml")

# Maximum number of parents that this code will search before quiting. This is an insane value, but
# must be set, as starlark has no while() loop equivalent.
_MAX_HIERARCHY_DEPTH = 1000

_ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE = """
package(default_visibility = ["//visibility:public"])
exports_files([
{files}])
"""

_POM_HASH_INFIX = "sha256"

_POM_HASH_CACHE_WRITE_SCRIPT = "bin/pom_hash_cache_write.sh"

#TODO(cgruber) move this into a toolchain (and make a windows equivalent)
_POM_HASH_CACHE_WRITE_SCRIPT_CONTENT = """#!/bin/sh
content="$1"
cache_file="$2"
mkdir -p $(dirname "${cache_file}")
echo "${content}" > ${cache_file}
"""

def _format_exported_files(paths):
    return "".join(["    \"%s\",\n" % path for path in paths])

# Obtain the _pom fetch workspace, and collect the precomupted maven packaging type from a known file therein.
def _get_packaging_type(ctx, pom_label):
    packaging_type_file = pom_label.relative(":%s" % PACKAGING_TYPE_FILE)
    path = ctx.path(packaging_type_file)
    return strings.trim(ctx.read(path))

# Downloads an artifact and exports it into the build language.
def _fetch_artifact_impl(ctx):
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))
    artifact = artifacts.parse_spec(ctx.attr.artifact)
    packaging = packaging_type.value_of(_get_packaging_type(ctx, ctx.attr.pom))
    path = fetch_repo.artifact_path(artifact, packaging.suffix)
    urls = ["%s/%s" % (repo, path) for repo in ctx.attr.repository_urls]
    local_path = "%s/%s" % (DOWNLOAD_PREFIX, path)
    ctx.file(
        "%s/BUILD.bazel" % DOWNLOAD_PREFIX,
        _ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE.format(files = _format_exported_files([path])),
    )
    ctx.download(url = urls, output = local_path, sha256 = ctx.attr.sha256)

fetch_artifact = repository_rule(
    implementation = _fetch_artifact_impl,
    attrs = {
        "artifact": attr.string(),
        "sha256": attr.string(),
        "repository_urls": attr.string_list(),
        "pom": attr.label(),
    },
)
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

    explicit_hash = ctx.attr.pom_hashes.get(artifact.original_spec)
    if bool(explicit_hash):
        return explicit_hash

    if not ctx.attr.cache_poms_insecurely:
        return None

    # Fetch from the cache.
    if ctx.attr.insecure_cache.startswith("/"):
        cache_dir = "%s/%s" % (ctx.attr.insecure_cache, _POM_HASH_INFIX)
    else:
        cache_dir = "%s/%s/%s" % (ctx.os.environ["HOME"], ctx.attr.insecure_cache, _POM_HASH_INFIX)
    cached_file = ctx.path("%s/%s.sha256" % (cache_dir, file))

    if not cached_file.exists:
        # This will result in a CA cache miss and an extra download on first use, since the first
        # (non-sha-attributed) download won't store anything in the CA cache.
        ctx.report_progress("%s not locally cached, fetching and hashing" % cached_file)
        pom_result = ctx.download(url = urls, output = file)
        result = ctx.execute([_POM_HASH_CACHE_WRITE_SCRIPT, pom_result.sha256, cached_file])
        if result.return_code != 0:
            fail("Cache write failed with code %s, stderr: %s", (result.return_code, result.stderr))
        return pom_result.sha256
    else:
        return strings.trim(ctx.read(cached_file))

# Fetch the pom for the artifact.  First see if a cached hash is available for it. If so, use
# that hash to try a download with the sha, to get a hit on the content addressable cache. If not
# fetch normally and write that hash to the pom hash cache for next time.
def _fetch_and_read_pom(ctx, artifact):
    path = fetch_repo.pom_path(artifact)
    local_path = "%s/%s" % (DOWNLOAD_PREFIX, path)
    ctx.report_progress("Fetching %s" % path)
    urls = ["%s/%s" % (repo, path) for repo in ctx.attr.repository_urls]
    sha256 = _get_pom_sha256(ctx, artifact, urls, path)
    if sha256:
        ctx.download(url = urls, sha256 = sha256, output = local_path)
    else:
        ctx.download(url = urls, output = local_path)
    return ctx.read(local_path)

def _fetch_pom_impl(ctx):
    ctx.file(
        _POM_HASH_CACHE_WRITE_SCRIPT,
        content = _POM_HASH_CACHE_WRITE_SCRIPT_CONTENT,
        executable = True,
    )
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))

    # Fetch this pom and its parent poms.
    paths = [PACKAGING_TYPE_FILE]
    packaging_type = None
    current = artifacts.parse_spec(ctx.attr.artifact)
    for count in range(_MAX_HIERARCHY_DEPTH):
        if not bool(current):
            break
        xml_text = _fetch_and_read_pom(ctx, current)
        paths.append(fetch_repo.pom_path(current))
        project = poms.parse(xml_text)
        if count == 0:
            packaging_type = poms.extract_packaging(project)
        current = poms.extract_parent(project)
    if not bool(packaging_type):
        fail("Could not determine packaging type from root pom for %s" % ctx.attr.artifact)
    ctx.file("%s/%s" % (DOWNLOAD_PREFIX, PACKAGING_TYPE_FILE), packaging_type)

    ctx.file(
        "%s/BUILD.bazel" % DOWNLOAD_PREFIX,
        _ARTIFACT_DOWNLOAD_BUILD_FILE_TEMPLATE.format(files = _format_exported_files(paths)),
    )

fetch_pom = repository_rule(
    implementation = _fetch_pom_impl,
    attrs = {
        "artifact": attr.string(),
        "pom_hashes": attr.string_dict(),
        "repository_urls": attr.string_list(),
        "cache_poms_insecurely": attr.bool(),
        "insecure_cache": attr.string(mandatory = False),
    },
)

for_testing = struct(
    fetch_and_read_pom = _fetch_and_read_pom,
    get_pom_sha256 = _get_pom_sha256,
)