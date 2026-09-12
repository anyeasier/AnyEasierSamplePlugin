# MoonBit 样例

[AnyEasier](https://github.com/anyeasier/AnyEasier) 的官方样例插件，
用 [MoonBit](https://www.moonbitlang.com) 编写。

一个输入框加八个按钮，每个按钮演示一种插件能力。既能当功能演示台用，
也适合当"MoonBit 插件怎么写"的参考实现读。

## 界面上有什么

| 按钮 | 做什么 |
| --- | --- |
| 回显 | 把你输入的内容原样显示在状态栏 |
| 计数 | 每点一次加一，演示跨事件保存状态 |
| 写日志 | 往日志面板写一条 Info 和一条 Warn |
| 运行命令 | 跑一个 `echo` 命令（Windows 上用 `cmd /C echo`），结果显示在状态栏 |
| 取消 | 终止正在运行的命令 |
| 定时器 | 每 500 毫秒触发一次，三次后自动停止 |
| 弹窗 | 弹一个提示框 |
| 数据区 | 往插件自己的沙箱目录写一个文本文件 |

底部的状态栏显示最近一次操作的结果。

## 权限

这个插件申请的权限很少：

- **允许运行的程序**：`cmd`、`echo`（就是上面"运行命令"按钮用的）
- **允许读写的文件**：无
- **允许访问网络**：否

它写入的"数据区"是 AnyEasier 分给每个插件的专属沙箱目录，
不需要额外权限，也碰不到你的其他文件。卸载插件时数据区一并删除。

## 支持的平台

Windows、macOS、Linux。插件本身是 WebAssembly，跨平台；
"运行命令"按钮会按当前系统自动选用 `cmd` 或 `echo`。

## 源码与开发

仓库：[anyeasier/AnyEasierSamplePlugin](https://github.com/anyeasier/AnyEasierSamplePlugin)

架构说明、构建步骤、测试方式都在仓库的 README 里。
想自己写插件，从
[插件开发教程](https://github.com/anyeasier/AnyEasier/blob/main/docs/plugin-development/README.md)
开始——`aep new` 生成的项目就是以这个插件为模板的。

## 已知限制

MoonBit 的插件 SDK 目前只覆盖了宿主能力的一部分，所以这个样例没有演示：

- HTTP 请求
- 文件选择对话框
- 读写任意文件
- 系统密钥链
- 主动保存配置

这些能力用 Rust 写插件时全部可用。完整清单见
[MoonBit 插件教程的能力缺口一节](https://github.com/anyeasier/AnyEasier/blob/main/docs/plugin-development/07-moonbit-plugins.md#当前的能力缺口)。
