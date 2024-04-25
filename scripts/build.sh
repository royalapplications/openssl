#!/usr/bin/env bash

set -e

OPENSSL_VERSION_STABLE="3.2.1" # https://www.openssl.org/source/index.html
IOS_VERSION_MIN="13.4"
MACOS_VERSION_MIN="11.0"
CODESIGN_ID="-"

SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
echo "Script Path: ${SCRIPT_PATH}"

BUILD_ROOT_DIR="${SCRIPT_PATH}/../build"
echo "Build Path: ${BUILD_ROOT_DIR}"
mkdir -p "${BUILD_ROOT_DIR}"

if [[ -z $OPENSSL_VERSION ]]; then
  echo "OPENSSL_VERSION not set; falling back to ${OPENSSL_VERSION_STABLE} (Stable)"
  OPENSSL_VERSION="${OPENSSL_VERSION_STABLE}"
fi

if [[ ! -f "${BUILD_ROOT_DIR}/openssl-${OPENSSL_VERSION}.tar.gz" ]]; then
  echo "Downloading openssl-${OPENSSL_VERSION}.tar.gz"
  curl -fL "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" -o "${BUILD_ROOT_DIR}/openssl-${OPENSSL_VERSION}.tar.gz"
  curl -fL "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz.sha256" -o "${BUILD_ROOT_DIR}/openssl-${OPENSSL_VERSION}.tar.gz.sha256"
  DIGEST=$( cat "${BUILD_ROOT_DIR}/openssl-${OPENSSL_VERSION}.tar.gz.sha256" )

  if [[ "$(shasum -a 256 "${BUILD_ROOT_DIR}/openssl-${OPENSSL_VERSION}.tar.gz" | awk '{ print " "$1}')" != "${DIGEST}" ]]
  then
    echo "openssl-${OPENSSL_VERSION}.tar.gz: checksum mismatch"
    exit 1
  fi
  rm -f "${BUILD_ROOT_DIR}/openssl-${OPENSSL_VERSION}.tar.gz.sha256"
fi

BUILD_DIR="${BUILD_ROOT_DIR}/openssl-${OPENSSL_VERSION}"

if [[ ! -d "${BUILD_DIR}" ]]; then
  mkdir -p "${BUILD_DIR}"
  tar xzf "${BUILD_ROOT_DIR}/openssl-${OPENSSL_VERSION}.tar.gz" -C "${BUILD_DIR}" --strip-components=1
fi

THREAD_COUNT=$(sysctl hw.ncpu | awk '{print $2}')

build_sim_libs()
{
  local ARCH=$1
  if [[ ! -d "${BUILD_DIR}/build/iphonesimulator-${ARCH}" ]]; then
    pushd "${BUILD_DIR}"
    ./Configure --openssldir="${BUILD_DIR}/build/ssl" no-asm no-shared no-tests no-dso no-hw no-engine iossimulator-xcrun CFLAGS="-arch $ARCH -mios-simulator-version-min=${IOS_VERSION_MIN}"
    make clean
    make -j$THREAD_COUNT
    mkdir "${BUILD_DIR}/build/iphonesimulator-${ARCH}"
    cp libssl.a "${BUILD_DIR}/build/iphonesimulator-${ARCH}/"
    cp libcrypto.a "${BUILD_DIR}/build/iphonesimulator-${ARCH}/"
    make clean
	popd
  fi
}

HOST_ARC="$( uname -m )"
if [ "$HOST_ARC" = "arm64" ]; then
  FOREIGN_ARC="x86_64"
else
  FOREIGN_ARC="arm64"
fi
NATIVE_BUILD_FLAGS="-mmacosx-version-min=${MACOS_VERSION_MIN}"

if [[ ! -d "${BUILD_DIR}/build/lib" ]]; then
  pushd "${BUILD_DIR}"
  ./Configure --prefix="${BUILD_DIR}/build" --openssldir="${BUILD_DIR}/build/ssl" no-shared no-tests darwin64-$HOST_ARC-cc CFLAGS="${NATIVE_BUILD_FLAGS}"
  make clean
  make -j$THREAD_COUNT
  make -j$THREAD_COUNT install_sw # skip man pages, see https://github.com/openssl/openssl/issues/8170#issuecomment-461122307
  make clean
  popd
fi

if [[ ! -d "${BUILD_DIR}/build/macosx" ]]; then
  pushd "${BUILD_DIR}"
  ./Configure --openssldir="${BUILD_DIR}/build/ssl" no-shared no-tests darwin64-$FOREIGN_ARC-cc CFLAGS="-arch ${FOREIGN_ARC} ${NATIVE_BUILD_FLAGS}"
  make clean
  make -j$THREAD_COUNT
  mkdir "${BUILD_DIR}/build/macosx"
  mkdir "${BUILD_DIR}/build/macosx/include" 
  mkdir "${BUILD_DIR}/build/macosx/lib"
  cp -r "${BUILD_DIR}/build/include/openssl" "${BUILD_DIR}/build/macosx/include/OpenSSL"
  lipo -create "${BUILD_DIR}/build/lib/libssl.a"    libssl.a    -output "${BUILD_DIR}/build/macosx/lib/libssl.a"
  lipo -create "${BUILD_DIR}/build/lib/libcrypto.a" libcrypto.a -output "${BUILD_DIR}/build/macosx/lib/libcrypto.a"
  xcrun libtool -static -o "${BUILD_DIR}/build/macosx/lib/libOpenSSL.a" "${BUILD_DIR}/build/macosx/lib/libcrypto.a" "${BUILD_DIR}/build/macosx/lib/libssl.a"
  make clean
  popd
fi

if [[ ! -d "${BUILD_DIR}/build/iphonesimulator" ]]; then
  build_sim_libs arm64
  build_sim_libs x86_64
  mkdir "${BUILD_DIR}/build/iphonesimulator"
  mkdir "${BUILD_DIR}/build/iphonesimulator/include" 
  mkdir "${BUILD_DIR}/build/iphonesimulator/lib"
  cp -r "${BUILD_DIR}/build/include/openssl" "${BUILD_DIR}/build/iphonesimulator/include/OpenSSL"
  lipo -create "${BUILD_DIR}/build/iphonesimulator-x86_64/libssl.a"    "${BUILD_DIR}/build/iphonesimulator-arm64/libssl.a"    -output "${BUILD_DIR}/build/iphonesimulator/lib/libssl.a"
  lipo -create "${BUILD_DIR}/build/iphonesimulator-x86_64/libcrypto.a" "${BUILD_DIR}/build/iphonesimulator-arm64/libcrypto.a" -output "${BUILD_DIR}/build/iphonesimulator/lib/libcrypto.a"
  xcrun libtool -static -o "${BUILD_DIR}/build/iphonesimulator/lib/libOpenSSL.a" "${BUILD_DIR}/build/iphonesimulator/lib/libcrypto.a" "${BUILD_DIR}/build/iphonesimulator/lib/libssl.a"
  rm -rf "${BUILD_DIR}/build/iphonesimulator-arm64"
  rm -rf "${BUILD_DIR}/build/iphonesimulator-x86_64"
fi

if [[ ! -d "${BUILD_DIR}/build/iphoneos" ]]; then
  pushd "${BUILD_DIR}"
  ./Configure --openssldir="${BUILD_DIR}/build/ssl" no-asm no-shared no-tests no-dso no-hw no-engine ios64-xcrun -mios-version-min=${IOS_VERSION_MIN}
  make clean
  make -j$THREAD_COUNT
  mkdir "${BUILD_DIR}/build/iphoneos" 
  mkdir "${BUILD_DIR}/build/iphoneos/include" 
  mkdir "${BUILD_DIR}/build/iphoneos/lib"
  cp -r "${BUILD_DIR}/build/include/openssl" "${BUILD_DIR}/build/iphoneos/include/OpenSSL"
  cp libssl.a "${BUILD_DIR}/build/iphoneos/lib/"
  cp libcrypto.a "${BUILD_DIR}/build/iphoneos/lib/"
  xcrun libtool -static -o "${BUILD_DIR}/build/iphoneos/lib/libOpenSSL.a" "${BUILD_DIR}/build/iphoneos/lib/libcrypto.a" "${BUILD_DIR}/build/iphoneos/lib/libssl.a"
  make clean
  popd
fi

if [[ ! -d "${BUILD_DIR}/build/OpenSSL.xcframework" ]]; then
  xcodebuild -create-xcframework \
    -library "${BUILD_DIR}/build/macosx/lib/libOpenSSL.a" \
    -library "${BUILD_DIR}/build/iphonesimulator/lib/libOpenSSL.a" \
    -library "${BUILD_DIR}/build/iphoneos/lib/libOpenSSL.a" \
    -output "${BUILD_DIR}/build/OpenSSL.xcframework"

  codesign \
    --force --deep --strict \
    --sign "${CODESIGN_ID}" \
    "${BUILD_DIR}/build/OpenSSL.xcframework"
fi