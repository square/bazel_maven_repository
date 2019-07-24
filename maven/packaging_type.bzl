# Artifact types supported by bazel maven repository

_JAR = struct(name = "jar", suffix = "jar")
_AAR = struct(name = "aar", suffix = "aar")
_BUNDLE = struct(name = "bundle", suffix = "jar")
_VALUES = [_JAR, _AAR, _BUNDLE]

def _value_of_packaging_types(string):
    for val in _VALUES:
        if string == val.name:
            return val
    return None

# enum
packaging_type = struct(
    JAR = _JAR,
    AAR = _AAR,
    BUNDLE = _BUNDLE,
    DEFAULT = _JAR,
    values = _VALUES,
    value_of = _value_of_packaging_types,
)
