///|
/// WIT guest 导出（全标量；数据经 ABI 共享缓冲交换）。
///
/// 协议见 abi.mbt 顶部注释。各导出的 payload 约定：
///
/// | 导出 | 请求 payload | 应答 payload |
/// |---|---|---|
/// | moon_init | `[cfgLen:u32][metaLen:u32][cfg][meta]` | （无） |
/// | moon_on_event | 事件 JSON | 动作 JSON 数组 |
/// | moon_get_default_config | （空） | 默认配置 JSON（可为空） |
/// | moon_validate | 配置 JSON | （不合法时错误文本） |
/// | moon_destroy | （空） | （无） |

let plugin : @logic.SamplePlugin = @logic.get_plugin()

///|
#export_name("moon_init")
pub fn moon_init() -> Unit {
  ensure_memory()
  let req = read_request()
  let cfg_len = u32_le_at(req, 0)
  let meta_len = u32_le_at(req, 4)
  let config = @utf8.decode_lossy(read_region(req, 8, cfg_len)[:])
  let meta_json = @utf8.decode_lossy(read_region(req, 8 + cfg_len, meta_len)[:])
  let meta = @sdk.parse_meta(meta_json)
  if meta.api_version != @sdk.SDK_API_VERSION {
    abort("AnyEasier API version mismatch: expected \{@sdk.SDK_API_VERSION}, got \{meta.api_version}")
  }
  plugin.init(config~, meta~)
}

///|
#export_name("moon_on_event")
pub fn moon_on_event() -> Unit {
  ensure_memory()
  let req = read_request()
  let evt_json = @utf8.decode_lossy(req[:])
  let actions = try {
    let evt = @sdk.parse_event(evt_json)
    plugin.handle_event(event=evt)
  } catch {
    err => [
      @sdk.Action::Log(level=Error, message="SDK 异常：\{err}｜输入长度 \{evt_json.length()}｜内容：\{evt_json}")
    ]
  }
  write_reply(@utf8.encode(@sdk.render_actions(actions)))
}

///|
#export_name("moon_get_default_config")
pub fn moon_get_default_config() -> Unit {
  ensure_memory()
  match plugin.default_config() {
    Some(cfg) => write_reply(@utf8.encode(cfg[:]))
    None => write_reply(b"")
  }
}

///|
#export_name("moon_validate")
pub fn moon_validate() -> Unit {
  ensure_memory()
  let req = read_request()
  let config = @utf8.decode_lossy(req[:])
  match plugin.validate(config~) {
    None => write_reply(b"")
    Some(msg) => write_reply(@utf8.encode(msg[:]))
  }
}

///|
#export_name("moon_destroy")
pub fn moon_destroy() -> Unit {
  ensure_memory()
  plugin.destroy()
}

///|
/// 从 bytes 的 [start, start+len) 区间拷出视图（越界自动收紧）。
fn read_region(bytes : Bytes, start : Int, len : Int) -> BytesView {
  let end = if start + len > bytes.length() {
    bytes.length()
  } else {
    start + len
  }
  if start >= end {
    return b""[:]
  }
  bytes[start:end]
}

///|
fn u32_le_at(bytes : Bytes, offset : Int) -> Int {
  let b0 = get_or_zero(bytes.get(offset)).to_int()
  let b1 = get_or_zero(bytes.get(offset + 1)).to_int()
  let b2 = get_or_zero(bytes.get(offset + 2)).to_int()
  let b3 = get_or_zero(bytes.get(offset + 3)).to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
fn get_or_zero(b : Byte?) -> Byte {
  match b {
    Some(x) => x
    None => b'\x00'
  }
}
