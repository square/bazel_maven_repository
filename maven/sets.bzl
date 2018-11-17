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
    for item in items:
        _add(set_dict, item)
    return set_dict

def _pop(set_dict):
    """Pops the next item from the set."""
    item, _ = set_dict.popitem()
    return item

def _new():
    """Creates a new set.  Not strictly necessary, since a dict can be passed, but it's more """
    return {}


sets = struct(
    contains = _contains,
    add = _add,
    add_all = _add_all,
    pop = _pop,
    new = _new,
)