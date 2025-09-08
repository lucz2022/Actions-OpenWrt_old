#!/bin/bash
set -euxo pipefail
cd openwrt

# 删循环依赖的第三方包
rm -rf feeds/*/*/luci-app-fchomo feeds/*/*/luci-app-homeproxy \
       feeds/*/*/nikki feeds/*/*/momo feeds/*/*/luci-app-momo \
       feeds/*/*/luci-app-alist || true

# 禁用所有会触发 Rust 的包（避免 rust/host 在 CI 报 panic）
for k in shadowsocks-rust-sslocal shadowsocks-rust-ssserver shadowsocks-rust-ssmanager \
         shadow-tls tuic-client tuic-server ripgrep fd bat eza zoxide; do
  sed -i "s/^CONFIG_PACKAGE_${k}=y/# CONFIG_PACKAGE_${k} is not set/" .config || true
done

# 只用 dnsmasq-full
sed -i 's/^CONFIG_DEFAULT_dnsmasq=y/# CONFIG_DEFAULT_dnsmasq is not set/' .config || true
sed -i 's/^CONFIG_PACKAGE_dnsmasq=.*/# CONFIG_PACKAGE_dnsmasq is not set/' .config || true
sed -i 's/^CONFIG_PACKAGE_dnsmasq-dhcpv6=.*/# CONFIG_PACKAGE_dnsmasq-dhcpv6 is not set/' .config || true
grep -q '^CONFIG_PACKAGE_dnsmasq-full=y' .config || echo 'CONFIG_PACKAGE_dnsmasq-full=y' >> .config

# 应用你仓库的 patch 集（如果有）
for p in "$GITHUB_WORKSPACE"/patches/*.patch; do
  [ -e "$p" ] || continue
  git am --3way "$p" || { git am --abort || true; git apply "$p"; }
done

# 追加 overlay（可选）
# cp -a "$GITHUB_WORKSPACE/files/." files/ || true

# 规范配置
make defconfig
