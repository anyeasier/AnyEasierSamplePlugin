// SamplePlugin 单元测试：纯 SDK 对象驱动测试，无任何 JSON 手拼

test "ui-ready 返回就绪状态与日志动作" {
  let plugin = SamplePlugin::new()
  let actions = plugin.handle_event(event=UiReady)
  inspect(actions.length(), content="2")
  match actions[0] {
    SetValue(id~, value~) => {
      inspect(id, content="status")
      inspect(value, content="MoonBit 插件就绪")
    }
    _ => fail("expected SetValue action")
  }
}

test "echoInput 输入缓存 + echoBtn 回显" {
  let plugin = SamplePlugin::new()
  let _ = plugin.handle_event(event=Control({ id: "echoInput", event: "input", value: "你好 MoonBit" }))
  let actions = plugin.handle_event(event=Control({ id: "echoBtn", event: "click", value: "" }))
  inspect(actions.length(), content="1")
  match actions[0] {
    SetValue(id~, value~) => {
      inspect(id, content="status")
      inspect(value, content="回显：你好 MoonBit")
    }
    _ => fail("expected SetValue action")
  }
}

test "countBtn 累加计数" {
  let plugin = SamplePlugin::new()
  let _ = plugin.handle_event(event=Control({ id: "countBtn", event: "click", value: "" }))
  let actions = plugin.handle_event(event=Control({ id: "countBtn", event: "click", value: "" }))
  inspect(actions.length(), content="1")
  match actions[0] {
    SetValue(id~, value~) => {
      inspect(id, content="status")
      inspect(value, content="已点击 2 次")
    }
    _ => fail("expected SetValue action")
  }
}

test "cmdBtn 生成 RunCommand 动作并切换按钮状态" {
  let plugin = SamplePlugin::new()
  let actions = plugin.handle_event(event=Control({ id: "cmdBtn", event: "click", value: "" }))
  inspect(actions.length(), content="4")
  match actions[0] {
    RunCommand(opts) => {
      inspect(opts.program, content="cmd")
      inspect(opts.args.length(), content="3")
    }
    _ => fail("expected RunCommand action")
  }
  match actions[2] {
    SetEnabled(id~, enabled~) => {
      inspect(id, content="cmdBtn")
      inspect(enabled, content="false")
    }
    _ => fail("expected SetEnabled(cmdBtn, false)")
  }
}

test "cancelBtn 无 handle 时发 KillLastCommand" {
  let plugin = SamplePlugin::new()
  let actions = plugin.handle_event(event=Control({ id: "cancelBtn", event: "click", value: "" }))
  inspect(actions.length(), content="2")
  match actions[0] {
    KillLastCommand => ()
    _ => fail("expected KillLastCommand action")
  }
}

test "command-finished 恢复按钮并展示 stdout" {
  let plugin = SamplePlugin::new()
  let actions = plugin.handle_event(event=CommandFinished({
    handle: 3,
    exit_code: 0,
    stdout: "hello",
    stderr: "",
    timed_out: false,
  }))
  inspect(actions.length(), content="3")
  match actions[0] {
    SetValue(id~, value~) => {
      inspect(id, content="status")
      inspect(value, content="命令完成：hello")
    }
    _ => fail("expected SetValue action")
  }
}

test "timer 三次滴答后 ClearTimer" {
  let plugin = SamplePlugin::new()
  let _ = plugin.handle_event(event=Control({ id: "timerBtn", event: "click", value: "" }))
  let a1 = plugin.handle_event(event=Timer(id=7))
  let a2 = plugin.handle_event(event=Timer(id=7))
  let a3 = plugin.handle_event(event=Timer(id=7))

  match a1[0] {
    SetValue(value~, ..) => inspect(value, content="定时器滴答 1/3")
    _ => fail("expected SetValue")
  }
  match a2[0] {
    SetValue(value~, ..) => inspect(value, content="定时器滴答 2/3")
    _ => fail("expected SetValue")
  }
  inspect(a3.length(), content="2")
  match a3[1] {
    ClearTimer(id~) => inspect(id, content="7")
    _ => fail("expected ClearTimer action")
  }
}

test "dataBtn 生成 DataWrite 动作" {
  let plugin = SamplePlugin::new()
  let actions = plugin.handle_event(event=Control({ id: "dataBtn", event: "click", value: "" }))
  inspect(actions.length(), content="2")
  match actions[0] {
    DataWrite(path~, text~) => {
      inspect(path, content="sample/state.txt")
      inspect(text, content="moonbit-data-0")
    }
    _ => fail("expected DataWrite action")
  }
}

test "未知控件返回空动作数组" {
  let plugin = SamplePlugin::new()
  let actions = plugin.handle_event(event=Control({ id: "unknown_id", event: "click", value: "" }))
  inspect(actions.length(), content="0")
}

test "validate 配置校验" {
  let plugin = SamplePlugin::new()
  inspect(plugin.validate(config="{\"a\":1}"), content="None")
  inspect(plugin.validate(config="[1,2]") is None, content="false")
  inspect(plugin.validate(config="not json") is None, content="false")
}

test "default_config 是合法 JSON" {
  let plugin = SamplePlugin::new()
  let cfg = plugin.default_config()
  guard cfg is Some(json_str) else {
    fail("expected default_config")
  }
  let v = @json.parse(json_str)
  guard v is Object(_) else {
    fail("default_config should be a JSON object")
  }
}

test "set_platform 影响 cmdBtn 的程序选择" {
  let plugin = SamplePlugin::new()
  plugin.set_platform("linux")
  let actions = plugin.handle_event(event=Control({ id: "cmdBtn", event: "click", value: "" }))
  match actions[0] {
    RunCommand(opts) => {
      inspect(opts.program, content="echo")
    }
    _ => fail("expected RunCommand with echo")
  }
}
