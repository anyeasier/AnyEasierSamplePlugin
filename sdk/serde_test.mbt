// AnyEasier MoonBit Plugin SDK - 序列化单元测试

test "parse_event ui-ready" {
  let evt = parse_event("{\"type\":\"ui-ready\"}")
  inspect(evt, content="UiReady")
}

test "parse_event control with normal and special characters" {
  // 普通 control 事件
  let evt1 = parse_event("{\"type\":\"control\",\"id\":\"btn1\",\"event\":\"click\",\"value\":\"\"}")
  inspect(evt1, content=(
    #|Control({id: btn1, event: click, value: })
  ))

  // 特殊字符：引号、中文、换行、反斜杠转义
  let json_special = "{\"type\":\"control\",\"id\":\"input_test\",\"event\":\"input\",\"value\":\"你好，\\\"AnyEasier\\\"！\\n第二行\\\\路径\"}"
  let evt2 = parse_event(json_special)
  match evt2 {
    Control(ce) => {
      inspect(ce.id, content="input_test")
      inspect(ce.event, content="input")
      inspect(ce.value, content="你好，\"AnyEasier\"！\n第二行\\路径")
    }
    _ => fail("expected Control event")
  }
}

test "parse_event command-finished" {
  let evt = parse_event("{\"type\":\"command-finished\",\"handle\":5,\"exitCode\":0,\"stdout\":\"output text\\nline2\",\"stderr\":\"\",\"timedOut\":false}")
  match evt {
    CommandFinished(cr) => {
      inspect(cr.handle, content="5")
      inspect(cr.exit_code, content="0")
      inspect(cr.stdout, content="output text\nline2")
      inspect(cr.timed_out, content="false")
    }
    _ => fail("expected CommandFinished")
  }
}

test "parse_event http-response & dialog-result & timer & config-changed" {
  let e_timer = parse_event("{\"type\":\"timer\",\"id\":42}")
  inspect(e_timer, content="Timer(id=42)")

  let e_cfg = parse_event("{\"type\":\"config-changed\",\"config\":\"{\\\"key\\\":\\\"val\\\"}\"}")
  inspect(e_cfg, content=(
    #|ConfigChanged(config={"key":"val"})
  ))

  let e_dialog = parse_event("{\"type\":\"dialog-result\",\"id\":1,\"path\":\"C:\\\\test\\\\file.txt\",\"canceled\":false}")
  inspect(e_dialog, content=(
    #|DialogResult({id: 1, path: Some(C:\test\file.txt), canceled: false})
  ))

  let e_dialog_cancel = parse_event("{\"type\":\"dialog-result\",\"id\":2,\"canceled\":true}")
  inspect(e_dialog_cancel, content="DialogResult({id: 2, path: None, canceled: true})")
}

test "parse_event unknown type and malformed fields" {
  let r_unknown = try {
    let _ = parse_event("{\"type\":\"future-event-type\"}")
    "ok"
  } catch {
    UnknownEventType(t) => "unknown:\{t}"
    _ => "other"
  }
  inspect(r_unknown, content="unknown:future-event-type")

  let r_invalid_json = try {
    let _ = parse_event("not-a-json")
    "ok"
  } catch {
    InvalidEventJson(_) => "invalid-json"
    _ => "other"
  }
  inspect(r_invalid_json, content="invalid-json")
}

test "render_actions roundtrip with special characters" {
  let actions : Array[Action] = [
    SetValue(id="status", value="包含 \"引号\" 和 \n换行 和 中文"),
    SetEnabled(id="btn1", enabled=false),
    SetVisible(id="box1", visible=true),
    SetOptions(id="select1", options=["选项一", "Option \"2\"", "Line\n3"]),
    Log(level=Info, message="日志测试：\"引用\" 与 \\反斜杠"),
    RunCommand(CommandOptions::new("cmd", args=["/C", "echo", "你好 \"world\""], timeout_ms=Some(5000))),
    KillLastCommand,
    KillCommand(handle=10),
    ShowMessage(kind=Warn, title="警告", text="内容包含\n换行"),
    SetTimer(id=7, interval_ms=500, repeat=true),
    ClearTimer(id=7),
    DataWrite(path="data/test.txt", text="保存内容：\"json\" 字符串"),
    Close,
  ]

  let rendered = render_actions(actions)
  // 验证渲染的 JSON 是否能被合法解析
  let parsed = try {
    @json.parse(rendered)
  } catch {
    err => fail("render_actions output is not valid json: \{err}")
  }
  guard parsed is Array(arr) else {
    fail("expected JSON array")
  }
  inspect(arr.length(), content="13")

  // 重点验证特殊字符在 JSON 反序列化后完全一致
  match arr[0] {
    Object(fields) => {
      inspect(fields.get("type"), content=(
        #|Some(String(set-value))
      ))
      inspect(fields.get("id"), content=(
        #|Some(String(status))
      ))
      inspect(fields.get("value"), content=(
        #|Some(String(包含 "引号" 和 
        #|换行 和 中文))
      ))
    }
    _ => fail("expected object for action 0")
  }

  match arr[3] {
    Object(fields) => {
      inspect(fields.get("type"), content=(
        #|Some(String(set-options))
      ))
      match fields.get("options") {
        Some(Array(opts)) => {
          inspect(opts.length(), content="3")
          inspect(opts[1], content=(
            #|String(Option "2")
          ))
        }
        _ => fail("expected array of options")
      }
    }
    _ => fail("expected object for action 3")
  }
}

test "parse_meta extraction" {
  let meta_json = "{\"api_version\":\"0.1\",\"app_version\":\"0.2.0\",\"platform\":\"linux\"}"
  let meta = parse_meta(meta_json)
  inspect(meta.api_version, content="0.1")
  inspect(meta.app_version, content="0.2.0")
  inspect(meta.platform, content="linux")

  let empty_meta = parse_meta("{}")
  inspect(empty_meta.api_version, content="0.1")
  inspect(empty_meta.app_version, content="0.1.0")
  inspect(empty_meta.platform, content="windows")
}
