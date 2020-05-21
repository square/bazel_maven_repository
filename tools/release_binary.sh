#!/usr/bin/env bash

(cd kramer && bazel build //:kramer_deploy.jar)
RELEASE_JAR=maven/kramer-resolve.jar
BUILT_JAR=kramer/bazel-bin/kramer_deploy.jar
cp ${BUILT_JAR} ${RELEASE_JAR}
git add ${RELEASE_JAR}
git commit -m "Auto-add kramer to the main tree" ${RELEASE_JAR}
