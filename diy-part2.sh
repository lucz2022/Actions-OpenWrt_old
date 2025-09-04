#!/bin/bash
# =======================================
# DIY Part2: 定制 .config，禁用 SS-libev
# =======================================

cd openwrt

# 1. 保留要用的后端（SSRR + Xray）
./scripts/config -e PACKAGE_luci-app-ssr-plus
./scripts/config -e PACKAGE_luci-app-ssr-plus_INCLUDE_Xray
./scripts/config -e PACKAGE_xray-core
./scripts/config -e PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client
./scripts/config -e PACKAGE_shadowsocksr-libev-ssr-local
./scripts/config -e PACKAGE_shadowsocksr-libev-ssr-redir

# 2. 强制禁用所有 Shadowsocks-libev 相关
for sym in \
  PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Client \
  PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server \
  PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Client \
  PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Server \
  PACKAGE_luci-app-passwall2_INCLUDE_Shadowsocks_Libev_Client \
  PACKAGE_luci-app-passwall2_INCLUDE_Shadowsocks_Libev_Server \
  PACKAGE_luci-app-bypass_INCLUDE_Shadowsocks_Libev_Client \
  PACKAGE_luci-app-bypass_INCLUDE_Shadowsocks_Libev_Server \
  PACKAGE_shadowsocks-libev \
  PACKAGE_shadowsocks-libev-ss-local \
  PACKAGE_shadowsocks-libev-ss-redir \
  PACKAGE_shadowsocks-libev-ss-server \
  PACKAGE_shadowsocks-libev-ss-tunnel; do
  ./scripts/config -d $sym || true
done

# 3. 展开依赖，保证配置干净
make defconfig

# 4. 清理历史残留（防止编译器继续尝试 build ss-libev）
make package/feeds/packages/shadowsocks-libev/clean V=s || true
rm -rf build_dir/target-*/shadowsocks-libev-*
rm -f staging_dir/target-*/stamp/.package_*shadowsocks-libev*
rm -f tmp/.packageinfo tmp/.config-package.in

# 5. 打印确认
echo "==== Shadowsocks-libev 状态检查 ===="
grep -E 'shadowsocks-libev|INCLUDE_Shadowsocks_Libev' .config || echo "OK: ss-libev 已完全禁用"
