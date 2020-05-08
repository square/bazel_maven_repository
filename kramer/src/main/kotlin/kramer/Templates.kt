package kramer

internal fun aar_template(
  target: String,
  coordinate: String,
  customPackage: String,
  jetify: String,
  deps: String,
  fetchRepo: String,
  testonly: String,
  visibility: String
) = """
# $coordinate raw classes
raw_jvm_import(
    name = "${target}_classes",
    jar = "$fetchRepo:classes.jar",$jetify
    deps = [$deps],
)

# $coordinate library target
android_library(
    name = "$target",
    manifest = "$fetchRepo:AndroidManifest.xml",
    custom_package = "$customPackage",
    visibility = $visibility,
    resource_files = ["$fetchRepo:resources"],
    assets = ["$fetchRepo:assets"],
    assets_dir = "assets",
    deps = [":${target}_classes"] + [$deps],$testonly
)
"""

internal fun jar_template(
  target: String,
  coordinate: String,
  jarPath: String,
  jetify: String,
  deps: String,
  fetchRepo: String,
  testonly: String,
  visibility: String
) = """
# $coordinate
raw_jvm_import(
    name = "$target",
    jar = "$fetchRepo:$jarPath",
    visibility = $visibility,$jetify
    deps = [$deps],$testonly
)
"""
