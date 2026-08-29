#!/usr/bin/env bash
# AnyEasierSamplePlugin 打包脚本：
#   MoonBit 逻辑（wasm 模块）→ 组件化 → Rust adapter（wasm32-wasip2 组件）
#   → wasm-tools compose 合并 → plugin.zip
#
# 依赖：moon、Rust（含 wasm32-wasip2 target）、wasm-tools、PowerShell
set -euo pipefail
cd "$(dirname "$0")"

WASMTIME_HOST=${WASMTIME_HOST:-x86_64-pc-windows-msvc}

echo "── 1/6 MoonBit 单测 ─────────────────────────────"
moon test

echo "── 2/6 构建 MoonBit 裸模块（wasm）───────────────"
moon -C core build --target wasm
# 重命名导出为 WIT canonical 名（moonc 的 #export_name 限 C 符号）
(cd bridge && cargo run --release --bin fix-exports -- \
  ../_build/wasm/debug/build/core/core.wasm ../_build/moon-renamed.wasm)

echo "── 3/6 组件化 MoonBit 模块（embed + new）────────"
wasm-tools component embed bridge/wit-mb/ _build/moon-renamed.wasm \
  -o _build/moon-embedded.wasm
wasm-tools component new _build/moon-embedded.wasm -o _build/moon-component.wasm
echo "   moon-component.wasm: $(wc -c < _build/moon-component.wasm) bytes"

echo "── 4/6 构建 Rust adapter（wasm32-wasip2 组件）───"
(cd bridge && cargo build --target wasm32-wasip2 --release)
cp -f bridge/target/wasm32-wasip2/release/moonbit_adapter.wasm _build/adapter.wasm
echo "   adapter.wasm: $(wc -c < _build/adapter.wasm) bytes"

echo "── 5/6 compose：adapter + MoonBit 组件 ──────────"
wasm-tools compose _build/adapter.wasm -d _build/moon-component.wasm -o pkg/main.wasm
echo "   main.wasm: $(wc -c < pkg/main.wasm) bytes"
wasm-tools component wit pkg/main.wasm | head -3

echo "── 6/6 打包 plugin.zip ──────────────────────────"
mkdir -p dist
rm -f dist/moonbit-sample.zip
powershell -NoProfile -Command \
  "Compress-Archive -Force -Path 'pkg/manifest.json','pkg/ui.xml','pkg/README.md','pkg/main.wasm' -DestinationPath 'dist/moonbit-sample.zip'"
echo "   dist/moonbit-sample.zip: $(wc -c < dist/moonbit-sample.zip) bytes"

echo "✅ 打包完成：dist/moonbit-sample.zip（在 AnyEasier 商店页「从本地 ZIP 安装」）"
