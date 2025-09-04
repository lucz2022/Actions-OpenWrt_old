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
cd openwrt

# 找到 small 源里的 mosdns Makefile（路径可能是 feeds/small/mosdns/Makefile）
MOSDNS_MK=$(grep -Rwl --include=Makefile -e '^.*mosdns' feeds 2>/dev/null | head -n1)
if [ -n "$MOSDNS_MK" ]; then
  echo "[patch] Fix mosdns CGO/linkmode in $MOSDNS_MK"
  # 1) 开启 CGO
  sed -i -e 's/\bCGO_ENABLED=0\b/CGO_ENABLED=1/' "$MOSDNS_MK"
  # 2) （可选）如果 Makefile 里硬塞了 -linkmode external，直接去掉
  sed -i -e 's/-linkmode[[:space:]]\+external//g' "$MOSDNS_MK"
fi

# 确保 Go 工具链主机端已准备好
make package/golang/host/compile V=s

make defconfig
