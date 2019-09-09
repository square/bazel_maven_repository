#
# Description:
#   Common utilities to make code a little cleaner.
#

_DICT_ENCODING_SEPARATOR = ">>>"

# Performs a typical "trim()" operation on a string, eliminating whitespace (or optionally supplied characters) from
# the front and back of the string.
def _trim(string, characters = "\n "):
    return string.strip(characters)

def _contains(string, substring):
    return not (string.find(substring) == -1)

def _munge(to_mangle, *characters_to_munge):
    if len(characters_to_munge) == 0:
        fail("Illegal argument: no mangling characters given when mangling %s" % to_mangle)
    for char in characters_to_munge:
        to_mangle = to_mangle.replace(char, "_")
    return to_mangle

strings = struct(
    contains = _contains,
    trim = _trim,
    munge = _munge,
)

def _filename(string):
    (path, sep, file) = string.rpartition("/")
    return file if bool(sep) else string

paths = struct(
    filename = _filename,
)

def _max_int(a, b):
    return a if a > b else b

ints = struct(
    max = _max_int,
)

# Encodes a dict(string->dict(string->string)) into a dict(string->list(string)) with the string encoded so it can
# be split and restored in decode_nested.  Skylark rules can't take in arbitrarily deep dict nesting.
#
# This function only handles one level of depth, and only handles string keys and values.
def _encode_nested(dict):
    result = {}
    for key, value in dict.items():
        if type(value) == type({}):
            nested_encoded_list = []
            for nested_key, nested_value in value.items():
                nested_encoded_list += ["%s%s%s" % (nested_key, _DICT_ENCODING_SEPARATOR, nested_value)]
            result[key] = nested_encoded_list
        else:
            result[key] = value
    return result

# Decodes a dict(string->list(string)) into a dict(string->dict(string->string)) by splitting the nested string using
# the same separator used by encode_nested.  Skylark rules can't take in arbitrarily deep dict nesting.
#
# This function only handles one level of depth, and only handles string keys and values (in the final dictionary)
def _decode_nested(dict):
    result = {}
    for key, encoded_list in dict.items():
        nested_dict = {}
        for encoded_item in encoded_list:
            # Just blows up if it's not encoded right.  But this would be a software error in the bazel code, not
            # user error, so there's no recovery from that.
            nested_key, nested_value = encoded_item.split(_DICT_ENCODING_SEPARATOR)
            nested_dict[nested_key] = nested_value
        result[key] = nested_dict
    return result

dicts = struct(
    encode_nested = _encode_nested,
    decode_nested = _decode_nested,
)
