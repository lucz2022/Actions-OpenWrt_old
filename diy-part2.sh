#!/usr/bin/env bash
# diy-part2.sh — 调整最终 .config，禁用易翻车项、锁定 x86_64，补齐必要依赖
# 运行位置：已在 openwrt/ 目录下（workflow 中先 cd openwrt 再执行本脚本）

set -euxo pipefail

# 0) 确保有 .config（前一步 Load custom configuration 已经把 $CONFIG_FILE 移到 .config）
[ -f .config ] || touch .config

echo "==== [diy-part2] START  ===="

############################
# 1) 锁定 x86_64 目标
############################
# 清理原有 TARGET_*，再写入 x86_64 通用设备
sed -i '/^CONFIG_TARGET_/d' .config
cat >> .config <<'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
EOF

############################
# 2) 镜像类型（BIOS/EFI + QCOW2 + ISO + ext4 + squashfs + gzip）
############################
# 不重复添加：先删同名行，再追加所需
sed -i -e '/^CONFIG_TARGET_IMAGES_GZIP/d' \
       -e '/^CONFIG_TARGET_ROOTFS_SQUASHFS/d' \
       -e '/^CONFIG_TARGET_ROOTFS_EXT4FS/d' \
       -e '/^CONFIG_GRUB_IMAGES/d' \
       -e '/^CONFIG_QCOW2_IMAGES/d' \
       -e '/^CONFIG_ISO_IMAGES/d' .config
cat >> .config <<'EOF'
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_GRUB_IMAGES=y
CONFIG_QCOW2_IMAGES=y
CONFIG_ISO_IMAGES=y
EOF

############################
# 3) 基础组件（LuCI + PPPoE）
############################
# 若你在外部 .config 已选，可保留；这里是“兜底确保”
for k in \
  CONFIG_PACKAGE_luci \
  CONFIG_PACKAGE_luci-compat \
  CONFIG_PACKAGE_luci-app-opkg \
  CONFIG_LUCI_LANG_zh_Hans \
  CONFIG_PACKAGE_ppp \
  CONFIG_PACKAGE_ppp-mod-pppoe \
  CONFIG_PACKAGE_luci-proto-ppp
do
  sed -i "/^${k}[ =]/d" .config || true
  echo "${k}=y" >> .config
done

############################
# 4) 代理栈：保留 Xray + SSRR，彻底禁用 SS-libev 与 MosDNS
############################
# 4.1 禁 MosDNS（避免 Go/CGO 构建冲突）
sed -i '/^CONFIG_PACKAGE_mosdns[ =]/d' .config || true
sed -i '/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_MosDNS[ =]/d' .config || true
cat >> .config <<'EOF'
# CONFIG_PACKAGE_mosdns is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_MosDNS is not set
EOF

# 4.2 禁 Shadowsocks-libev 全家（避免老 PCRE1 链接问题）
sed -i '/^CONFIG_PACKAGE_shadowsocks-libev/d' .config || true
sed -i '/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_/d' .config || true
cat >> .config <<'EOF'
# CONFIG_PACKAGE_shadowsocks-libev-config is not set
# CONFIG_PACKAGE_shadowsocks-libev-ss-local is not set
# CONFIG_PACKAGE_shadowsocks-libev-ss-redir is not set
# CONFIG_PACKAGE_shadowsocks-libev-ss-rules is not set
# CONFIG_PACKAGE_shadowsocks-libev-ss-server is not set
# CONFIG_PACKAGE_shadowsocks-libev-ss-tunnel is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Client is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server is not set
EOF

# 4.3 开 Xray + SSRR（客户端）
#    注意：若你只要 Xray，不要 SSRR，可把下面两行关于 shadowsocksr-libev 的打开删掉。
for k in \
  CONFIG_PACKAGE_luci-app-ssr-plus \
  CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray \
  CONFIG_PACKAGE_xray-core \
  CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client \
  CONFIG_PACKAGE_shadowsocksr-libev-ssr-local \
  CONFIG_PACKAGE_shadowsocksr-libev-ssr-redir
do
  sed -i "/^${k}[ =]/d" .config || true
  echo "${k}=y" >> .config
done

############################
# 5) TurboACC（Flow Offload + FullCone）
############################
# 如果用 chenmozhijin/turboacc feed，这里打开 LuCI + OFFLOADING + NFT_FULLCONE
# 若你遇到 fullcone 版本不匹配，可先注释掉 INCLUDE_NFT_FULLCONE 与 kmod-nft-fullcone。
sed -i '/^CONFIG_PACKAGE_luci-app-turboacc[ =]/d' .config || true
sed -i '/^CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_OFFLOADING[ =]/d' .config || true
sed -i '/^CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_NFT_FULLCONE[ =]/d' .config || true
sed -i '/^CONFIG_PACKAGE_kmod-nft-fullcone[ =]/d' .config || true
cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_OFFLOADING=y
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_NFT_FULLCONE=y
CONFIG_PACKAGE_kmod-nft-fullcone=y
EOF

############################
# 6) ucode 生态：homeproxy 等会依赖 ucode-mod-digest
############################
sed -i '/^CONFIG_PACKAGE_ucode[ =]/d' .config || true
sed -i '/^CONFIG_PACKAGE_ucode-mod-digest[ =]/d' .config || true
cat >> .config <<'EOF'
CONFIG_PACKAGE_ucode=y
CONFIG_PACKAGE_ucode-mod-digest=y
EOF

############################
# 7) 展开默认，自动补齐依赖
############################
make defconfig

############################
# 8) 守卫：确认 ss-libev 没被其它包“联动”拉入
############################
if [ -f tmp/.config-package.in ]; then
  if grep -R -E '(^| )PACKAGE_shadowsocks-libev' tmp/.config-package.in | grep -qv 'is not set' ; then
    echo "ERROR: ss-libev 被 feed 选上了；请检查 passwall/bypass/ssr-plus 的 INCLUDE_Shadowsocks_Libev* 选项或第三方 feed 冲突。"
    exit 1
  fi
fi

echo "==== [diy-part2] DONE  ===="
