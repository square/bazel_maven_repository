load(":testing.bzl", "asserts", "test_suite")
load("//maven:utils.bzl", "paths")

def filename_test(env):
    asserts.equals(env, "blah", paths.filename("//foo/bar/blah"))
    asserts.equals(env, "blah", paths.filename("bar/blah"))
    asserts.equals(env, "blah", paths.filename("/bar/blah"))
    asserts.equals(env, "blah", paths.filename("../bar/blah"))
    asserts.equals(env, "blah", paths.filename("@maven//bar/blah"))

# Roll-up function.
def paths_test_suite():
    test_suite("paths", tests = [filename_test]
