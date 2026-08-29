//! AnyEasier 插件 Rust adapter。
//!
//! 职责：把 anyeasier:plugin 的 WIT guest 接口翻译成对 MoonBit 组件
//! （anyeasier:mb/bridge，全标量接口）的调用，把 MoonBit 产出的动作
//! JSON 翻译回 WIT action / host 调用。本 crate 不含插件业务逻辑——
//! 业务全部在 MoonBit 侧（见仓库 logic/ 与 core/ 包）。
//!
//! 协议见 pkg/README.md「ABI 协议」。构建后经 `wasm-tools compose`
//! 与 MoonBit 组件合并为最终 main.wasm。

wit_bindgen::generate!({
    path: "wit",
    world: "adapter",
    generate_all,
});

use anyeasier::mb::bridge;
use anyeasier::plugin::host;
use anyeasier::plugin::types::{Action, CommandOptions, Event, MessageKind};
use exports::anyeasier::plugin::guest::Guest;

///| guest 导出：翻译层。业务决策全部在 MoonBit。
struct Adapter;

impl Guest for Adapter {
    fn init(config: String, meta: String) -> Result<(), String> {
        let mut payload = Vec::with_capacity(config.len() + meta.len() + 8);
        payload.extend_from_slice(&(config.len() as u32).to_le_bytes());
        payload.extend_from_slice(&(meta.len() as u32).to_le_bytes());
        payload.extend_from_slice(config.as_bytes());
        payload.extend_from_slice(meta.as_bytes());
        call_moon(&payload, || bridge::init());
        Ok(())
    }

    fn on_event(evt: Event) -> Vec<Action> {
        let json = event_to_json(&evt);
        let reply = call_moon(json.as_bytes(), || bridge::on_event());
        let text = String::from_utf8_lossy(&reply);
        match serde_json::from_str::<Vec<serde_json::Value>>(&text) {
            Ok(items) => items.iter().filter_map(action_from_json).collect(),
            Err(e) => {
                host::log(
                    anyeasier::plugin::types::LogLevel::Error,
                    &format!("MoonBit 动作 JSON 无效：{e}"),
                );
                Vec::new()
            }
        }
    }

    fn get_default_config() -> Option<String> {
        let reply = call_moon(&[], || bridge::get_default_config());
        let s = String::from_utf8_lossy(&reply).trim().to_string();
        if s.is_empty() { None } else { Some(s) }
    }

    fn validate(config: String) -> Option<String> {
        let reply = call_moon(config.as_bytes(), || bridge::validate());
        let s = String::from_utf8_lossy(&reply).trim().to_string();
        if s.is_empty() { None } else { Some(s) }
    }

    fn destroy() {
        call_moon(&[], || bridge::destroy());
    }
}

///| 共享缓冲调用：写请求 `[len][payload]`（4 字节对齐）→ 执行 → 拉应答。
/// write-u32 的 offset 相对缓冲基址：0 = 长度头，4 = payload 首字。
fn call_moon(payload: &[u8], invoke: impl FnOnce()) -> Vec<u8> {
    let _base = bridge::alloc(payload.len() as u32);
    bridge::write_u32(0, payload.len() as u32);
    for (i, word) in payload.chunks(4).enumerate() {
        let mut w = [0u8; 4];
        w[..chunk_len(payload.len(), i)].copy_from_slice(word);
        bridge::write_u32((i * 4 + 4) as u32, u32::from_le_bytes(w));
    }
    invoke();
    pull_reply()
}

fn chunk_len(total: usize, index: usize) -> usize {
    let start = index * 4;
    (total - start).min(4)
}

///| 从 MoonBit 应答缓冲逐 u32 拉取应答字节。
fn pull_reply() -> Vec<u8> {
    let len = bridge::buf_len() as usize;
    let mut out = Vec::with_capacity(len);
    let mut offset = 0usize;
    while offset < len {
        let word = bridge::read_u32(offset as u32).to_le_bytes();
        let take = (len - offset).min(4);
        out.extend_from_slice(&word[..take]);
        offset += 4;
    }
    out
}

///| WIT Event → JSON（MoonBit 侧的事件协议）。
fn event_to_json(evt: &Event) -> String {
    let v = match evt {
        Event::UiReady => serde_json::json!({ "type": "ui-ready" }),
        Event::Control(ce) => serde_json::json!({
            "type": "control",
            "id": ce.id,
            "event": ce.event,
            "value": ce.value,
        }),
        Event::CommandFinished(r) => serde_json::json!({
            "type": "command-finished",
            "handle": r.handle,
            "exitCode": r.exit_code,
            "stdout": r.stdout,
            "stderr": r.stderr,
            "timedOut": r.timed_out,
        }),
        Event::HttpResponse(r) => serde_json::json!({
            "type": "http-response",
            "id": r.id,
            "status": r.status,
            "body": r.body,
        }),
        Event::DialogResult(dr) => serde_json::json!({
            "type": "dialog-result",
            "id": dr.id,
            "path": dr.path,
            "canceled": dr.canceled,
        }),
        Event::Timer(id) => serde_json::json!({ "type": "timer", "id": id }),
        Event::ConfigChanged(config) => {
            serde_json::json!({ "type": "config-changed", "config": config })
        }
    };
    v.to_string()
}

///| 动作 JSON → WIT Action / host 调用。未知类型忽略（返回 None）。
fn action_from_json(v: &serde_json::Value) -> Option<Action> {
    let kind = v.get("type")?.as_str()?;
    match kind {
        "log" => {
            // 扩展动作：MoonBit 日志 → host log
            let level = match v.get("level").and_then(|x| x.as_str()) {
                Some("debug") => anyeasier::plugin::types::LogLevel::Debug,
                Some("warn") => anyeasier::plugin::types::LogLevel::Warn,
                Some("error") => anyeasier::plugin::types::LogLevel::Error,
                _ => anyeasier::plugin::types::LogLevel::Info,
            };
            host::log(
                level,
                v.get("message").and_then(|x| x.as_str()).unwrap_or(""),
            );
            None
        }
        "run-command" => {
            // 扩展动作：发起命令（完成时由宿主自回环 command-finished 事件）
            let opts_json = v.get("options").cloned().unwrap_or(serde_json::json!({}));
            match serde_json::from_value::<OptsJson>(opts_json)
                .map_err(|e| e.to_string())
                .and_then(|o| host::run_command(&o.into()))
            {
                Ok(_) => None,
                Err(e) => {
                    host::log(
                        anyeasier::plugin::types::LogLevel::Error,
                        &format!("run-command 失败：{e}"),
                    );
                    None
                }
            }
        }
        "data-write" => {
            // 扩展动作：数据区写入（adapter 直接执行 host 调用）
            let path = v.get("path").and_then(|x| x.as_str()).unwrap_or("");
            let text = v.get("text").and_then(|x| x.as_str()).unwrap_or("");
            if let Err(e) = host::data_write(path, text.as_bytes()) {
                host::log(
                    anyeasier::plugin::types::LogLevel::Error,
                    &format!("data-write 失败：{e}"),
                );
            }
            None
        }
        "set-value" => Some(Action::SetValue((
            v.get("id")?.as_str()?.to_string(),
            v.get("value")
                .and_then(|x| x.as_str())
                .unwrap_or("")
                .to_string(),
        ))),
        "set-enabled" => Some(Action::SetEnabled((
            v.get("id")?.as_str()?.to_string(),
            v.get("enabled").and_then(|x| x.as_bool()).unwrap_or(true),
        ))),
        "set-visible" => Some(Action::SetVisible((
            v.get("id")?.as_str()?.to_string(),
            v.get("visible").and_then(|x| x.as_bool()).unwrap_or(true),
        ))),
        "set-options" => Some(Action::SetOptions((
            v.get("id")?.as_str()?.to_string(),
            v.get("options")
                .and_then(|x| x.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|s| s.as_str().map(str::to_string))
                        .collect()
                })
                .unwrap_or_default(),
        ))),
        "show-message" => Some(Action::ShowMessage(
            anyeasier::plugin::types::MessageOptions {
                kind: match v.get("kind").and_then(|x| x.as_str()) {
                    Some("warn") => MessageKind::Warn,
                    Some("error") => MessageKind::Error,
                    _ => MessageKind::Info,
                },
                title: v
                    .get("title")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .to_string(),
                text: v
                    .get("text")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .to_string(),
            },
        )),
        "set-timer" => Some(Action::SetTimer(anyeasier::plugin::types::TimerSpec {
            id: v.get("id").and_then(|x| x.as_u64()).unwrap_or(0) as u32,
            interval_ms: v
                .get("intervalMs")
                .and_then(|x| x.as_u64())
                .unwrap_or(1000) as u32,
            repeat: v.get("repeat").and_then(|x| x.as_bool()).unwrap_or(false),
        })),
        "clear-timer" => Some(Action::ClearTimer(
            v.get("id").and_then(|x| x.as_u64()).unwrap_or(0) as u32,
        )),
        "kill-command" => Some(Action::KillCommand(
            v.get("handle").and_then(|x| x.as_u64()).unwrap_or(0) as u32,
        )),
        "close" => Some(Action::Close),
        _ => {
            host::log(
                anyeasier::plugin::types::LogLevel::Warn,
                &format!("MoonBit 返回了未识别的动作类型：{kind}"),
            );
            None
        }
    }
}

export!(Adapter);

///| MoonBit 传来的 command-options JSON 形态（camelCase）。
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct OptsJson {
    program: String,
    #[serde(default)]
    args: Vec<String>,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(default)]
    env: Vec<(String, String)>,
    #[serde(default)]
    timeout_ms: Option<u32>,
    #[serde(default)]
    stdin: Option<String>,
}

impl From<OptsJson> for CommandOptions {
    fn from(o: OptsJson) -> Self {
        CommandOptions {
            program: o.program,
            args: o.args,
            cwd: o.cwd,
            env: o.env,
            timeout_ms: o.timeout_ms,
            stdin: o.stdin,
        }
    }
}
