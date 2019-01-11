load(":testing.bzl", "asserts", "test_suite")
load("//maven:utils.bzl", "dicts")

def encode_test(env):
    nested = {
        "foo": "bar",
        "blah": {
            "a": "b",
            "c": "d",
        }
    }

    expected = {
        "foo": "bar",
        "blah": ["a>>>b", "c>>>d"],
    }
    asserts.equals(env, expected, dicts.encode_nested(nested))

# Roll-up function.
def dicts_test_suite():
    test_suite("dicts", tests = [encode_test])