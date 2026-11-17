#!/bin/bash
set -euxo pipefail

cd "$(dirname "$0")"
export DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-1}
BUILD_LOG=${BUILD_LOG:-docker-browser-build.log}
OUTPUT_DIR=${OUTPUT_DIR:-build-emscripten-web}
: > "${BUILD_LOG}"
rm -rf "${OUTPUT_DIR}"
# vcpkg's built libraries (restored by the CI's cache step): go into the build
# with the sources, and come back out updated for the cache to save
VCPKG_CACHE_DIR=${VCPKG_CACHE_DIR:-vcpkg-cache}
mkdir -p "${VCPKG_CACHE_DIR}"
if [ "${VCPKG_CACHE_DIR}" != "vcpkg-cache" ]; then
	rm -rf vcpkg-cache && cp -a "${VCPKG_CACHE_DIR}" vcpkg-cache
fi
docker build --progress=plain -t otclient-web -f Dockerfile.browser . 2>&1 | tee -a "${BUILD_LOG}"
test "${PIPESTATUS[0]}" -eq 0
docker rm -f otclient-web-tmp >/dev/null 2>&1 || true
docker create --name otclient-web-tmp otclient-web:latest
docker cp otclient-web-tmp:/otclient-web "${OUTPUT_DIR}"
docker rm otclient-web-tmp

# the cache as the build left it (the builder stage, already built: no rebuild)
docker build --progress=plain --target builder -t otclient-web-builder -f Dockerfile.browser . >> "${BUILD_LOG}" 2>&1
docker rm -f otclient-web-cache >/dev/null 2>&1 || true
docker create --name otclient-web-cache otclient-web-builder:latest
rm -rf vcpkg-cache.new
docker cp otclient-web-cache:/workspace/vcpkg-cache vcpkg-cache.new
docker rm otclient-web-cache
rm -rf "${VCPKG_CACHE_DIR}"
mv vcpkg-cache.new "${VCPKG_CACHE_DIR}"
du -sh "${VCPKG_CACHE_DIR}" || true
