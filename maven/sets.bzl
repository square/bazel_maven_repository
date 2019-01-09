"""
A set of utilities that provide set-like behavior, using a dict (specifically its keys) as the underlying
implementation.  Generally just pass a dict into these.
"""

_UNDEFINED = "__UNDEFINED__"
_EMPTY = "__EMPTY__"

def _contains(set_dict, item):
    """Returns true if the set contains the supplied item"""
    return not (set_dict.get(item, _UNDEFINED) == _UNDEFINED)

def _add(set_dict, item):
    """Adds an item to the set and returns the set"""
    set_dict[item] = _EMPTY
    return set_dict

def _add_all(set_dict, items):
    """Adds all items to the set and returns the set"""
    item_type = type(items)
    if item_type == type({}):
        for item in items.keys():
            _add(set_dict, item)
    elif item_type == type([]):
        for item in items:
            _add(set_dict, item)
    else:
        fail("Error, invalid %s argument passed to set operation." % item_type)
    return set_dict

def _pop(set_dict):
    """Pops the next item from the set."""
    item, _ = set_dict.popitem()
    return item

def _new():
    """Creates a new set.  Not strictly necessary, since a dict can be passed, but it's more """
    return {}

def _difference(set_dict1, set_dict2):
    """Returns the elements that reflect the set difference (items in set_dict2 that are not in set_dict1)"""
    return sets.add_all(sets.new(), [x for x in set_dict1 if not sets.contains(set_dict2, x)])

def _disjunctive_union(set_dict1, set_dict2):
    """Returns a set containing all the elements in the supplied sets are not contained in both sets."""
    result = sets.new()
    sets.add_all(result, sets.difference(set_dict1, set_dict2))
    sets.add_all(result, sets.difference(set_dict2, set_dict1))
    return result

sets = struct(
    difference = _difference,
    disjunctive_union = _disjunctive_union,
    contains = _contains,
    add = _add,
    add_all = _add_all,
    pop = _pop,
    new = _new,
)