ARG TARGET="${TARGET:?Please set target}"
ARG SUBTARGET="${SUBTARGET:?Please set subtarget}"
ARG BRANCH="${BRANCH:-main}"
ARG CONTAINER_TAG="${TARGET}-${SUBTARGET}-${BRANCH}"
ARG CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-ghcr.io}"

FROM "${CONTAINER_REGISTRY}/openwrt/sdk:${CONTAINER_TAG}" AS sdk-stage

COPY --chown=buildbot custom-feed/ custom-feed/
COPY --chown=buildbot patches/ patches/

ARG DEBIAN_FRONTEND="noninteractive"
USER root
RUN <<EOF
apt update
apt upgrade -y
apt install -y \
    quilt
EOF

USER buildbot
COPY --chmod=755 <<"EOF" build.sh
#!/usr/bin/env bash

set -e
set -u
set -x
set -o pipefail

quilt push -a

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

for i in custom-feed/*; do
    ./scripts/feeds install "${i##*/}"
    make package/"${i##*/}"/{clean,compile} \
        -j"$(nproc)"
        #V=s
done

rm -rf bin/targets/
rmdir bin/packages/*/custom/tmp || true
shopt -s extglob
rm -rf bin/packages/*/!(custom)
shopt -u extglob
EOF
RUN ./build.sh



FROM "${CONTAINER_REGISTRY}/openwrt/imagebuilder:${CONTAINER_TAG}" AS imagebuilder-stage

ARG IMAGE_PROFILE="${IMAGE_PROFILE:?Please set profile image}"
ENV IMAGE_PROFILE="${IMAGE_PROFILE}"
ARG IMAGE_PACKAGES="${IMAGE_PACKAGES:-luci luci-ssl}"
ENV IMAGE_PACKAGES="${IMAGE_PACKAGES}"
ARG ROOTFS_SIZE=""
ENV ROOTFS_SIZE="${ROOTFS_SIZE}"

COPY --from=sdk-stage --chown=buildbot /builder/bin/ bin/

COPY --chmod=755 <<"EOF" build.sh
#!/usr/bin/env bash

set -e
set -u
set -x
set -o pipefail

shopt -s globstar nullglob
for i in bin/**/custom/*.ipk; do
    ln -sr "${i}" packages/
done

IMAGE_PACKAGES+="$(basename -a packages/*.ipk | awk -F'_' '{printf " %s", $1}')" || true
shopt -u globstar nullglob

make image \
    PROFILE="${IMAGE_PROFILE}" \
    PACKAGES="${IMAGE_PACKAGES}" \
    ROOTFS_PARTSIZE="${ROOTFS_SIZE}" \
    -j"$(nproc)" \
    #V=s
EOF
RUN ./build.sh



FROM scratch AS export-stage
COPY --from=imagebuilder-stage /builder/bin/ .
