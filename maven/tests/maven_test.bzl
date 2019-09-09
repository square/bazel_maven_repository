load(":poms_for_testing.bzl", "COMPLEX_POM", "GRANDPARENT_POM", "PARENT_POM")
load(":testing.bzl", "asserts", "test_suite")
load("//maven:artifacts.bzl", "artifacts")
load("//maven:maven.bzl", "for_testing")
load("//maven:poms.bzl", "poms", poms_testing = "for_testing")
load("//maven:sets.bzl", "sets")
load("//maven:xml.bzl", "xml")

_FAKE_URL_PREFIX = "fake://maven"
_FAKE_DOWNLOAD_PREFIX = "maven"

def unsupported_keys_test(env):
    asserts.equals(
        env,
        expected = sets.new("foo", "bar"),
        actual = for_testing.unsupported_keys(["build_snippet", "foo", "sha256", "insecure", "bar"]),
    )

def handle_legacy_sha_handling(env):
    asserts.equals(
        env,
        expected = {"foo:bar:1.0": {"sha256": "abcdef"}},
        actual = for_testing.handle_legacy_specifications({"foo:bar:1.0": "abcdef"}, [], {}),
    )

def handle_legacy_build_snippet_handling(env):
    asserts.equals(
        env,
        expected = {"foo:bar:1.0": {"sha256": "abcdef", "build_snippet": "blah"}},
        actual = for_testing.handle_legacy_specifications(
            {"foo:bar:1.0": {"sha256": "abcdef"}},
            [],
            {"foo:bar": "blah"},
        ),
    )

# Set up fakes.
def _fake_read_for_get_parent_chain(path):
    download_map = {
        "test/group/child/1.0/child-1.0.pom": COMPLEX_POM,
        "test/group/parent/1.0/parent-1.0.pom": PARENT_POM,
        "test/grandparent/1.0/grandparent-1.0.pom": GRANDPARENT_POM,
    }
    return download_map.get(path, None)

def _noop_download(url, output):
    pass

def _noop_report_progress(string):
    pass

def _pass_through_path(label):
    return label.name

def get_dependencies_from_project_test(env):
    fake_ctx = struct(
        download = _noop_download,
        read = _fake_read_for_get_parent_chain,
        attr = struct(repository_urls = [_FAKE_URL_PREFIX], cache_poms_insecurely = False),
        report_progress = _noop_report_progress,
        path = _pass_through_path,
    )
    artifact = artifacts.parse_spec("test.group:child:1.0")
    project = poms_testing.merge_inheritance_chain(poms_testing.get_inheritance_chain(fake_ctx, artifact))

    # confirm junit is present.  This is just a precondition assertion, testing the baseline deps mechanism
    dependencies = [d.coordinates for d in for_testing.get_dependencies_from_project(fake_ctx, [], project)]
    asserts.true(env, sets.contains(sets.copy_of(dependencies), "junit:junit"), "Should contain junit:junit")

    # confirm junit is excluded
    dependencies = [d.coordinates for d in for_testing.get_dependencies_from_project(fake_ctx, ["junit:junit"], project)]
    asserts.false(env, sets.contains(sets.copy_of(dependencies), "junit:junit"), "Should NOT contain junit:junit")

TESTS = [
    unsupported_keys_test,
    handle_legacy_sha_handling,
    handle_legacy_build_snippet_handling,
    get_dependencies_from_project_test,
]

# Roll-up function.
def suite():
    return test_suite("maven processing", tests = TESTS)
