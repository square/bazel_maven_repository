#
# Description:
#   Common utilities to make code a little cleaner.
#

def _java_executable(ctx):
    java_home = ctx.os.environ.get("JAVA_HOME")
    if java_home != None:
        java = ctx.path(java_home + "/bin/java")
        return java
    elif ctx.which("java") != None:
        return ctx.which("java")
    fail("Cannot obtain java binary")

def _exec_jar(root, label):
    return "%s/../%s/%s/%s" % (root, label.workspace_name, label.package, label.name)

exec = struct(
    java_bin = _java_executable,
    exec_jar = _exec_jar,
)
