#!/bin/bash
# diy-part2.sh —— 运行于 feeds install 之后
set -euxo pipefail

echo "=== [DIY2] Start ==="

# 0) 自动定位 OpenWrt 源码根
OWRT_DIR=""
for d in openwrt source lede ImmortalWrt .; do
  if [ -f "$d/include/toplevel.mk" ]; then OWRT_DIR="$d"; break; fi
done
[ -n "$OWRT_DIR" ] || { echo "ERROR: OpenWrt source tree not found"; exit 1; }
echo "[DIY2] OpenWrt tree: $OWRT_DIR"

# 1) 合并 overlay：仓库根 files/ -> $OWRT_DIR/files/
SRC_FILES="${GITHUB_WORKSPACE:-$(pwd)}/files"
if [ -d "$SRC_FILES" ]; then
  mkdir -p "$OWRT_DIR/files"
  rsync -a --delete --info=name0 "$SRC_FILES"/ "$OWRT_DIR/files"/
fi

# 2) 移除已知循环依赖/会搅局的包（按需增减）
BAD_PKGS=(
  luci-app-fchomo luci-app-homeproxy nikki
  momo luci-app-momo luci-app-alist
  # geoview 如暂不用也一起删
  geoview
)
for name in "${BAD_PKGS[@]}"; do
  find "$OWRT_DIR/feeds" "$OWRT_DIR/package" -type d -name "$name" -prune -exec rm -rf {} + 2>/dev/null || true
done

# 3) 只保留 dnsmasq-full，避免撞车
CFG="$OWRT_DIR/.config"; touch "$CFG"
sed -i 's/\r$//' "$CFG"; sed -i '1s/^\xEF\xBB\xBF//' "$CFG" || true
sed -i -r 's/^CONFIG_([A-Za-z0-9_]+)\s+is not set/# CONFIG_\1 is not set/' "$CFG" || true
sed -i 's/^CONFIG_DEFAULT_dnsmasq=y/# CONFIG_DEFAULT_dnsmasq is not set/' "$CFG" || true
sed -i 's/^CONFIG_PACKAGE_dnsmasq=y/# CONFIG_PACKAGE_dnsmasq is not set/' "$CFG" || true
sed -i 's/^CONFIG_PACKAGE_dnsmasq-dhcpv6=y/# CONFIG_PACKAGE_dnsmasq-dhcpv6 is not set/' "$CFG" || true
grep -q '^CONFIG_PACKAGE_dnsmasq-full=y' "$CFG" || echo 'CONFIG_PACKAGE_dnsmasq-full=y' >> "$CFG"
sed -i 's/^CONFIG_PACKAGE_yggdrasil=y/# CONFIG_PACKAGE_yggdrasil is not set/' ./.config
sed -i 's/^CONFIG_PACKAGE_luci-proto-yggdrasil=y/# CONFIG_PACKAGE_luci-proto-yggdrasil is not set/' ./.config
sed -i 's/^CONFIG_PACKAGE_yggdrasil-jumper=y/# CONFIG_PACKAGE_yggdrasil-jumper is not set/' ./.config

# 4) 关闭一切会触发 Rust 的包 + LuCI 包含项
RUST_TRIGGERS=(tuic-client tuic-server shadow-tls
  shadowsocks-rust-sslocal shadowsocks-rust-ssserver shadowsocks-rust-ssmanager
  ripgrep fd bat eza zoxide naiveproxy yggdrasil brook restic-rest-server dtndht external-protocol)
for k in "${RUST_TRIGGERS[@]}"; do
  sed -i "s/^CONFIG_PACKAGE_${k}=y/# CONFIG_PACKAGE_${k} is not set/" "$CFG" || true
done
sed -i '
  s/^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust=y/# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust is not set/;
  s/^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_TUIC=y/# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_TUIC is not set/;
  s/^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadow_TLS=y/# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadow_TLS is not set/;
' "$CFG" || true

# 5) 应用 patches/*.patch（有则用）
PATCH_DIR="${GITHUB_WORKSPACE:-$(pwd)}/patches"
if ls "$PATCH_DIR"/*.patch >/dev/null 2>&1; then
  pushd "$OWRT_DIR" >/dev/null
  for p in "$PATCH_DIR"/*.patch; do
    git am --3way "$p" || { git am --abort || true; git apply --reject --whitespace=fix "$p"; }
  done
  popd >/dev/null
fi

# 6) 规范化配置并二次拦截 rust 触发源
pushd "$OWRT_DIR" >/dev/null
make defconfig

NEED_RUST=$(awk -v RS='' '/^Package:/ {pkg=$2} /Build-Depends:.*rust\/host/ {print pkg}' tmp/.packageinfo | sort -u || true)
if [ -n "${NEED_RUST:-}" ]; then
  while read -r p; do
    [ -n "$p" ] || continue
    sed -i "s/^CONFIG_PACKAGE_${p}=y/# CONFIG_PACKAGE_${p} is not set/" ".config" || true
  done <<<"$NEED_RUST"
  make defconfig
fi

# 7) 清理 rust 残留
make package/feeds/packages/rust/clean || true
rm -rf build_dir/target-*_*/host/rustc-* 2>/dev/null || true

./scripts/diffconfig.sh | egrep -i 'dnsmasq|rust|tuic|shadow-tls' || true
popd >/dev/null
echo "=== [DIY2] Done ==="
