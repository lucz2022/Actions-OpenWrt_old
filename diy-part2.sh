#!/bin/bash
set -e

# ---- 强制锁死目标为 x86_64/generic ----
./scripts/config -e CONFIG_TARGET_x86
./scripts/config -e CONFIG_TARGET_x86_64
./scripts/config -e CONFIG_TARGET_x86_64_DEVICE_generic

# ---- 镜像输出：BIOS/ISO/QCOW2 + 根文件系统 ----
./scripts/config -e CONFIG_TARGET_IMAGES_GZIP
./scripts/config -e CONFIG_TARGET_ROOTFS_SQUASHFS
./scripts/config -e CONFIG_TARGET_ROOTFS_EXT4FS
./scripts/config -e CONFIG_GRUB_IMAGES      # Legacy BIOS
./scripts/config -e CONFIG_ISO_IMAGES       # LiveCD ISO
./scripts/config -e CONFIG_QCOW2_IMAGES     # PVE/KVM 用

# （可选）UEFI 也要的话再开：
# ./scripts/config -e CONFIG_EFI_IMAGES

# ---- 保险：关掉 MIPS16（防止工具链切到别的 target 时触发）----
./scripts/config -d CONFIG_USE_MIPS16

# ---- 你的功能选择（和现在的 .config 保持一致）----
./scripts/config -e CONFIG_PACKAGE_luci
./scripts/config -e CONFIG_PACKAGE_luci-compat
./scripts/config -e CONFIG_PACKAGE_luci-app-opkg
./scripts/config -e CONFIG_LUCI_LANG_zh_Hans

./scripts/config -e CONFIG_PACKAGE_ppp
./scripts/config -e CONFIG_PACKAGE_ppp-mod-pppoe
./scripts/config -e CONFIG_PACKAGE_luci-proto-ppp

./scripts/config -e CONFIG_PACKAGE_luci-app-ssr-plus
./scripts/config -e CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray
./scripts/config -e CONFIG_PACKAGE_xray-core
./scripts/config -e CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client
./scripts/config -e CONFIG_PACKAGE_shadowsocksr-libev-ssr-local
./scripts/config -e CONFIG_PACKAGE_shadowsocksr-libev-ssr-redir

./scripts/config -e CONFIG_PACKAGE_luci-app-turboacc
./scripts/config -e CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_OFFLOADING
./scripts/config -e CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_NFT_FULLCONE
./scripts/config -e CONFIG_PACKAGE_kmod-nft-fullcone

make defconfig

# ---- 自检：打印目标与工具链，确认不是 mips ----
echo "TARGET_SELECTED: $(grep -E '^CONFIG_TARGET_.*=y' .config | xargs)"
ls -d staging_dir/target-* || true
