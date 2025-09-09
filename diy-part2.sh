#!/usr/bin/env bash
set -euo pipefail

echo "=== [DIY2] Start ==="

# --- 定位 OpenWrt 源树 ---
OWRT_DIR=""
for d in openwrt source lede ImmortalWrt .; do
  [ -f "$d/include/toplevel.mk" ] && OWRT_DIR="$d" && break
done
[ -n "$OWRT_DIR" ] || { echo "[ERR] OpenWrt tree not found"; exit 1; }
echo "[DIY2] OpenWrt tree: $OWRT_DIR"
cd "$OWRT_DIR"

CFG="./.config"
touch "$CFG"
# 规范换行与去 BOM（防止“missing separator”）
sed -i 's/\r$//' "$CFG" || true
sed -i '1s/^\xEF\xBB\xBF//' "$CFG" || true
# 把 “is not set” 统一成注释行（兼容 sed 开关）
sed -i -r 's/^CONFIG_([A-Za-z0-9_]+)\s+is not set/# CONFIG_\1 is not set/' "$CFG"

# --- 可选：清掉一些第三方问题包（你遇到循环依赖的那批）---
BAD_PKGS=(luci-app-fchomo luci-app-homeproxy nikki momo luci-app-momo luci-app-alist geoview)
for name in "${BAD_PKGS[@]}"; do
  find ./feeds ./package -type d -name "$name" -prune -exec rm -rf '{}' + || true
done

# --- Helper：开/关包 ---
enable_pkg() {
  local p="$1"
  sed -i "s/^#\? *CONFIG_PACKAGE_${p} is not set/CONFIG_PACKAGE_${p}=y/" "$CFG"
  grep -q "^CONFIG_PACKAGE_${p}=y" "$CFG" || echo "CONFIG_PACKAGE_${p}=y" >> "$CFG"
}
disable_pkg() {
  local p="$1"
  sed -i -E "s/^CONFIG_PACKAGE_${p}=y/# CONFIG_PACKAGE_${p} is not set/" "$CFG"
  sed -i -E "s/^CONFIG_PACKAGE_${p}=m/# CONFIG_PACKAGE_${p} is not set/" "$CFG"
}

# --- 固定 x86_64 目标与输出镜像类型 ---
# 清除旧的 target/device 选择，避免多目标冲突
sed -i '/^CONFIG_TARGET_[^_]\+=y/d' "$CFG"
sed -i '/^CONFIG_TARGET_[A-Za-z0-9_]\+_DEVICE_.*=y/d' "$CFG"

cat >>"$CFG" <<'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y

# 输出镜像类型
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_IMAGES_GZIP=y
# 如需 zstd 更快体积更小，可改用：
# CONFIG_TARGET_IMAGES_ZSTD=y

CONFIG_GRUB_IMAGES=y        # BIOS 启动镜像 (combined.img)
CONFIG_GRUB_EFI_IMAGES=y    # UEFI 启动镜像 (combined-efi.img)
CONFIG_ISO_IMAGES=y         # ISO
CONFIG_VMDK_IMAGES=y        # VMDK

# 分区大小（按需调整）
CONFIG_TARGET_KERNEL_PARTSIZE=64
CONFIG_TARGET_ROOTFS_PARTSIZE=512
EOF

# --- Clash 运行所需（fw4/nft/tproxy 路线）---
for p in \
  kmod-tun \
  kmod-nft-nat kmod-nft-tproxy kmod-nft-socket \
  firewall4 ip-full iptables-nft \
  dnsmasq-full ca-bundle ca-certificates \
  curl wget-ssl unzip coreutils-nohup bash
do
  enable_pkg "$p"
done

# --- I226(igc) 直通 & VirtIO 桥接：网卡驱动全开 ---
for p in kmod-igc kmod-e1000e kmod-igb kmod-r8169 kmod-virtio kmod-virtio-pci kmod-virtio-net; do
  enable_pkg "$p"
done
# 若有独立瑞昱 2.5G 网卡，再开：
# enable_pkg kmod-r8125

# --- 统一用 dnsmasq-full，避免冲突 ---
sed -i 's/^CONFIG_DEFAULT_dnsmasq=y/# CONFIG_DEFAULT_dnsmasq is not set/' "$CFG"
sed -i 's/^CONFIG_PACKAGE_dnsmasq=y/# CONFIG_PACKAGE_dnsmasq is not set/' "$CFG"
sed -i 's/^CONFIG_PACKAGE_dnsmasq-dhcpv6=y/# CONFIG_PACKAGE_dnsmasq-dhcpv6 is not set/' "$CFG"
grep -q '^CONFIG_PACKAGE_dnsmasq-full=y' "$CFG" || echo 'CONFIG_PACKAGE_dnsmasq-full=y' >> "$CFG"

# 可按需开启 dnsmasq-full 功能模块（你之前用过的）
for f in auth conntrack dhcp dhcpv6 dnssec noid tftp; do
  echo "CONFIG_PACKAGE_dnsmasq_full_${f}=y" >> "$CFG"
done

# --- 关掉会触发 rust/host 或不需要的实现 ---
# 常见 rust/host 触发者（以及一些你不需要的代理实现）
must_off=(
  naiveproxy tuic-client tuic-server shadow-tls
  shadowsocks-rust-sslocal shadowsocks-rust-ssserver shadowsocks-rust-ssmanager
  brook yggdrasil luci-proto-yggdrasil yggdrasil-jumper
  restic-rest-server dtndht external-protocol
  ripgrep fd bat eza zoxide
)
for p in "${must_off[@]}"; do disable_pkg "$p"; done

# 一些 LuCI 选项会“选择”到 rust 方案（防止被自动勾上）
sed -i '
  s/^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust=y/# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust is not set/;
  s/^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_TUIC=y/# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_TUIC is not set/;
  s/^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadow_TLS=y/# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadow_TLS is not set/;
' "$CFG"

# --- 可选：立即跑一次 defconfig 并按 metadata 自动关掉一切 rust/host 触发（更保险） ---
# 说明：这步会生成 tmp/.packageinfo；若不想在 DIY2 里跑，也可依赖 workflow 的 Fail-fast 步骤。
make defconfig
NEED_RUST=$(awk -v RS='' '/^Package:/ {p=$2} /Build-Depends:.*rust\/host/ {print p}' tmp/.packageinfo | sort -u || true)
if [ -n "$NEED_RUST" ]; then
  echo "[DIY2] Packages declaring rust/host:"
  echo "$NEED_RUST"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    disable_pkg "$p" || true
  done <<< "$NEED_RUST"
fi

# 再来一次 defconfig，使关包生效
make defconfig

# 调试输出（可选）
echo "---- diffconfig ----"
./scripts/diffconfig.sh || true
echo "=== [DIY2] Done ==="
