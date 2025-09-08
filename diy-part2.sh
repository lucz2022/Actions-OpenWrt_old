#!/bin/bash
# diy-part2.sh —— 运行于 feeds install 之后
set -euxo pipefail

echo "=== [DIY2] Start ==="
echo "[DIY2] PWD=$(pwd)"
command -v date >/dev/null && date || true

# ---------- 0) 自动定位 OpenWrt 源码根 ----------
OWRT_DIR=""
for d in openwrt source lede ImmortalWrt .; do
  if [ -f "$d/include/toplevel.mk" ]; then OWRT_DIR="$d"; break; fi
done
if [ -z "$OWRT_DIR" ]; then
  echo "ERROR: OpenWrt source tree not found (include/toplevel.mk)"; exit 1
fi
echo "[DIY2] OpenWrt tree: $OWRT_DIR"

# ---------- 1) 合并 overlay: 仓库根的 files/ -> $OWRT_DIR/files/ ----------
SRC_FILES="${GITHUB_WORKSPACE:-$(pwd)}/files"
if [ -d "$SRC_FILES" ]; then
  echo "[DIY2] Merging overlay from: $SRC_FILES"
  mkdir -p "$OWRT_DIR/files"
  # 保留权限与时间戳
  rsync -a --delete --info=name0 "$SRC_FILES"/ "$OWRT_DIR/files"/
else
  echo "[DIY2] No overlay 'files/' found. Skip."
fi

# ---------- 2) 清除已知存在循环依赖/不稳定的第三方包 ----------
# 可按需增删
BAD_PKGS=(
  luci-app-fchomo luci-app-homeproxy nikki
  momo luci-app-momo luci-app-alist
  # geoview 如暂不用，也可去掉；用就注释掉这一项
  # geoview
)
echo "[DIY2] Removing problematic packages if present: ${BAD_PKGS[*]}"
for name in "${BAD_PKGS[@]}"; do
  # 在 feeds 与 package 树中查找并删除
  find "$OWRT_DIR/feeds" "$OWRT_DIR/package" -type d -name "$name" -prune -exec rm -rf {} + 2>/dev/null || true
done

# ---------- 3) 规范 .config 并修复常见写法错误 ----------
CFG="$OWRT_DIR/.config"
touch "$CFG"  # 若不存在则创建
# 去 Windows 回车与 BOM
sed -i 's/\r$//' "$CFG" || true
sed -i '1s/^\xEF\xBB\xBF//' "$CFG" || true
# 把 “CONFIG_FOO is not set” 错误写法修成合法注释
sed -i -r 's/^CONFIG_([A-Za-z0-9_]+)\s+is not set/# CONFIG_\1 is not set/' "$CFG" || true
sed -i -r 's/^CONFIG_([A-Za-z0-9_]+)=\s*is not set/# CONFIG_\1 is not set/' "$CFG" || true

# ---------- 4) 只保留 dnsmasq-full，避免撞车 ----------
# 先关默认与基础版，再开 full
sed -i 's/^CONFIG_DEFAULT_dnsmasq=y/# CONFIG_DEFAULT_dnsmasq is not set/' "$CFG" || true
sed -i 's/^CONFIG_PACKAGE_dnsmasq=y/# CONFIG_PACKAGE_dnsmasq is not set/' "$CFG" || true
sed -i 's/^CONFIG_PACKAGE_dnsmasq-dhcpv6=y/# CONFIG_PACKAGE_dnsmasq-dhcpv6 is not set/' "$CFG" || true
grep -q '^CONFIG_PACKAGE_dnsmasq-full=y' "$CFG" || echo 'CONFIG_PACKAGE_dnsmasq-full=y' >> "$CFG"

# ---------- 5) 关闭一切会触发 Rust 的包（CI/本地都省心） ----------
# 包括常见 CLI 工具；按需补充
RUST_TRIGGERS=(
  tuic-client tuic-server shadow-tls
  shadowsocks-rust-sslocal shadowsocks-rust-ssserver shadowsocks-rust-ssmanager
  ripgrep fd bat eza zoxide
)
for k in "${RUST_TRIGGERS[@]}"; do
  sed -i "s/^CONFIG_PACKAGE_${k}=y/# CONFIG_PACKAGE_${k} is not set/" "$CFG" || true
done
# 一些 LuCI/合集里的包含项（名称可能随版本浮动，这里覆盖常见写法）
sed -i '
  s/^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust=y/# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust is not set/;
  s/^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_TUIC=y/# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_TUIC is not set/;
  s/^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadow_TLS=y/# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadow_TLS is not set/;
' "$CFG" || true

# ---------- 6) 应用补丁：支持 patches/*.patch ----------
PATCH_DIR="${GITHUB_WORKSPACE:-$(pwd)}/patches"
if ls "$PATCH_DIR"/*.patch >/dev/null 2>&1; then
  echo "[DIY2] Applying patches from $PATCH_DIR"
  pushd "$OWRT_DIR" >/dev/null
  for p in "$PATCH_DIR"/*.patch; do
    echo "[DIY2]  -> $p"
    # 优先 git am（三方合并），失败则退回 git apply
    git am --3way "$p" || { git am --abort || true; git apply --reject --whitespace=fix "$p"; }
  done
  popd >/dev/null
else
  echo "[DIY2] No patches to apply."
fi

# ---------- 7) 规范化配置，生成最新依赖图 ----------
pushd "$OWRT_DIR" >/dev/null
make defconfig

# ---------- 8) 二次防御：若仍有人声明 Build-Depends: rust/host，则强制关掉 ----------
NEED_RUST=$(awk -v RS='' '
  /^Package:/ {pkg=$2} /Build-Depends:.*rust\/host/ {print pkg}
' tmp/.packageinfo | sort -u || true)
if [ -n "${NEED_RUST:-}" ]; then
  echo "[DIY2] Packages that declare rust/host: $(echo "$NEED_RUST" | xargs echo || true)"
  while read -r p; do
    [ -n "$p" ] || continue
    sed -i "s/^CONFIG_PACKAGE_${p}=y/# CONFIG_PACKAGE_${p} is not set/" ".config" || true
  done <<<"$NEED_RUST"
  make defconfig
fi

# ---------- 9) 清理 rust 残留（若之前编过） ----------
make package/feeds/packages/rust/clean || true
rm -rf build_dir/target-*_*/host/rustc-* 2>/dev/null || true

# ---------- 10) 打印关键检查点 ----------
echo "[DIY2] diffconfig (dnsmasq & rust related):"
./scripts/diffconfig.sh | egrep -i 'dnsmasq|rust|tuic|shadow-tls' || true

popd >/dev/null
echo "=== [DIY2] Done ==="
