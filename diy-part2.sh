#!/usr/bin/env bash
set -e

cd "$GITHUB_WORKSPACE/openwrt"

# 统一关闭会拉入 ss-libev 的可选项（如存在）
sed -i 's/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Client=y/# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Client is not set/' .config || true
sed -i 's/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server=y/# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server is not set/' .config || true

# 二次兜底：显式禁止 ss-libev 家族（若被别的菜单 select 也会被覆盖掉）
cat >> .config <<'EOF'

# CONFIG_PACKAGE_shadowsocks-libev-config is not set
# CONFIG_PACKAGE_shadowsocks-libev-ss-local is not set
# CONFIG_PACKAGE_shadowsocks-libev-ss-redir is not set
# CONFIG_PACKAGE_shadowsocks-libev-ss-rules is not set
# CONFIG_PACKAGE_shadowsocks-libev-ss-server is not set
# CONFIG_PACKAGE_shadowsocks-libev-ss-tunnel is not set
EOF

make defconfig
