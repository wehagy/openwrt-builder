# :construction: openwrt-builder (WIP)

## :rotating_light: CAREFUL! WORKING IN PROGRESS!

Maybe this code can kill your cat  
For now i'm reseting this repo a lot

<!--
git format-patch --no-signature --stdout master..netbird/update > netbird-update-to-0.29.4.patch
sed -i -e 's,--- a/net,--- a/custom-feed,g' -e 's,+++ b/net,+++ b/custom-feed,g' patches/podman-200-update_to_5.2.2.patch
sed -i 's,include ../..,include $(TOPDIR)/feeds/packages,g' custom-feed/*/Makefile
quilt add custom-feed/*/Makefile
quilt refresh
quilt push -a
quilt pop -a
printf -v test "%(%Y.%m.%d_%H.%M.%S)T"
-->
