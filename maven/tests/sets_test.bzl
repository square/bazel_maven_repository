load(":testing.bzl", "asserts", "test_suite")
load("//maven:sets.bzl", "sets")

def new_test(env):
    set = sets.new()
    asserts.equals(env, 0, len(set))
    set = sets.new("a", "b", "c")
    asserts.equals(env, 3, len(set))
    asserts.equals(env, ["a", "b", "c"], list(set))

def equality_test(env):
    a = sets.new()
    b = sets.new()
    sets.add(a, "foo1")
    sets.add(b, "foo1")
    asserts.equals(env, a, b)

def inequality_test(env):
    a = sets.new()
    b = sets.new()
    sets.add(a, "foo1")
    sets.add(b, "foo1")
    asserts.equals(env, a, b)

def add_test(env):
    a = sets.new()
    sets.add(a, "foo")
    asserts.equals(env, "foo", list(a)[0])

def add_all_as_list_test(env):
    a = sets.new()
    sets.add_all(a, ["foo", "bar", "baz"])
    asserts.equals(env, ["foo", "bar", "baz"], list(a))

def add_all_as_dict_test(env):
    a = sets.new()
    sets.add_all(a, {"foo": "", "bar": "", "baz": ""})
    asserts.equals(env, ["foo", "bar", "baz"], list(a))

def add_each_test(env):
    a = sets.new()
    sets.add_each(a, "foo", "bar", "baz")
    asserts.equals(env, ["foo", "bar", "baz"], list(a))

def set_behavior_test(env):
    a = sets.new("foo", "bar", "baz")
    sets.add(a, "bar")
    asserts.equals(env, ["foo", "bar", "baz"], list(a))

def pop_test(env):
    a = sets.new("a", "b", "c")
    item = sets.pop(a)
    asserts.equals(env, 2, len(a))
    item = sets.pop(a)
    asserts.equals(env, 1, len(a))
    item = sets.pop(a)
    asserts.equals(env, 0, len(a))
    # Can't test failure, as that invokes bazel fail().

def contains_test(env):
    a = sets.new("a")
    asserts.true(env, sets.contains(a, "a"))
    asserts.false(env, sets.contains(a, "b"))

def difference_test(env):
    a = sets.new("a", "b", "c")
    b = sets.new ("c", "d", "e")
    asserts.equals(env, sets.new("d", "e"), sets.difference(a, b))
    asserts.equals(env, sets.new("a", "b"), sets.difference(b, a))

def disjoint_test(env):
    a = sets.new("a", "b", "c")
    b = sets.new ("c", "d", "e")
    asserts.equals(env, sets.new("a", "b", "d", "e"), sets.disjoint(a, b))

TESTS = [
    new_test,
    equality_test,
    inequality_test,
    pop_test,
    add_test,
    add_all_as_dict_test,
    add_all_as_list_test,
    add_each_test,
    set_behavior_test,
    contains_test,
    difference_test,
    disjoint_test,
]

# Roll-up function.
def sets_test_suite():
    test_suite("sets", tests = TESTS)