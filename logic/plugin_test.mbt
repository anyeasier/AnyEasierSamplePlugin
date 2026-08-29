///|
/// handle_event 的黑盒测试：覆盖全部按钮分支与状态机。
/// 注意各 test 共享全局状态（click_count 等），断言采用自洽顺序。

///|
test "ui-ready 返回就绪状态与日志动作" {
  let out = handle_event(#|{"type":"ui-ready"}
)
  inspect(out.contains("\"status\""), content="true")
  inspect(out.contains("就绪"), content="true")
  inspect(out.contains("\"log\""), content="true")
}

///|
test "echoInput 输入缓存 + echoBtn 回显" {
  let _ = handle_event(
    #|{"type":"control","id":"echoInput","event":"input","value":"你好 MoonBit"}
)
  let out = handle_event(
    #|{"type":"control","id":"echoBtn","event":"click","value":""}
)
  inspect(out.contains("你好 MoonBit"), content="true")
}

///|
test "countBtn 累加计数" {
  let _ = handle_event(#|{"type":"control","id":"countBtn","event":"click","value":""}
)
  let second = handle_event(
    #|{"type":"control","id":"countBtn","event":"click","value":""}
)
  inspect(second.contains("2 次"), content="true")
}

///|
test "cmdBtn 生成 run-command 动作并切换按钮状态" {
  let out = handle_event(#|{"type":"control","id":"cmdBtn","event":"click","value":""}
)
  inspect(out.contains("\"run-command\""), content="true")
  inspect(out.contains("\"program\":\"cmd\""), content="true")
  inspect(out.contains("\"enabled\":false"), content="true")
}

///|
test "cancelBtn 无 handle 时发空 kill-command" {
  let out = handle_event(
    #|{"type":"control","id":"cancelBtn","event":"click","value":""}
)
  inspect(out.contains("\"kill-command\""), content="true")
  inspect(out.contains("已请求取消"), content="true")
}

///|
test "command-finished 恢复按钮并展示 stdout" {
  let out = handle_event(
    #|{"type":"command-finished","handle":3,"exitCode":0,"stdout":"hello","stderr":"","timedOut":false}
)
  inspect(out.contains("hello"), content="true")
  inspect(out.contains("\"set-enabled\""), content="true")
}

///|
test "timer 三次滴答后 clear-timer" {
  let _ = handle_event(#|{"type":"control","id":"timerBtn","event":"click","value":""}
)
  let t1 = handle_event(#|{"type":"timer","id":7}
)
  let t2 = handle_event(#|{"type":"timer","id":7}
)
  let t3 = handle_event(#|{"type":"timer","id":7}
)
  inspect(t1.contains("1/3"), content="true")
  inspect(t2.contains("2/3"), content="true")
  inspect(t3.contains("\"clear-timer\""), content="true")
}

///|
test "dataBtn 生成 data-write 动作" {
  let out = handle_event(#|{"type":"control","id":"dataBtn","event":"click","value":""}
)
  inspect(out.contains("\"data-write\""), content="true")
  inspect(out.contains("sample/state.txt"), content="true")
}

///|
test "非法事件 JSON 返回日志动作" {
  let out = handle_event("not-json")
  inspect(out.contains("\"log\""), content="true")
  inspect(out.contains("异常"), content="true")
}

///|
test "未知控件返回空数组" {
  inspect(
    handle_event(
      #|{"type":"control","id":"nope","event":"click","value":""}
),
    content="[]",
  )
}

///|
test "validate_config 合法与非法" {
  inspect(validate_config("{\"a\":1}"), content="None")
  inspect(validate_config("[1,2]").is_empty(), content="false")
  inspect(validate_config("not json").is_empty(), content="false")
}

///|
test "default_config 是合法 JSON 对象" {
  let v = @json.parse(default_config())
  guard v is Object(_)
  else {
    fail("default_config 应为 JSON 对象")
  }
}

///|
test "set_platform 影响 cmdBtn 的程序选择" {
  set_platform("linux")
  let out = handle_event(#|{"type":"control","id":"cmdBtn","event":"click","value":""}
)
  inspect(out.contains("\"program\":\"echo\""), content="true")
  set_platform("windows")
}
