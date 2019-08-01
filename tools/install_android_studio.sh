#!/usr/bin/env bash
# Download android SDK, if not already present, explode it, and install the correct bits.

# Assume that PLATFORM, ANDROID_SDK_TOOLS_VERSION, ANDROID_PLATFORM_VERSION and ANDROID_BUILD_TOOLS_VERSION
# are in the environment presented to this script.

SDK_MANAGER=${ANDROID_HOME}/tools/bin/sdkmanager
SDK_TOOLS_FILE=sdk-tools-${PLATFORM}-${ANDROID_SDK_TOOLS_VERSION}.zip

if [[ ! -e ${SDK_MANAGER} ]]; then
  cd ${HOME}
  wget https://dl.google.com/android/repository/${SDK_TOOLS_FILE}
  mkdir -p ${ANDROID_HOME}
  cd ${ANDROID_HOME}
  unzip ${HOME}/${SDK_TOOLS_FILE}
else
  echo "sdk manager already exists, skipping download."
fi

yes | ${SDK_MANAGER} "platform-tools" > /dev/null
yes | ${SDK_MANAGER} "platforms;android-${ANDROID_PLATFORM_VERSION}" >/dev/null
yes | ${SDK_MANAGER} "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" >/dev/null
${SDK_MANAGER} --list
