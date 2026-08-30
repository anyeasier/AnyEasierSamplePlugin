// AnyEasier MoonBit Plugin SDK - 序列化与反序列化

///|
/// 解析 adapter 写入请求缓冲的事件 JSON。
pub fn parse_event(json : String) -> Event raise SdkError {
  let v = try {
    @json.parse(json)
  } catch {
    err => raise InvalidEventJson(err.to_string())
  }
  guard v is Object(fields) else {
    raise InvalidEventJson("Event JSON must be an object")
  }
  guard fields.get("type") is Some(Json::String(kind)) else {
    raise MalformedField(path="type", reason="Missing or non-string 'type' field")
  }
  match kind {
    "ui-ready" => Event::UiReady
    "control" => {
      let id = match fields.get("id") {
        Some(Json::String(s)) => s
        _ => raise MalformedField(path="id", reason="Missing or non-string 'id'")
      }
      let event = match fields.get("event") {
        Some(Json::String(s)) => s
        _ => raise MalformedField(path="event", reason="Missing or non-string 'event'")
      }
      let value = match fields.get("value") {
        Some(Json::String(s)) => s
        _ => ""
      }
      Event::Control({ id, event, value })
    }
    "command-finished" => {
      let handle = match fields.get("handle") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      let exit_code = match fields.get("exitCode") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      let stdout = match fields.get("stdout") {
        Some(Json::String(s)) => s
        _ => ""
      }
      let stderr = match fields.get("stderr") {
        Some(Json::String(s)) => s
        _ => ""
      }
      let timed_out = match fields.get("timedOut") {
        Some(Json::True) => true
        Some(Json::False) => false
        _ => false
      }
      Event::CommandFinished({ handle, exit_code, stdout, stderr, timed_out })
    }
    "http-response" => {
      let id = match fields.get("id") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      let status = match fields.get("status") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      let body = match fields.get("body") {
        Some(Json::Array(arr)) => {
          let b_arr : Array[Byte] = Array::make(arr.length(), b'\x00')
          for i = 0; i < arr.length(); i = i + 1 {
            match arr[i] {
              Json::Number(n, ..) => b_arr[i] = n.to_int().to_byte()
              _ => ()
            }
          }
          Bytes::from_array(b_arr[:])
        }
        _ => b""
      }
      Event::HttpResponse({ id, status, body })
    }
    "dialog-result" => {
      let id = match fields.get("id") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      let path = match fields.get("path") {
        Some(Json::String(s)) => Some(s)
        _ => None
      }
      let canceled = match fields.get("canceled") {
        Some(Json::True) => true
        Some(Json::False) => false
        _ => false
      }
      Event::DialogResult({ id, path, canceled })
    }
    "timer" => {
      let id = match fields.get("id") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => raise MalformedField(path="id", reason="Missing or non-number 'id'")
      }
      Event::Timer(id~)
    }
    "config-changed" => {
      let config = match fields.get("config") {
        Some(Json::String(s)) => s
        _ => ""
      }
      Event::ConfigChanged(config~)
    }
    _ => raise UnknownEventType(kind)
  }
}

///|
/// 解析 meta JSON。
pub fn parse_meta(json : String) -> Meta {
  try {
    let v = @json.parse(json)
    guard v is Object(fields) else {
      { api_version: "0.1", app_version: "0.1.0", platform: "windows" }
    }
    let api_version = match fields.get("api_version") {
      Some(Json::String(s)) => s
      _ => "0.1"
    }
    let app_version = match fields.get("app_version") {
      Some(Json::String(s)) => s
      _ => "0.1.0"
    }
    let platform = match fields.get("platform") {
      Some(Json::String(s)) => s
      _ => "windows"
    }
    { api_version, app_version, platform }
  } catch {
    _ => { api_version: "0.1", app_version: "0.1.0", platform: "windows" }
  }
}

///|
/// 序列化动作数组为 JSON 字符串。
pub fn render_actions(actions : Array[Action]) -> String {
  let json_arr : Array[Json] = Array::new(capacity=actions.length())
  for action in actions {
    json_arr.push(render_action(action))
  }
  Json::array(json_arr).stringify()
}

///|
fn render_action(action : Action) -> Json {
  match action {
    SetValue(id~, value~) => {
      "type": Json::string("set-value"),
      "id": Json::string(id),
      "value": Json::string(value),
    }
    SetEnabled(id~, enabled~) => {
      "type": Json::string("set-enabled"),
      "id": Json::string(id),
      "enabled": Json::boolean(enabled),
    }
    SetVisible(id~, visible~) => {
      "type": Json::string("set-visible"),
      "id": Json::string(id),
      "visible": Json::boolean(visible),
    }
    SetOptions(id~, options~) => {
      let opt_arr : Array[Json] = [for o in options => Json::string(o)]
      {
        "type": Json::string("set-options"),
        "id": Json::string(id),
        "options": Json::array(opt_arr),
      }
    }
    Log(level~, message~) => {
      let lv_str = match level {
        Debug => "debug"
        Info => "info"
        Warn => "warn"
        Error => "error"
      }
      {
        "type": Json::string("log"),
        "level": Json::string(lv_str),
        "message": Json::string(message),
      }
    }
    RunCommand(opts) => {
      let args_arr : Array[Json] = [for a in opts.args => Json::string(a)]
      let env_arr : Array[Json] = [
        for pair in opts.env => Json::array([Json::string(pair.0), Json::string(pair.1)])
      ]
      let cwd_val = match opts.cwd {
        Some(c) => Json::string(c)
        None => Json::null()
      }
      let timeout_val = match opts.timeout_ms {
        Some(t) => Json::number(t.to_double())
        None => Json::null()
      }
      let stdin_val = match opts.stdin {
        Some(s) => Json::string(s)
        None => Json::null()
      }
      let opts_json : Json = {
        "program": Json::string(opts.program),
        "args": Json::array(args_arr),
        "cwd": cwd_val,
        "env": Json::array(env_arr),
        "timeoutMs": timeout_val,
        "stdin": stdin_val,
      }
      {
        "type": Json::string("run-command"),
        "options": opts_json,
      }
    }
    KillLastCommand => {
      "type": Json::string("kill-command"),
    }
    KillCommand(handle~) => {
      "type": Json::string("kill-command"),
      "handle": Json::number(handle.to_double()),
    }
    ShowMessage(kind~, title~, text~) => {
      let kind_str = match kind {
        Info => "info"
        Warn => "warn"
        Error => "error"
      }
      {
        "type": Json::string("show-message"),
        "kind": Json::string(kind_str),
        "title": Json::string(title),
        "text": Json::string(text),
      }
    }
    SetTimer(id~, interval_ms~, repeat~) => {
      "type": Json::string("set-timer"),
      "id": Json::number(id.to_double()),
      "intervalMs": Json::number(interval_ms.to_double()),
      "repeat": Json::boolean(repeat),
    }
    ClearTimer(id~) => {
      "type": Json::string("clear-timer"),
      "id": Json::number(id.to_double()),
    }
    DataWrite(path~, text~) => {
      "type": Json::string("data-write"),
      "path": Json::string(path),
      "text": Json::string(text),
    }
    Close => {
      "type": Json::string("close"),
    }
  }
}
