#!/usr/bin/env bash

# This script manages container operations for OpenWRT builds
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024 Wesley Gimenes <wehagy@proton.me>
# See LICENSE for the full license text.

set -euxo pipefail

# Check and set the container manager (Podman or Docker)
if command -v podman; then
    CONTAINER_MANAGER="podman"
elif command -v docker; then
    CONTAINER_MANAGER="docker"
    printf '%s/n' "Important: ${CONTAINER_MANAGER} functionality may be incomplete or unstable - please test carefully before use"
else
    printf '%s/n' "ERROR: no container manager found, please install podman or docker"
    exit 1
fi

# Packages to install or to remove for the build
mapfile -t TMP < <(
    [[ -d custom-feed ]]
    ls custom-feed
)
PACKAGES_IMAGE+=(
    luci
    luci-ssl
    luci-app-attendedsysupgrade
    luci-app-watchcat
    "${TMP[@]}"
)
unset TMP

# Build process for a specific target, subtarget, and profile
build () {
    local TARGET="${1:?Please set target}"
    local SUBTARGET="${2:?Please set subtarget }"
    local PROFILE_IMAGE="${3:?Please set profile image}"
    local BRANCH="${4:-main}"

    CONTAINER_PREFIX="ghcr.io/openwrt"
    CONTAINER_TAG="${TARGET}-${SUBTARGET}-${BRANCH}"
    CONTAINER_SDK_IMAGE="${CONTAINER_PREFIX}/sdk:${CONTAINER_TAG}"
    CONTAINER_IMAGEBUILDER_IMAGE="${CONTAINER_PREFIX}/imagebuilder:${CONTAINER_TAG}"

    CONTAINER_COMMON_ARGS=(
        run
        --rm
        --user 0:0
        --pull always
        --volume "${PWD}"/bin/:/builder/bin/
        "$([[ -d custom-feed ]] && printf -- '--volume %s/custom-feed/:/builder/custom-feed/:ro' "${PWD}" || true)"
    )

    CONTAINER_SDK_ARGS=(
        ${CONTAINER_COMMON_ARGS[@]}
        "${CONTAINER_SDK_IMAGE}"
        # Update feeds and build packages
        bash -c "
            sed -i '2i src-link custom /builder/custom-feed' feeds.conf.default
            ./scripts/feeds update packages custom
            make defconfig

            # Logic to build additional packages
            for PACKAGE in custom-feed/*; do
                ./scripts/feeds install \"\${PACKAGE##*/}\"
                make package/\"\${PACKAGE##*/}\"/{clean,compile} -j \"\$( nproc )\"
            done

            # Clean kernel modules
            rm -rf bin/targets/
        "
    )

    CONTAINER_IMAGEBUILDER_ARGS=(
        ${CONTAINER_COMMON_ARGS[@]}
        "${CONTAINER_IMAGEBUILDER_IMAGE}"
        # Create symbolic links for IPK files and build the final image
        bash -c "
            shopt -s globstar nullglob
            for IPK in bin/**/*.ipk; do
                ln -sr \"\${IPK}\" packages/
            done
            shopt -u globstar nullglob
            make image PROFILE=${PROFILE_IMAGE} PACKAGES=\"${PACKAGES_IMAGE[*]}\"
        "
    )

    # Prepare the output directory
    [[ ! -d bin ]] && install --mode=0755 --directory bin

    [[ -d custom-feed ]] && "${CONTAINER_MANAGER}" "${CONTAINER_SDK_ARGS[@]}"
    "${CONTAINER_MANAGER}" "${CONTAINER_IMAGEBUILDER_ARGS[@]}"
    mv bin "openwrt-${TARGET}-${SUBTARGET}-${PROFILE_IMAGE}-$(TZ='America/Sao_Paulo' date +"%Y.%m.%d_%H.%M.%S")"
}

quilt push -a
build "${@:?Please set <target> <subtarget> <profile> <opcional:openwrt branch, default is main>}"
quilt pop -a

exit 0
