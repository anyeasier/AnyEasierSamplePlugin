# AnyEasierSamplePlugin（MoonBit 样例插件）

用 [MoonBit](https://www.moonbitlang.com/) 编写 AnyEasier 插件的完整示范。

## 架构

AnyEasier 插件是 WASI 组件（wasm32-wasip2 / Component Model），而 MoonBit
当前（moon 0.1.2026.08）尚无组件目标——只能编译到**裸 wasm 模块**。本项目
用一层极薄的 Rust adapter 打通：

```
┌─────────────────────────────────────────────┐
│  main.wasm（WASI 组件，manifest 声明的插件） │
│                                             │
│  Rust adapter（wit-bindgen 实现 guest）      │
│    ├─ WIT guest 导出：init/on-event/…        │
│    ├─ WIT host 导入：log/ui_get/fs/…         │
│    └─ wasmi 解释器 ── 内嵌 MoonBit 裸模块     │
│         ├─ 导出 moon_init/moon_on_event/…    │
│         └─ 导入 "anyeasier" 模块（host 桥）   │
└─────────────────────────────────────────────┘
```

- **业务逻辑 100% MoonBit**（`logic/` 包）：事件 JSON → 动作 JSON，纯逻辑
  可单测（fake bridge 注入，`moon test` 全绿）。
- **core/ 包**：ABI 边界。MoonBit 通过 `extern "wasm"` 内联 WAT 访问自己的
  线性内存，实现共享缓冲协议（`moon_alloc` / `moon_buf_ptr` / `moon_buf_len`）
  和宿主导入绑定（`"anyeasier" "log"` 等）。
- **bridge/（Rust adapter）**：`include_bytes!` 内嵌 MoonBit 裸模块，用
  wasmi 实例化，把 WIT 类型 ↔ JSON、host 接口 ↔ "anyeasier" 导入桥接起来。
  它不含任何插件业务逻辑，换一个插件只需重写 MoonBit 侧。

## ABI 协议（core ↔ adapter）

- 请求：adapter 调 `moon_alloc(n)` 得基址 → 写 `[len:u32 LE][payload]` →
  调 `moon_init` / `moon_on_event` / `moon_validate` / `moon_destroy`（无参）。
- 应答：adapter 调 `moon_buf_ptr()` / `moon_buf_len()` 读取 `[len][payload]`。
- `moon_init` 的 payload：`[cfgLen:u32][metaLen:u32][cfg][meta]`。
- 宿主导入（MoonBit → adapter）：字符串经 MoonBit scratch 区按
  `(ptr, len)` 传址；「返回字符串」的导入由 adapter 把结果写进 MoonBit
  内存（临时 grow 的页），并把 `(ptr, len)` 写到 MoonBit 提供的 out 参数区；
  `ui_get` 无值时 len 置 `0xFFFFFFFF`。

## 构建

依赖：moon、Rust（wasm32-wasip2 target）、PowerShell（打 zip）。

```bash
./build.sh          # 产出 dist/moonbit-sample.zip
```

然后在 AnyEasier 商店页「从本地 ZIP 安装」。

## 测试

```bash
moon test           # logic 包 14 个用例（fake bridge）
```

## 目录

```
logic/   插件业务逻辑（纯 MoonBit，可测）
core/    ABI 边界（内联 WAT 内存原语 + 宿主导入绑定 + guest 导出）
bridge/  Rust adapter（wasmi + wit-bindgen，无业务逻辑）
pkg/     插件包静态文件（manifest.json / ui.xml / README.md）
```
