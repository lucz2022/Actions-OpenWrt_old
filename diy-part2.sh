#!/bin/bash
# ================================================
# diy-part2.sh
# 用于 OpenWrt 编译：调整配置、禁用不需要的包、补充依赖
# ================================================

set -eux
cd openwrt

# 确保存在 .config
[ -f .config ] || touch .config

# 1) 锁定 x86_64 目标
sed -i '/^CONFIG_TARGET_/d' .config
cat >> .config <<'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
EOF

# 2) 关闭 mosdns（避免编译失败）
sed -i '/^CONFIG_PACKAGE_mosdns[ =]/d;/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_MosDNS[ =]/d' .config
cat >> .config <<'EOF'
# CONFIG_PACKAGE_mosdns is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_MosDNS is not set
EOF

# 3) 禁用 shadowsocks-libev 全家（防止拉入 PCRE1）
sed -i '/^CONFIG_PACKAGE_shadowsocks-libev/d;/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_/d' .config
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

# 4) 确保 ucode 与 ucode-mod-digest 存在（homeproxy 需要）
sed -i '/^CONFIG_PACKAGE_ucode/d;/^CONFIG_PACKAGE_ucode-mod-digest/d' .config
cat >> .config <<'EOF'
CONFIG_PACKAGE_ucode=y
CONFIG_PACKAGE_ucode-mod-digest=y
EOF

# 5) 自动补全依赖
make defconfig

# 6) 守卫：确认 ss-libev 没被其它 feed 联动拉回来
if grep -R -E 'PACKAGE_shadowsocks-libev' tmp/.config-package.in | grep -qv 'is not set'; then
  echo "ERROR: ss-libev 被 feed 强制启用，请关闭 passwall/ssr-plus/bypass 里的 INCLUDE_Shadowsocks_Libev*"
  exit 1
fi
