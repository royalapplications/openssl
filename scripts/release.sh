#!/usr/bin/env bash

set -e

SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
echo "Script Path: ${SCRIPT_PATH}"

if [[ -z $OPENSSL_VERSION ]]; then
  echo "OPENSSL_VERSION not set; aborting"
  exit 1
fi

BUILD_DIR="${SCRIPT_PATH}/../build/openssl-${OPENSSL_VERSION}/build"
echo "Build Path: ${BUILD_DIR}"

if [[ ! -d "${BUILD_DIR}" ]]; then
  echo "Build dir not found: ${BUILD_DIR}"
  exit 1
fi

pushd "${BUILD_DIR}"

echo "Creating ${BUILD_DIR}/openssl.tar.gz"
rm -f "openssl.tar.gz"
tar czf "openssl.tar.gz" iphoneos iphonesimulator macosx

echo "Creating ${BUILD_DIR}/OpenSSL.xcframework.tar.gz"
rm -f "OpenSSL.xcframework.tar.gz"
tar czf "OpenSSL.xcframework.tar.gz" OpenSSL.xcframework

popd