FROM ghcr.io/openwrt/sdk:x86-64-main AS sdk-stage

COPY --chown=buildbot /custom-feed/ ./custom-feed/ 
COPY --chown=buildbot /patches/ ./patches/

USER root
RUN <<EOF
  apt update
  apt install -y quilt
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

for PACKAGE in custom-feed/*; do
  ./scripts/feeds install "${PACKAGE##*/}"
  make package/"${PACKAGE##*/}"/{clean,compile} \
    V=s \
    -j"$(nproc)"
done
EOF
RUN ./build.sh



FROM sdk-stage AS sdk-packages-stage
COPY --chmod=755 <<"EOF" clean.sh
#!/usr/bin/env bash

set -e
set -u
set -x
set -o pipefail

rm -rf bin/targets/
rmdir bin/packages/*/custom/tmp || true
shopt -s extglob
rm -rf bin/packages/*/!(custom)
shopt -u extglob

mkdir packages
shopt -s globstar nullglob
for IPK in bin/**/custom/*.ipk; do
  cp "${IPK}" packages/
done
shopt -u globstar nullglob

EOF
RUN ./clean.sh



FROM ghcr.io/openwrt/imagebuilder:x86-64-main AS imagebuilder-stage

ENV PROFILE_IMAGE="${PROFILE_IMAGE:-generic}"
ENV PACKAGES_IMAGE="${PACKAGES_IMAGE:-luci luci-ssl}"

COPY --from=sdk-packages-stage --chown=buildbot /builder/packages/* /builder/packages/

COPY --chmod=755 <<"EOF" build.sh
#!/usr/bin/env bash

set -e
set -u
set -x
set -o pipefail

shopt -s globstar nullglob
PACKAGES_IMAGE+="$(basename -a packages/*.ipk | awk -F'_' '{printf " %s", $1}')" || true
shopt -u globstar nullglob

make image PROFILE="${PROFILE_IMAGE}" PACKAGES="${PACKAGES_IMAGE}" \
  V=s \
  -j"$(nproc)"
EOF
RUN ./build.sh



FROM scratch AS export-stage
COPY --from=sdk-packages-stage /builder/bin/ .
COPY --from=imagebuilder-stage /builder/bin/ .
