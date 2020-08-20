#!/usr/bin/env bash
set -x
set -e

(cd kramer && bazel test //...)
(cd kramer && bazel build //:kramer_shaded)
RELEASE_JAR=maven/kramer-resolve.jar
BUILT_JAR=kramer/bazel-bin/kramer_shaded.jar
cp ${BUILT_JAR} ${RELEASE_JAR}
git add ${RELEASE_JAR}
git commit -m "Auto-add kramer to the main tree" ${RELEASE_JAR}
