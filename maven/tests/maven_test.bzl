load(":poms_for_testing.bzl", "COMPLEX_POM", "PARENT_POM", "GRANDPARENT_POM")
load(":testing.bzl", "asserts", "test_suite")
load("//maven:artifacts.bzl", "artifacts")
load("//maven:maven.bzl", "for_testing")
load("//maven:poms.bzl", "poms")
load("//maven:sets.bzl", "sets")
load("//maven:xml.bzl", "xml")

_FAKE_URL_PREFIX = "fake://maven"
_FAKE_DOWNLOAD_PREFIX = "maven"

def unsupported_keys_test(env):
    asserts.equals(
        env,
        expected = sets.new("foo", "bar"),
        actual = for_testing.unsupported_keys(["build_snippet","foo", "sha256", "insecure", "bar"]))

def handle_legacy_sha_handling(env):
    asserts.equals(env,
        expected = {"foo:bar:1.0": { "sha256": "abcdef" }},
        actual = for_testing.handle_legacy_specifications({"foo:bar:1.0": "abcdef"}, [], {}))

def handle_legacy_build_snippet_handling(env):
    asserts.equals(env,
        expected = {"foo:bar:1.0": { "sha256": "abcdef", "build_snippet": "blah" }},
        actual = for_testing.handle_legacy_specifications(
            {"foo:bar:1.0": {"sha256": "abcdef"}}, [], {"foo:bar": "blah"}))

# Set up fakes.
def _fake_read_for_get_pom_test(path):
    return COMPLEX_POM

def _fake_download(url, output):
    pass

def _fake_log(string):
    pass

# This test is way way too mock-ish, but I definitely wanted to stage a test around the method itself, since I'm
# restructuring large chunks of the code.  All it does is make sure the download and execute commands are done
# as expected, to return pom text.
def get_pom_test(env):
    fake_ctx = struct(
        download = _fake_download,
        read = _fake_read_for_get_pom_test,
        attr = struct(repository_urls = [_FAKE_URL_PREFIX], insecure_pom_cache = None),
        report_progress = _fake_log,
    )
    project = poms.parse(
        for_testing.fetch_pom(fake_ctx, artifacts.annotate(artifacts.parse_spec("test.group:child:1.0"))))
    asserts.equals(env, "project", project.label)


# Set up fakes.
def _fake_read_for_get_parent_chain(path):
    download_map = {
        "test/group/parent-1.0.pom": PARENT_POM,
        "test/grandparent-1.0.pom": GRANDPARENT_POM,
    }
    return download_map.get(path, "")

def _extract_artifact_id(node):
    for child_node in node.children:
        if child_node.label == "artifactId":
            return child_node.content

def get_parent_chain_test(env):
    fake_ctx = struct(
        download = _fake_download,
        read = _fake_read_for_get_parent_chain,
        attr = struct(repository_urls = [_FAKE_URL_PREFIX], insecure_pom_cache = None),
        report_progress = _fake_log,
    )
    chain = for_testing.get_inheritance_chain(fake_ctx, COMPLEX_POM)
    asserts.equals(env, ["child", "parent", "grandparent"], [_extract_artifact_id(x) for x in chain])

def get_effective_pom_test(env):
    inheritance_chain = [poms.parse(COMPLEX_POM), poms.parse(PARENT_POM), poms.parse(GRANDPARENT_POM)]

    merged = for_testing.get_effective_pom(inheritance_chain)

    asserts.equals(env, "test.group", xml.find_first(merged, "groupId").content, "groupId")
    asserts.equals(env, "child", xml.find_first(merged, "artifactId").content, "artifactId")
    asserts.equals(env, "1.0", xml.find_first(merged, "version").content, "version")
    asserts.equals(env, "jar", xml.find_first(merged, "packaging").content, "packaging")

# Roll-up function.
def suite():
    return test_suite("maven processing", tests = [
        unsupported_keys_test,
        handle_legacy_sha_handling,
        handle_legacy_build_snippet_handling,
        get_pom_test,
        get_parent_chain_test,
        get_effective_pom_test,
    ],
)
