load(":testing.bzl", "asserts", "test_suite")
load("//maven:utils.bzl", "strings")

def trim_test_default(env):
    asserts.equals(env, "foo", strings.trim("   \n foo \n"))

def trim_test_custom(env):
    asserts.equals(env, "foo", strings.trim(" aaa fooa \n", "\n a"))

def contains_test(env):
    asserts.true(env, strings.contains("foobarbash", "bar"))
    asserts.false(env, strings.contains("foobarbash", "Bar"))

# Roll-up function.
def suite():
    return test_suite("strings", tests = [trim_test_custom, trim_test_default, contains_test])
