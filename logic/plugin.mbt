///|
/// 插件业务逻辑：事件 JSON → 动作 JSON 数组。
///
/// 本包是「用 MoonBit 写 AnyEasier 插件」的示范核心：纯函数、无宿主依赖、
/// 可被 `moon test` 直接覆盖。与 adapter 的协议：
///
/// 事件（adapter → MoonBit，一次一个 JSON）：
///   {"type":"ui-ready"}
///   {"type":"control","id":"...","event":"click|input|change","value":"..."}
///   {"type":"command-finished","handle":1,"exitCode":0,"stdout":"...","stderr":"...","timedOut":false}
///   {"type":"timer","id":1}
///   {"type":"config-changed","config":"{...}"}
///
/// 动作（MoonBit → adapter，数组；adapter 翻译为 WIT action / host 调用）：
///   {"type":"set-value","id":"...","value":"..."}
///   {"type":"set-enabled","id":"...","enabled":true}
///   {"type":"log","level":"info","message":"..."}
///   {"type":"run-command","options":{...command-options JSON...}}
///   {"type":"kill-command","handle":1}          // handle 可省略 = 取消最近命令
///   {"type":"show-message","kind":"info","title":"...","text":"..."}
///   {"type":"set-timer","id":1,"intervalMs":500,"repeat":true}
///   {"type":"clear-timer","id":1}
///   {"type":"data-write","path":"...","text":"..."}
///   {"type":"close"}

///| 日志级别（与 WIT enum log-level 对应）。
pub enum LogLevel {
  Debug
  Info
  Warn
  Error
} derive(Eq, Show)

///| 演示计数按钮的内部状态。
let click_count : Ref[Int] = Ref(0)

///| 定时器滴答计数。
let tick_count : Ref[Int] = Ref(0)

///| 最近一次命令的 handle（command-finished 事件带回，用于取消）。
let running_handle : Ref[Int] = Ref(-1)

///| 控件值缓存：每次 control 事件的 value 即该控件最新值（事件驱动范式）。
let control_values : Ref[Map[String, String]] = Ref(Map::new())

///| 插件配置（config-changed 时缓存）。
let plugin_config : Ref[String] = Ref("{}")

///|
/// 事件入口（JSON 字符串 → 动作 JSON 数组字符串）。
/// MoonBit 逻辑出错时返回空数组并写日志动作，保证 UI 不因插件异常而卡死。
pub fn handle_event(evt_json : String) -> String {
  handle_event_impl(evt_json) catch {
    err => {
      Json::array([
        log_action(Error, "异常：\{err}｜输入长度 \{evt_json.length()}｜内容：\{evt_json}"),
      ]).stringify()
    }
  }
}

///|
fn handle_event_impl(evt_json : String) -> String raise {
  let evt = @json.parse(evt_json)
  guard evt is Object(fields)
  guard fields.get("type") is Some(Json::String(kind))
  let actions : Array[Json] = match kind {
    "ui-ready" => on_ui_ready()
    "control" => on_control(fields)
    "command-finished" => on_command_finished(fields)
    "timer" => on_timer(fields)
    "config-changed" => on_config_changed(fields)
    _ => []
  }
  Json::array(actions).stringify()
}

///|
fn on_ui_ready() -> Array[Json] {
  [
    action_set_value("status", "MoonBit 插件就绪"),
    log_action(Info, "moonbit-sample 就绪（platform=\{cached_platform.val}）"),
  ]
}

///|
fn on_control(fields : Map[String, Json]) -> Array[Json] raise {
  guard fields.get("id") is Some(Json::String(id))
  guard fields.get("event") is Some(Json::String(event))
  let value = json_str(fields.get("value"))
  // 事件驱动缓存：本次事件的 value 就是该控件的最新值
  control_values.val[id] = value
  match (id, event) {
    ("echoBtn", "click") => {
      let text = match control_values.val.get("echoInput") {
        Some(v) => v
        None => "(未输入)"
      }
      [action_set_value("status", "回显：\{text}")]
    }
    ("echoInput", "input") => [action_set_value("status", "输入中：\{value}")]
    ("countBtn", "click") => {
      click_count.val += 1
      [action_set_value("status", "已点击 \{click_count.val} 次")]
    }
    ("logBtn", "click") => [
      log_action(Info, "这是一条来自 MoonBit 的 Info 日志"),
      log_action(Warn, "这是一条 Warn 日志"),
    ]
    ("cmdBtn", "click") => {
      // 运行命令：echo 一段文本（依赖 manifest allow_programs）
      let (prog, args) = if cached_platform.val == "windows" {
        ("cmd", ["/C", "echo", "hello-from-moonbit"])
      } else {
        ("echo", ["hello-from-moonbit"])
      }
      let options : Json = {
        "program": prog,
        "args": Json::array([for a in args => Json::string(a)]),
        "cwd": Json::null(),
        "env": Json::array([]),
        "timeoutMs": Json::number(10_000.0),
        "stdin": Json::null(),
      }
      [
        { "type": "run-command", "options": options },
        action_set_value("status", "命令运行中…"),
        action_set_enabled("cmdBtn", false),
        action_set_enabled("cancelBtn", true),
      ]
    }
    ("cancelBtn", "click") => {
      let kill : Json = if running_handle.val >= 0 {
        { "type": "kill-command", "handle": Json::number(running_handle.val.to_double()) }
      } else {
        { "type": "kill-command" } // 无 handle = 取消最近命令（adapter 补齐）
      }
      [kill, action_set_value("status", "已请求取消")]
    }
    ("timerBtn", "click") => {
      tick_count.val = 0
      [
        action_set_value("status", "定时器启动（500ms × 3）"),
        { "type": "set-timer", "id": Json::number(7.0), "intervalMs": Json::number(500.0), "repeat": Json::boolean(true) },
      ]
    }
    ("msgBtn", "click") => [
      {
        "type": "show-message",
        "kind": Json::string("info"),
        "title": Json::string("来自 MoonBit"),
        "text": Json::string("show-message 动作工作正常"),
      },
    ]
    ("dataBtn", "click") => {
      let text = "moonbit-data-\{click_count.val}"
      [
        { "type": "data-write", "path": Json::string("sample/state.txt"), "text": Json::string(text) },
        action_set_value("status", "已写入数据区：\{text}"),
      ]
    }
    _ => []
  }
}

///|
fn on_command_finished(fields : Map[String, Json]) -> Array[Json] {
  let exit_code = json_int(fields.get("exitCode"))
  let stdout = json_str(fields.get("stdout"))
  let stderr = json_str(fields.get("stderr"))
  running_handle.val = json_int(fields.get("handle"))
  let status_text = if exit_code == 0 {
    "命令完成：\{stdout.trim()}"
  } else {
    "命令失败（exit=\{exit_code}）\{stderr.trim()}"
  }
  [
    action_set_value("status", status_text),
    action_set_enabled("cmdBtn", true),
    action_set_enabled("cancelBtn", false),
  ]
}

///|
fn on_timer(fields : Map[String, Json]) -> Array[Json] {
  let id = json_int(fields.get("id"))
  if id != 7 {
    return []
  }
  tick_count.val += 1
  if tick_count.val >= 3 {
    [
      action_set_value("status", "定时器完成：滴答 3 次"),
      { "type": "clear-timer", "id": Json::number(7.0) },
    ]
  } else {
    [action_set_value("status", "定时器滴答 \{tick_count.val}/3")]
  }
}

///|
fn on_config_changed(fields : Map[String, Json]) -> Array[Json] {
  let config = json_str(fields.get("config"))
  plugin_config.val = config
  [log_action(Info, "配置已更新：\{config}")]
}

// ---- 动作构造 helper（pub 供其他插件作者参考复用）----

///|
pub fn action_set_value(id : String, value : String) -> Json {
  { "type": "set-value", "id": Json::string(id), "value": Json::string(value) }
}

///|
pub fn action_set_enabled(id : String, enabled : Bool) -> Json {
  { "type": "set-enabled", "id": Json::string(id), "enabled": Json::boolean(enabled) }
}

///|
pub fn log_action(level : LogLevel, message : String) -> Json {
  let lv = match level {
    Debug => "debug"
    Info => "info"
    Warn => "warn"
    Error => "error"
  }
  { "type": "log", "level": Json::string(lv), "message": Json::string(message) }
}

///|
fn json_int(v : Json?) -> Int {
  match v {
    Some(Json::Number(n)) => n.to_int()
    _ => 0
  }
}

///|
fn json_str(v : Json?) -> String {
  match v {
    Some(Json::String(s)) => s
    _ => ""
  }
}

///|
/// 配置校验（moon_validate 调用）：配置必须是合法 JSON 对象。
/// 返回 None 表示合法，Some(错误文本) 表示不合法。
pub fn validate_config(config : String) -> String? {
  try {
    let v = @json.parse(config)
    guard v is Object(_)
    else {
      return Some("配置必须是 JSON 对象")
    }
  } catch {
    err => return Some("配置不是合法 JSON：\{err}")
  }
  None
}

///|
/// 默认配置。
pub fn default_config() -> String {
  let v : Json = { "count": Json::number(0.0), "greeting": Json::string("你好，AnyEasier") }
  v.stringify()
}

///| 平台（moon_init 从 meta JSON 缓存）。
let cached_platform : Ref[String] = Ref("windows")

///|
pub fn set_platform(p : String) -> Unit {
  cached_platform.val = p
}
