// AnyEasier MoonBit Plugin SDK - 类型定义

pub const SDK_API_VERSION : String = "0.1"

// ---------- 事件（宿主 → 插件） ----------

pub(all) struct ControlEvent {
  id : String
  event : String // "click" | "input" | "change" | "select" | "submit"
  value : String // 控件当前值（字符串协议，见 spec/XML结构.md）
} derive(Eq, Show, Debug)

pub(all) struct CommandResult {
  handle : Int
  exit_code : Int
  stdout : String
  stderr : String
  timed_out : Bool
} derive(Eq, Show, Debug)

pub(all) struct HttpResult {
  id : Int
  status : Int
  body : Bytes
} derive(Eq, Show, Debug)

pub(all) struct DialogResult {
  id : Int
  path : String?
  canceled : Bool
} derive(Eq, Show, Debug)

pub(all) enum Event {
  UiReady
  Control(ControlEvent)
  CommandFinished(CommandResult)
  HttpResponse(HttpResult)
  DialogResult(DialogResult)
  Timer(id~ : Int)
  ConfigChanged(config~ : String)
} derive(Eq, Show, Debug)

// ---------- 动作（插件 → 宿主） ----------

pub(all) enum LogLevel {
  Debug
  Info
  Warn
  Error
} derive(Eq, Show, Debug)

pub(all) enum MsgKind {
  Info
  Warn
  Error
} derive(Eq, Show, Debug)

pub(all) enum HttpMethod {
  Get
  Post
  Put
  Delete
  Head
} derive(Eq, Show, Debug)

pub(all) struct CommandOptions {
  program : String
  args : Array[String]
  cwd : String?
  env : Array[(String, String)]
  timeout_ms : Int?
  stdin : String?
} derive(Eq, Show, Debug)

pub fn CommandOptions::new(
  program : String,
  args~ : Array[String] = [],
  cwd~ : String? = None,
  env~ : Array[(String, String)] = [],
  timeout_ms~ : Int? = None,
  stdin~ : String? = None
) -> CommandOptions {
  { program, args, cwd, env, timeout_ms, stdin }
}

pub(all) enum Action {
  SetValue(id~ : String, value~ : String)
  SetEnabled(id~ : String, enabled~ : Bool)
  SetVisible(id~ : String, visible~ : Bool)
  SetOptions(id~ : String, options~ : Array[String])
  Log(level~ : LogLevel, message~ : String)
  RunCommand(CommandOptions)
  /// 无 handle 版本：取消最近一次命令（adapter 用内部记录的 handle 填充）
  KillLastCommand
  KillCommand(handle~ : Int)
  ShowMessage(kind~ : MsgKind, title~ : String, text~ : String)
  SetTimer(id~ : Int, interval_ms~ : Int, repeat~ : Bool)
  ClearTimer(id~ : Int)
  /// 扩展动作（adapter 直接执行 host 调用，不经 WIT Action）
  DataWrite(path~ : String, text~ : String)
  Close
} derive(Eq, Show, Debug)

// ---------- 插件契约 ----------

pub(all) struct Meta {
  api_version : String
  app_version : String
  platform : String // "windows" | "macos" | "linux"
} derive(Eq, Show, Debug)

pub(open) trait Plugin {
  init(Self, config~ : String, meta~ : Meta) -> Unit
  handle_event(Self, event~ : Event) -> Array[Action]
  validate(Self, config~ : String) -> String?
  default_config(Self) -> String?
  destroy(Self) -> Unit
}

// ---------- 错误模型 ----------

pub(all) suberror SdkError {
  InvalidEventJson(String)
  UnknownEventType(String)
  UnknownActionType(String)
  MalformedField(path~ : String, reason~ : String)
} derive(Eq, Show, Debug)
