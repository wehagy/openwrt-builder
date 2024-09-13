#!/usr/bin/env bash

# This script manages container operations for OpenWRT builds
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024 Wesley Gimenes <wehagy@proton.me>
# See LICENSE for the full license text.


# sed -i -e 's,--- a/net,--- a/custom-feed,g' -e 's,+++ b/net,+++ b/custom-feed,g' patches/podman-200-update_to_5.2.2.patch
# sed -i 's,include ../..,include $(TOPDIR)/feeds/packages,g' custom-feed/*/Makefile
# quilt add custom-feed/*/Makefile
# quilt refresh
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
        --transient-store
        run
        --rm
        --pull always
        #--userns keep-id
        --image-volume tmpfs
        --volume "${PWD}"/bin/:/builder/bin/
        "$([[ -d custom-feed ]] && printf -- '--volume %s/custom-feed/:/builder/custom-feed/:ro' "${PWD}" || true)"
    )

    CONTAINER_SDK_ARGS=(
        ${CONTAINER_COMMON_ARGS[@]}
        "${CONTAINER_SDK_IMAGE}"
        bash -c "
            # Update feeds and build packages
            sed \
                --in-place \
                --regexp-extended \
                    's,git\.openwrt\.org\/(openwrt|feed|project),github\.com\/openwrt,' \
                    feeds.conf.default
            sed \
                --in-place \
                    '1i src-link custom /builder/custom-feed' \
                    feeds.conf.default
            ./scripts/feeds update -a
            make defconfig

            # Logic to build additional packages
            for PACKAGE in custom-feed/*; do
                ./scripts/feeds install \"\${PACKAGE##*/}\"
                make package/\"\${PACKAGE##*/}\"/{clean,compile} \
                    V=s \
                    -j \"\$( nproc )\"
            done

            # Clean
            rm -rf bin/targets/
            rmdir bin/packages/*/custom/tmp
            shopt -s extglob
            rm -rf bin/packages/*/!(custom)
            shopt -u extglob
        "
    )

    CONTAINER_IMAGEBUILDER_ARGS=(
        ${CONTAINER_COMMON_ARGS[@]}
        "${CONTAINER_IMAGEBUILDER_IMAGE}"
        bash -c "
            # Create symbolic links for IPK files and build the final image
            shopt -s globstar nullglob
            for IPK in bin/**/*.ipk; do
                ln -sr \"\${IPK}\" packages/
            done
            shopt -u globstar nullglob

            make image \
                V=s \
                -j \"\$( nproc )\" \
                PROFILE=${PROFILE_IMAGE} PACKAGES=\"${PACKAGES_IMAGE[*]}\"
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
