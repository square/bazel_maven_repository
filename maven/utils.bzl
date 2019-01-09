#
# Description:
#   Common utilities to make code a little cleaner.
#

# Performs a typical "trim()" operation on a string, eliminating whitespace (or optionally supplied characters) from
# the front and back of the string.
def _trim(string, characters = "\n "):
    return string.strip(characters)

def _contains(string, substring):
    return not (string.find(substring) == -1)

strings = struct(
    contains = _contains,
    trim = _trim,
)

def _filename(string):
    (path, sep, file) = string.rpartition("/")
    return file if bool(sep) else string

paths = struct(
    filename = _filename
)
