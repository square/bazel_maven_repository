load(":dicts_test.bzl", dicts = "dicts_test_suite")
load(":paths_test.bzl", paths = "paths_test_suite")
load(":poms_test.bzl", poms = "poms_test_suite")
load(":sets_test.bzl", sets = "sets_test_suite")
load(":strings_test.bzl", strings = "strings_test_suite")

def _all_tests_rule_impl(ignore):
    for suite in [dicts, paths, poms, sets, strings]:
        suite()

all_tests = rule(
    implementation = _all_tests_rule_impl,
)
