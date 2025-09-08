#!/bin/bash
# diy-part3.sh —— Guard rust/host（可自动修复）
# 用法：在 workflow 里执行本脚本；通过环境变量控制行为：
#   AUTO_FIX_RUST="true"  # 默认：自动把会触发 rust/host 的包从 .config 里关掉
#   AUTO_FIX_RUST="false" # 仅预检，发现触发就退出（fail-fast）
set -euxo pipefail

: "${AUTO_FIX_RUST:=true}"

echo "=== [DIY3] Guard rust/host (AUTO_FIX_RUST=$AUTO_FIX_RUST) ==="

# 0) 自动定位 OpenWrt 源码根
OWRT_DIR=""
for d in openwrt source lede ImmortalWrt .; do
  if [ -f "$d/include/toplevel.mk" ]; then OWRT_DIR="$d"; break; fi
done
[ -n "$OWRT_DIR" ] || { echo "ERROR: OpenWrt source tree not found"; exit 1; }
echo "[DIY3] OpenWrt tree: $OWRT_DIR"

pushd "$OWRT_DIR" >/dev/null

# 1) 规范配置，生成元数据
make defconfig

# 2) 找出“声明 Build-Depends: rust/host 的包”
awk -v RS='' '/^Package:/ {p=$2} /Build-Depends:.*rust\/host/ {print p}' \
  tmp/.packageinfo | sort -u > /tmp/need_rust.txt || true

echo "[DIY3] Packages declaring rust/host (may be empty):"
cat /tmp/need_rust.txt || true

# 3) 求交集：这些里被你选成 =y 的，就是“会触发 rust/host 的元凶”
comm -12 \
  <(sed -n 's/^CONFIG_PACKAGE_\(.*\)=y/\1/p' .config | sort) \
  /tmp/need_rust.txt > /tmp/enabled_rust.txt || true

if [ -s /tmp/enabled_rust.txt ]; then
  echo "❌ Found packages enabled (=y) that would trigger rust/host:"
  cat /tmp/enabled_rust.txt

  if [ "$AUTO_FIX_RUST" = "true" ]; then
    echo "[DIY3] Auto-fixing: turn them off in .config ..."
    while read -r p; do
      [ -n "$p" ] && sed -i "s/^CONFIG_PACKAGE_${p}=y/# CONFIG_PACKAGE_${p} is not set/" .config || true
    done < /tmp/enabled_rust.txt

    make defconfig

    # 再验一遍，确认干净
    comm -12 \
      <(sed -n 's/^CONFIG_PACKAGE_\(.*\)=y/\1/p' .config | sort) \
      /tmp/need_rust.txt > /tmp/enabled_rust_again.txt || true

    if [ -s /tmp/enabled_rust_again.txt ]; then
      echo "✗ Still enabled after auto-fix (please fix manually):"
      cat /tmp/enabled_rust_again.txt
      exit 1
    fi

    # 清理 rust 残留目录，避免误触
    make package/feeds/packages/rust/clean || true
    rm -rf build_dir/target-*_*/host/rustc-* 2>/dev/null || true

    echo "✓ Auto-fix done. No packages will trigger rust/host now."
  else
    echo "✗ Guard-only mode: failing early. Disable these or开启AUTO_FIX_RUST。"
    exit 1
  fi
else
  echo "✅ No enabled packages trigger rust/host."
fi

# 4) 打印一点有用的调试信息
echo ">>> Direct upstream of rust/host target (for debugging):"
make -rpn | awk '/^package\/feeds\/packages\/rust\/host\/compile:/,/^$/' | sed -n '1,40p' || true

# 5) 展示 dnsmasq / rust 相关最终 diffconfig（可选）
./scripts/diffconfig.sh | egrep -i 'dnsmasq|rust|tuic|shadow-tls' || true

popd >/dev/null
echo "=== [DIY3] Done ==="
