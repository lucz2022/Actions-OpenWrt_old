# === Clash 运行所需组件（fw4/nft 路线） ===
must_on=(
  kmod-tun
  kmod-nft-nat
  kmod-nft-tproxy
  kmod-nft-socket
  firewall4
  ip-full
  dnsmasq-full
  ca-bundle
  ca-certificates
  curl
  wget-ssl
  unzip
  coreutils-nohup
  bash
  iptables-nft
)

for p in "${must_on[@]}"; do
  sed -i "s/^#\? *CONFIG_PACKAGE_${p} is not set/CONFIG_PACKAGE_${p}=y/" "$CFG"
  grep -q "^CONFIG_PACKAGE_${p}=y" "$CFG" || echo "CONFIG_PACKAGE_${p}=y" >> "$CFG"
done

# 关掉会拉 rust/host 或不需要的实现
must_off=(
  naiveproxy tuic-client tuic-server shadow-tls
  shadowsocks-rust-sslocal shadowsocks-rust-ssserver shadowsocks-rust-ssmanager
  brook yggdrasil luci-proto-yggdrasil yggdrasil-jumper
  restic-rest-server dtndht external-protocol
)
for p in "${must_off[@]}"; do
  sed -i -E "s/^CONFIG_PACKAGE_${p}=y/# CONFIG_PACKAGE_${p} is not set/" "$CFG"
  sed -i -E "s/^CONFIG_PACKAGE_${p}=m/# CONFIG_PACKAGE_${p} is not set/" "$CFG"
done

# 避免基础版 dnsmasq 与 full 冲突
sed -i 's/^CONFIG_DEFAULT_dnsmasq=y/# CONFIG_DEFAULT_dnsmasq is not set/' "$CFG"
sed -i 's/^CONFIG_PACKAGE_dnsmasq=y/# CONFIG_PACKAGE_dnsmasq is not set/' "$CFG"
sed -i 's/^CONFIG_PACKAGE_dnsmasq-dhcpv6=y/# CONFIG_PACKAGE_dnsmasq-dhcpv6 is not set/' "$CFG"
grep -q '^CONFIG_PACKAGE_dnsmasq-full=y' "$CFG" || echo 'CONFIG_PACKAGE_dnsmasq-full=y' >> "$CFG"
