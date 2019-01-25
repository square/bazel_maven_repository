load(":testing.bzl", "asserts", "test_suite")
load("//maven:maven.bzl", "for_testing")
load("//maven:sets.bzl", "sets")

def unsupported_keys_test(env):
    asserts.equals(env, sets.new("foo", "bar"), for_testing.unsupported_keys(["foo", "sha256", "insecure", "bar"]))

def handle_legacy_sha_handling(env):
    asserts.equals(env,
        expected = {"foo:bar:1.0": { "sha256": "abcdef"}},
        actual = for_testing.handle_legacy_specifications({"foo:bar:1.0": "abcdef"}, []))

# Roll-up function.
def suite():
    return test_suite("maven processing", tests = [unsupported_keys_test, handle_legacy_sha_handling])
