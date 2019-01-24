_EMPTY_SET_VALUE = "__EMPTY__" # Check when changing this to keep in sync with sets.bzl

def _assert_true(env, condition, message = "Expected condition to be true, but was false."):
    if not condition:
        asserts.fail(env, message)

def _assert_false(env, condition, message = "Expected condition to be false, but was true."):
    if condition:
        asserts.fail(env, message)

def _is_set(maybe):
    return (
        type(maybe) == type({})
        and len(maybe) > 0
        and maybe.values()[0] == _EMPTY_SET_VALUE
    )

def _convert_if_set(maybe):
    return "set%s" % list(maybe) if _is_set(maybe) else maybe

def _assert_equals(env, expected, actual, message = None):
    if expected != actual:
        # Handle our special set type.
        expected = _convert_if_set(expected)
        actual = _convert_if_set(actual)
        expectation_msg = 'Expected <%s>, but was <%s>' % (expected, actual)
        full_message = "%s (%s)" % (message, expectation_msg) if message else expectation_msg
        asserts.fail(env, full_message)

def _fail(env, failure_message):
    error = "Assertion failure in test %s: %s" % (env.current[0].name, failure_message)
    if not env.fail_at_end:
        fail(error)
    env.current[0].failures.append(error)

# Holds the assertion functions.
asserts = struct(
    fail = _fail,
    equals = _assert_equals,
    true = _assert_true,
    false = _assert_false,
)


# Runs all the tests in a given suite.
def test_suite(name, tests = [], fail_at_end = True):
    print("TEST: ===============================================")
    print("TEST: Executing test suite: %s\n\n" % name)
    env = struct(name = name, failures = [], current = [], fail_at_end = fail_at_end)
    failing_test_cases = 0
    for test in tests:
        env.current.append(struct(name = str(test), failures = []))
        test(env)
        result = env.current.pop()
        if bool(result.failures):
            failing_test_cases += 1
            for failure in result.failures:
                env.failures.append(failure)
        print("TEST: %s ..... %s" % (
            str(test), "FAILED on %s assertions" % len(result.failures) if bool(result.failures) else "PASSED"))
    print("TEST: -----------------------------------------------")
    print("TEST: %s tests executed, %s test cases failed.\n\n"% (len(tests), failing_test_cases, ))
    return env.failures
