#!/usr/bin/env bash

# This script manages container operations for OpenWRT builds
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2024 Wesley Gimenes <wehagy@proton.me>
# See LICENSE for the full license text.

set -e
set -u
set -x
set -o pipefail

# sed -i -e 's,--- a/net,--- a/custom-feed,g' -e 's,+++ b/net,+++ b/custom-feed,g' patches/podman-200-update_to_5.2.2.patch
# sed -i 's,include ../..,include $(TOPDIR)/feeds/packages,g' custom-feed/*/Makefile
# quilt add custom-feed/*/Makefile
# quilt refresh
# https://github.com/openwrt/openwrt/blob/7e1d0925526a104364630b7af5355b799ef884d9/target/imagebuilder/files/Makefile#L43-L55

docker build \
    --build-arg TARGET=x86 \
    --build-arg SUBTARGET=64 \
    --build-arg IMAGE_PROFILE=generic \
    --progress plain \
    --output type=local,dest=openwrt-x86 .
