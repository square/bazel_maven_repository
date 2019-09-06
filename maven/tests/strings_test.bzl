load(":testing.bzl", "asserts", "test_suite")
load("//maven:utils.bzl", "strings")

def trim_test_default(env):
    asserts.equals(env, "foo", strings.trim("   \n foo \n"))

def trim_test_custom(env):
    asserts.equals(env, "foo", strings.trim(" aaa fooa \n", "\n a"))

def contains_test(env):
    asserts.true(env, strings.contains("foobarbash", "bar"))
    asserts.false(env, strings.contains("foobarbash", "Bar"))

def munge_test(env):
    asserts.equals(env, "foo", strings.munge("foo", ".", "-"))
    asserts.equals(env, "f_o-o", strings.munge("f.o-o", "."))
    asserts.equals(env, "f.o_o", strings.munge("f.o-o", "-"))
    asserts.equals(env, "f_o_o", strings.munge("f.o-o", ".", "-"))
    asserts.equals(env, "f_o_o", strings.munge("f.o-o", "-", "."))

# Roll-up function.
def suite():
    return test_suite("strings", tests = [trim_test_custom, trim_test_default, contains_test, munge_test])
