<div align="center">

# MoonBit 样例

用 [MoonBit](https://www.moonbitlang.com) 写的
[AnyEasier](https://github.com/anyeasier/AnyEasier) 官方样例插件。

![版本](https://img.shields.io/badge/版本-0.1.0-blue)
![许可证](https://img.shields.io/badge/许可证-MIT-blue)
![插件 ID](https://img.shields.io/badge/插件%20ID-anyeasier.moonbit--sample-informational)
![平台](https://img.shields.io/badge/平台-Windows%20·%20macOS%20·%20Linux-lightgrey)
![语言](https://img.shields.io/badge/语言-MoonBit%20%2B%20Rust-000000)

</div>

---

这个插件本身是个功能演示台：一个输入框和八个按钮，每个按钮触发一种插件能力。
它真正的用途是**当参考实现读**——MoonBit 插件从源码到 `main.wasm`
要经过哪些层，这里全都有。

## 插件演示了什么

| 按钮 | 演示的能力 |
| --- | --- |
| 回显 | 缓存控件事件的值，再用 `set-value` 写回界面 |
| 计数 | 用结构体的 `mut` 字段保存跨事件状态 |
| 写日志 | `Action::Log` 的多个级别 |
| 运行命令 | 跨平台命令（Windows 用 `cmd /C echo`，其他平台用 `echo`），平台从 `init` 的 `meta` 判断 |
| 取消 | `KillCommand(handle)` 与 `KillLastCommand` 两种取消方式 |
| 定时器 | `SetTimer` 每 500ms 触发，三次后 `ClearTimer` |
| 弹窗 | `ShowMessage` |
| 数据区 | `DataWrite` 写入插件沙箱目录 |

声明的权限只有 `allow_programs: ["cmd", "echo"]`，不要文件权限，不联网。

## 安装

在 AnyEasier 的插件商店里搜"示例插件"直接装，或者下载
[Release](https://github.com/anyeasier/AnyEasierSamplePlugin/releases) 里的
`plugin.zip`，用商店页的"从本地 ZIP 安装"。

## 架构

MoonBit 目前只能编译出裸 wasm 模块，产不出 WASI 组件。
所以这个插件是**两个组件合成**的：

```text
pkg/main.wasm  =  wasm-tools compose(
    ① bridge/   Rust adapter（wit-bindgen，target wasm32-wasip2）
                export anyeasier:plugin/guest
                import anyeasier:plugin/host + anyeasier:mb/bridge
    ② core/ + logic/ + sdk/   MoonBit 编译出的裸模块，组件化后
                export anyeasier:mb/bridge
)
```

两侧通过 MoonBit 线性内存里两段固定偏移的缓冲区通信，接口是一组全标量函数
（`alloc` / `write-u32` / `buf-len` / `read-u32` / `init` / `on-event` / …）。
WIT 类型在 adapter 里翻译成 JSON 跨过这道边界。

分层职责：

| 目录 | 职责 | 改插件时要动吗 |
| --- | --- | --- |
| `logic/` | 纯业务逻辑，实现 `@sdk.Plugin` | **要**，这是你唯一需要经常改的地方 |
| `sdk/` | 事件/动作类型与 JSON 序列化（来自 [plugin-sdk-moonbit](https://github.com/anyeasier/plugin-sdk-moonbit)） | 一般不动 |
| `core/` | ABI 边界：内联 WAT 访问线性内存，导出 `moon_*` 函数 | 不动 |
| `bridge/` | Rust adapter：WIT ↔ JSON 翻译，**零业务逻辑** | 不动 |

adapter 零业务逻辑是刻意的设计：换插件只改 MoonBit 侧，adapter 原样复用。
这也是 [`aep new`](https://github.com/anyeasier/aep-cli) 能把整个 `bridge/`
当模板拷过去的原因。

`bridge/src/bin/fix-exports.rs` 存在的原因：moonc 的 `#export_name` 只允许
C 风格符号，而 WIT 的规范导出名形如 `anyeasier:mb/bridge#alloc`
（含 `:` `#` `-`）。这个工具在构建期给 `moon_*` 短名追加一份规范名导出。

## 构建

```bash
./build.sh
```

前置依赖：`moon`、Rust + `wasm32-wasip2` target、`wasm-tools`、PowerShell（打 zip 用）。

六步：`moon test` → 编译 MoonBit → 规范化导出名 → 组件化 → 编译 adapter →
`wasm-tools compose` 并打包成 `dist/moonbit-sample.zip`。

用 [`aep`](https://github.com/anyeasier/aep-cli) 更省事，它还带热重载：

```bash
aep check      # 校验
aep test       # moon test
aep build      # 产出 dist/plugin.zip
aep dev        # 监听源码，增量重建
```

> 发布到 Release 时资产名必须改成 **`plugin.zip`**（全小写）——
> 商店按这个名字查找。`build.sh` 产出的是 `dist/moonbit-sample.zip`。

## 测试

```bash
moon test
```

19 个用例：`sdk/serde_test.mbt` 7 个（JSON 序列化往返与特殊字符），
`logic/plugin_test.mbt` 12 个（每个按钮与事件路径）。

logic 的测试是**纯函数测试**——直接构造 SDK 对象调 `handle_event`，
不需要 wasm 运行时，也不需要主程序。这是"事件进、动作出"这个模型的好处。

## 配合主程序开发

```bash
ANYEASIER_PLUGIN_DEV="/绝对路径/AnyEasierSamplePlugin" cargo tauri dev
```

主程序会发现根目录有 `manifest.json` 但没有 `main.wasm`、而 `pkg/` 下两者都有，
自动切到 `pkg/`。之后每 500 毫秒轮询产物，变了就自动重载。
配合 `aep dev` 就是完整的"改代码 → 几秒后界面刷新"循环。

## 仓库布局

```text
├── manifest.json  ui.xml  README.md    商店 Raw 预览约定：必须在 main 分支根目录
├── build.sh                            构建脚本
├── moon.mod  moon.pkg
├── logic/  sdk/  core/  bridge/        见上面的分层表
├── pkg/                                打包取料区（manifest / ui.xml / README / main.wasm）
└── dist/                               构建产物（gitignore）
```

根目录的 `manifest.json` / `ui.xml` / `README.md` 与 `pkg/` 下的副本内容相同。
根目录那份是给商店 Raw 预览用的，`pkg/` 那份是打进 zip 的。
**改了一份要同步另一份。**

## 文档

| | |
| --- | --- |
| [MoonBit 插件教程](https://github.com/anyeasier/AnyEasier/blob/main/docs/plugin-development/07-moonbit-plugins.md) | SDK 用法、示例、能力缺口 |
| [插件开发教程](https://github.com/anyeasier/AnyEasier/blob/main/docs/plugin-development/README.md) | 从零写一个插件 |
| [插件 API 参考](https://github.com/anyeasier/AnyEasier/blob/main/docs/api/README.md) | WIT 接口、清单、界面格式 |

## 贡献

这个仓库是 `aep new` 模板的来源，所以改动要考虑"被当成脚手架拷走"的后果：

- 改 `bridge/wit/deps/plugin/plugin-world.wit` 要与主仓库的
  `crates/anye-host/wit/plugin-world.wit` 保持一致（**没有自动守护**，靠人工）
- 改 `sdk/` 要同步 [plugin-sdk-moonbit](https://github.com/anyeasier/plugin-sdk-moonbit)
  与 `aep-cli` 模板里的副本
- 改内存布局常量要三处同步：`core/abi.mbt`、`core/moon.pkg` 的
  `heap-start-address`、`bridge/abi-constants.json`（`aep` 会门禁检查后两者与第一处的一致性）
- 改 `logic/plugin.mbt` 的控件 id 要同步 `ui.xml`（两份）与 `plugin_test.mbt`

已知待办：`bridge/Cargo.toml` 里还留着 `wasmi` 依赖和旧架构的 description
（现行实现用 wit-bindgen + compose，不跑解释器）；没有 CI，发布全靠本地脚本加手动上传。

## 许可证

[MIT](LICENSE)

## 相关

- [AnyEasier](https://github.com/anyeasier/AnyEasier) — 主程序
- [plugin-sdk-moonbit](https://github.com/anyeasier/plugin-sdk-moonbit) — MoonBit 插件 SDK
- [aep-cli](https://github.com/anyeasier/aep-cli) — 插件开发工具
- [registry](https://github.com/anyeasier/registry) — 中央插件注册表
