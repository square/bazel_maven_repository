load(":dicts_test.bzl", dicts = "suite")
load(":fetch_test.bzl", fetch = "suite")
load(":globals_test.bzl", globals = "suite")
load(":paths_test.bzl", paths = "suite")
load(":maven_test.bzl", maven = "suite")
load(":poms_test.bzl", poms = "suite")
load(":poms_merging_test.bzl", poms_merging = "suite")
load(":sets_test.bzl", set_tests = "suite")
load(":strings_test.bzl", strings = "suite")
load(":xml_test.bzl", xml = "suite")

load("//maven:sets.bzl", "sets")

# Order by more fundamental/generic, so we can see those errors earlier.
SUITES = [dicts, set_tests, strings, globals, xml, fetch, paths, poms, poms_merging, maven]

def _validate(ctx, suites):
    # Function objects don't have good properties, so we hack it from the string representation.
    suite_targets = [str(suite)[1:-1].split(" ")[3] for suite in SUITES]
    suite_names = [target.replace("//", "").replace(":", "/") for target in suite_targets]
    unreferenced = sets.difference(sets.copy_of(suite_names), sets.copy_of([x.path for x in ctx.files.srcs]))
    if bool(unreferenced):
        fail("Some globbed tests were not referenced in all_tests.bzl's SUITES: %s" % list(unreferenced))

def _all_tests_rule_impl(ctx):
    _validate(ctx, SUITES)
    failures = []
    for suite in SUITES:
        suite_failures = suite()
        for failure in suite_failures:
            failures.append(failure)
    if bool(failures):
        fail("Test Failures:\n%s" % "\n".join(failures))
    return [DefaultInfo()]

all_tests = rule(
    implementation = _all_tests_rule_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
    }
)
