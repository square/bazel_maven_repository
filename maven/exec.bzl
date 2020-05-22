#
# Copyright (C) 2020 Square, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
# in compliance with the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License
# is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing permissions and limitations under
# the License.

# Description:
#   Common utilities to make code a little cleaner.

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
