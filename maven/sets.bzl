"""
A set of utilities that provide set-like behavior, using a dict (specifically its keys) as the underlying
implementation.  Generally only use dictionaries created by sets.new() because values are normalized. Using
dictionaries from other sources may result in equality failing, and other odd behavior.
"""

_UNDEFINED = "__UNDEFINED__"
_EMPTY = "__EMPTY__"  # Check when changing this to keep in sync with sets.bzl
_SET_DICTIONARY_KEY = "_____SET_DICTIONARY_KEY______"

def _contains(set, item):
    """Returns true if the set contains the supplied item"""
    return not (set.get(item, _UNDEFINED) == _UNDEFINED)

def _add(set, item):
    """Adds an item to the set and returns the set"""
    set[item] = _EMPTY
    return set

def _add_all_as_list(set, items):
    "Implementation for the add_* family of functions."
    for item in items:
        sets.add(set, item)
    return set

def _add_all(set, items):
    """Adds all items in the list or all keys in the dictionary to the set and returns the set"""
    item_type = type(items)
    if item_type == type({}):
        _add_all_as_list(set, list(items))
    elif item_type == type([]):
        _add_all_as_list(set, items)
    else:
        fail("Error, invalid %s argument passed to set operation." % item_type)
    return set

def _add_each(set, *items):
    """Adds all items in the variable argument to the set and returns the set"""
    _add_all_as_list(set, list(items))
    return set

def _pop(set):
    """Pops the next item from the set."""
    item, _ = set.popitem()
    return item

def _new(*items):
    """Creates a new set. """
    return {} if not bool(items) else sets.add_all({}, list(items))

def _difference(a, b):
    """Returns the elements that reflect the set difference (items in b that are not in a)"""
    return sets.add_all(sets.new(), [x for x in list(b) if not sets.contains(a, x)])

def _disjoint(a, b):
    """Returns the elements each of a or b, but which are not in both sets."""
    set = sets.new()
    sets.add_all(set, sets.difference(b, a))
    sets.add_all(set, sets.difference(a, b))
    return set

sets = struct(
    difference = _difference,
    disjoint = _disjoint,
    contains = _contains,
    add = _add,
    add_all = _add_all,
    add_each = _add_each,
    pop = _pop,
    new = _new,
)