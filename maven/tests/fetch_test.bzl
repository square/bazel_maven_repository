load(":poms_for_testing.bzl", "COMPLEX_POM", "GRANDPARENT_POM", "PARENT_POM")
load(":testing.bzl", "asserts", "test_suite")
load("//maven:artifacts.bzl", "artifacts")
load("//maven:fetch.bzl", "for_testing")
load("//maven:poms.bzl", "poms")
load("//maven:sets.bzl", "sets")
load("//maven:xml.bzl", "xml")

_FAKE_URL_PREFIX = "fake://maven"
_FAKE_DOWNLOAD_PREFIX = "maven"

# Set up fakes.
def _fake_read_for_fetch_and_read_pom_test(path):
    return COMPLEX_POM

def _noop_download(url, output):
    pass

def _noop_report_progress(string):
    pass

# This test is way way too mock-ish, but I definitely wanted to stage a test around the method itself, since I'm
# restructuring large chunks of the code.  All it does is make sure the download and execute commands are done
# as expected, to return pom text.
def fetch_and_read_pom_test(env):
    fake_ctx = struct(
        download = _noop_download,
        read = _fake_read_for_fetch_and_read_pom_test,
        attr = struct(
            repository_urls = [_FAKE_URL_PREFIX],
            cache_poms_insecurely = False,
            pom_hashes = {},
        ),
        report_progress = _noop_report_progress,
    )
    project = poms.parse(
        for_testing.fetch_and_read_pom(fake_ctx, artifacts.parse_spec("test.group:child:1.0")),
    )
    asserts.equals(env, "project", project.label)

def _fake_read_for_cache_hit_test(path):
    return  "\n1234567812345678123456781234567812345678123456781234567812345678 \n"

def _fake_path(string):
    return struct(exists = True)

def get_pom_sha256_cache_hit_test(env):
    fake_ctx = struct(
        download = _noop_download,
        read = _fake_read_for_cache_hit_test,
        attr = struct(
            cache_poms_insecurely = True,
            insecure_cache = "/tmp/blah",
            pom_hashes = {},
        ),
        report_progress = _noop_report_progress,
        path = _fake_path,
    )
    artifact = artifacts.parse_spec("test.group:child:1.0")
    urls = ["fake://somerepo/test/group/child/1.0/child-1.0.pom"]
    file = "test/group/child-1.0.pom"
    sha256 = for_testing.get_pom_sha256(fake_ctx, artifact, urls, file)
    asserts.equals(env, "1234567812345678123456781234567812345678123456781234567812345678", sha256)

def _fake_download_for_cache_miss_test(url, output):
    return struct(sha256 = "1234567812345678123456781234567812345678123456781234567812345678")

def _fake_execute_for_cache_miss_test(args):
    if args[0] == "bin/pom_hash_cache_write.sh":
        if (args[1] == "1234567812345678123456781234567812345678123456781234567812345678" and
            args[2] == "/tmp/blah/sha256/test/group/child-1.0.pom.sha256"):
            return struct(return_code = 0)
    fail("Unexpected Execution %s" % args)

def get_pom_sha256_cache_miss_test(env):
    fake_ctx = struct(
        download = _fake_download_for_cache_miss_test,
        read = _fake_read_for_cache_hit_test,
        attr = struct(
            cache_poms_insecurely = True,
            insecure_cache = "/tmp/blah",
            pom_hashes = {},
        ),
        report_progress = _noop_report_progress,
        execute = _fake_execute_for_cache_miss_test,
        path = _fake_path,
    )
    artifact = artifacts.parse_spec("test.group:child:1.0")
    urls = ["fake://somerepo/test/group/child/1.0/child-1.0.pom"]
    file = "test/group/child-1.0.pom"
    sha256 = for_testing.get_pom_sha256(fake_ctx, artifact, urls, file)
    asserts.equals(env, "1234567812345678123456781234567812345678123456781234567812345678", sha256)

def get_pom_sha256_predefined_test(env):
    fake_ctx = struct(
        download = _fake_download_for_cache_miss_test,
        read = _fake_read_for_fetch_and_read_pom_test,
        attr = struct(
            insecure_cache = "/tmp/blah",
            pom_hashes = {"test.group:child:1.0": "1234567812345678123456781234567812345678123456781234567812345678"},
        ),
        report_progress = _noop_report_progress,
    )
    artifact = artifacts.parse_spec("test.group:child:1.0")
    sha256 = for_testing.get_pom_sha256(fake_ctx, artifact, None, None)
    asserts.equals(env, "1234567812345678123456781234567812345678123456781234567812345678", sha256)

# Roll-up function.
def suite():
    return test_suite(
        "fetching",
        tests = [
            fetch_and_read_pom_test,
            get_pom_sha256_cache_hit_test,
            get_pom_sha256_cache_miss_test,
            get_pom_sha256_predefined_test,
        ],
    )
