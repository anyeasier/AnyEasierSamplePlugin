// 插件业务逻辑：实现 @sdk.Plugin trait

pub struct SamplePlugin {
  mut click_count : Int
  mut tick_count : Int
  mut running_handle : Int
  control_values : Map[String, String]
  mut cached_platform : String
}

pub fn SamplePlugin::new() -> SamplePlugin {
  {
    click_count: 0,
    tick_count: 0,
    running_handle: -1,
    control_values: Map::new(),
    cached_platform: "windows",
  }
}

pub fn SamplePlugin::set_platform(self : SamplePlugin, p : String) -> Unit {
  self.cached_platform = p
}

pub impl @sdk.Plugin for SamplePlugin with init(self : SamplePlugin, config~ : String, meta~ : @sdk.Meta) -> Unit {
  let _ = config
  self.cached_platform = meta.platform
}

pub impl @sdk.Plugin for SamplePlugin with handle_event(self : SamplePlugin, event~ : @sdk.Event) -> Array[@sdk.Action] {
  match event {
    @sdk.Event::UiReady => [
      @sdk.Action::SetValue(id="status", value="MoonBit 插件就绪"),
      @sdk.Action::Log(level=Info, message="moonbit-sample 就绪（platform=\{self.cached_platform}）"),
    ]
    @sdk.Event::Control(ce) => self.on_control(ce)
    @sdk.Event::CommandFinished(r) => {
      self.running_handle = r.handle
      let status_text = if r.exit_code == 0 {
        "命令完成：\{r.stdout.trim()}"
      } else {
        "命令失败（exit=\{r.exit_code}）\{r.stderr.trim()}"
      }
      [
        @sdk.Action::SetValue(id="status", value=status_text),
        @sdk.Action::SetEnabled(id="cmdBtn", enabled=true),
        @sdk.Action::SetEnabled(id="cancelBtn", enabled=false),
      ]
    }
    @sdk.Event::Timer(id=7) => self.on_timer()
    @sdk.Event::ConfigChanged(config~) => [
      @sdk.Action::Log(level=Info, message="配置已更新：\{config}"),
    ]
    _ => []
  }
}

fn SamplePlugin::on_control(self : SamplePlugin, ce : @sdk.ControlEvent) -> Array[@sdk.Action] {
  self.control_values.set(ce.id, ce.value)
  match (ce.id, ce.event) {
    ("echoBtn", "click") => {
      let text = match self.control_values.get("echoInput") {
        Some(v) => v
        None => "(未输入)"
      }
      [@sdk.Action::SetValue(id="status", value="回显：\{text}")]
    }
    ("echoInput", "input") => [
      @sdk.Action::SetValue(id="status", value="输入中：\{ce.value}"),
    ]
    ("countBtn", "click") => {
      self.click_count += 1
      [@sdk.Action::SetValue(id="status", value="已点击 \{self.click_count} 次")]
    }
    ("logBtn", "click") => [
      @sdk.Action::Log(level=Info, message="这是一条来自 MoonBit 的 Info 日志"),
      @sdk.Action::Log(level=Warn, message="这是一条 Warn 日志"),
    ]
    ("cmdBtn", "click") => {
      let (prog, args) = if self.cached_platform == "windows" {
        ("cmd", ["/C", "echo", "hello-from-moonbit"])
      } else {
        ("echo", ["hello-from-moonbit"])
      }
      let options = @sdk.CommandOptions::new(
        prog,
        args~,
        timeout_ms=Some(10_000),
      )
      [
        @sdk.Action::RunCommand(options),
        @sdk.Action::SetValue(id="status", value="命令运行中…"),
        @sdk.Action::SetEnabled(id="cmdBtn", enabled=false),
        @sdk.Action::SetEnabled(id="cancelBtn", enabled=true),
      ]
    }
    ("cancelBtn", "click") => {
      let kill = if self.running_handle >= 0 {
        @sdk.Action::KillCommand(handle=self.running_handle)
      } else {
        @sdk.Action::KillLastCommand
      }
      [kill, @sdk.Action::SetValue(id="status", value="已请求取消")]
    }
    ("timerBtn", "click") => {
      self.tick_count = 0
      [
        @sdk.Action::SetValue(id="status", value="定时器启动（500ms × 3）"),
        @sdk.Action::SetTimer(id=7, interval_ms=500, repeat=true),
      ]
    }
    ("msgBtn", "click") => [
      @sdk.Action::ShowMessage(
        kind=Info,
        title="来自 MoonBit",
        text="show-message 动作工作正常",
      ),
    ]
    ("dataBtn", "click") => {
      let text = "moonbit-data-\{self.click_count}"
      [
        @sdk.Action::DataWrite(path="sample/state.txt", text~),
        @sdk.Action::SetValue(id="status", value="已写入数据区：\{text}"),
      ]
    }
    _ => []
  }
}

fn SamplePlugin::on_timer(self : SamplePlugin) -> Array[@sdk.Action] {
  self.tick_count += 1
  if self.tick_count >= 3 {
    [
      @sdk.Action::SetValue(id="status", value="定时器完成：滴答 3 次"),
      @sdk.Action::ClearTimer(id=7),
    ]
  } else {
    [@sdk.Action::SetValue(id="status", value="定时器滴答 \{self.tick_count}/3")]
  }
}

pub impl @sdk.Plugin for SamplePlugin with validate(self : SamplePlugin, config~ : String) -> String? {
  let _ = self
  try {
    let v = @json.parse(config)
    guard v is Object(_) else {
      return Some("配置必须是 JSON 对象")
    }
  } catch {
    err => return Some("配置不是合法 JSON：\{err}")
  }
  None
}

pub impl @sdk.Plugin for SamplePlugin with default_config(self : SamplePlugin) -> String? {
  let _ = self
  Some("{\"count\":0,\"greeting\":\"你好，AnyEasier\"}")
}

pub impl @sdk.Plugin for SamplePlugin with destroy(self : SamplePlugin) -> Unit {
  let _ = self
}

// 默认插件全局实例
let default_plugin : SamplePlugin = SamplePlugin::new()

pub fn get_plugin() -> SamplePlugin {
  default_plugin
}
