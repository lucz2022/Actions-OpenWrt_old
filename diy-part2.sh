#!/bin/bash
# ================================================
# diy-part2.sh  —— OpenWrt 二次配置（feeds 安装后执行）
# 1) 锁定 x86_64
# 2) 禁用 mosdns
# 3) 禁用 shadowsocks-libev 全家（避免 PCRE1 依赖链）
# 4) 启用 ucode / ucode-mod-digest
# 5) make defconfig 展开依赖
# 6) 守卫：检查是否误拉回 ss-libev（默认只告警；STRICT_GUARD=1 时中断）
# ================================================

set -eux

# 如果当前目录不是 openwrt/，且存在 openwrt/ 目录，则切进去
[ -d openwrt ] && cd openwrt

# 确保存在 .config（如果你在上一步把 openwrt.config 拷到 openwrt/.config，这里就会直接用）
[ -f .config ] || touch .config

echo "[diy2] Lock target to x86_64"
# 1) 只保留 x86_64 目标，清理历史目标项
sed -i '/^CONFIG_TARGET_/d' .config
cat >> .config <<'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
EOF

echo "[diy2] Disable mosdns and its menu include"
# 2) 关闭 mosdns（部分环境会编译失败）
sed -i '/^CONFIG_PACKAGE_mosdns[ =]/d;/^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_MosDNS[ =]/d' .config
cat >> .config <<'EOF'
# CONFIG_PACKAGE_mosdns is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_MosDNS is not set
EOF

echo "[diy2] Hard-disable shadowsocks-libev family to avoid PCRE1 chain"
# 3) 明确禁用 SS-libev（不要和 SSRR 混淆）
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

echo "[diy2] Ensure ucode & ucode-mod-digest present"
# 4) 一些插件（如 homeproxy 等）需要 ucode + ucode-mod-digest
sed -i '/^CONFIG_PACKAGE_ucode/d;/^CONFIG_PACKAGE_ucode-mod-digest/d' .config
cat >> .config <<'EOF'
CONFIG_PACKAGE_ucode=y
CONFIG_PACKAGE_ucode-mod-digest=y
EOF

# 5) 展开依赖
echo "[diy2] make defconfig..."
make defconfig

# 6) 守卫（检查最终 .config 是否真的启用了 ss-libev；默认仅告警，不中断）
STRICT_GUARD="${STRICT_GUARD:-0}"  # 环境变量设为 1 可改为严格模式
if grep -Eq '^(CONFIG_PACKAGE_shadowsocks-libev(-[a-z0-9_]+)?=y|CONFIG_PACKAGE_shadowsocks-libev(-[a-z0-9_]+)?=m)' .config; then
  echo "[diy2][WARNING] shadowsocks-libev **已被启用**，很可能被某个面板(feed)联动拉入。"
  echo "[diy2][WARNING] 请关闭 passwall/ssr-plus/bypass 中的 INCLUDE_Shadowsocks_Libev* 选项，或移除相应 feed。"
  if [ "$STRICT_GUARD" = "1" ]; then
    echo "[diy2][ERROR] STRICT_GUARD=1，终止构建。"
    exit 1
  fi
fi

echo "[diy2] Done."
