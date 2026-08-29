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

///| 插件配置（init 时缓存；config-changed 时更新）。
let plugin_config : Ref[String] = Ref("{}")

///| 平台（init 时从 meta JSON 缓存）。
let cached_platform : Ref[String] = Ref("windows")

///|
#export_name("moon_init")
pub fn moon_init() -> Unit {
  ensure_memory()
  let req = read_request()
  let cfg_len = u32_le_at(req, 0)
  let meta_len = u32_le_at(req, 4)
  let config = @utf8.decode_lossy(read_region(req, 8, cfg_len)[:])
  let meta = @utf8.decode_lossy(read_region(req, 8 + cfg_len, meta_len)[:])
  plugin_config.val = config
  @logic.set_platform(extract_platform(meta))
}

///|
#export_name("moon_on_event")
pub fn moon_on_event() -> Unit {
  ensure_memory()
  let req = read_request()
  let evt_json = @utf8.decode_lossy(req[:])
  write_reply(@utf8.encode(@logic.handle_event(evt_json)[:]))
}

///|
#export_name("moon_get_default_config")
pub fn moon_get_default_config() -> Unit {
  ensure_memory()
  write_reply(@utf8.encode(@logic.default_config()[:]))
}

///|
#export_name("moon_validate")
pub fn moon_validate() -> Unit {
  ensure_memory()
  let req = read_request()
  let config = @utf8.decode_lossy(req[:])
  match @logic.validate_config(config) {
    None => write_reply(b"")
    Some(msg) => write_reply(@utf8.encode(msg[:]))
  }
}

///|
#export_name("moon_destroy")
pub fn moon_destroy() -> Unit {
  ensure_memory()
  // 无需清理：实例随 adapter 一起销毁
  ()

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

///|
/// meta JSON 形如 {"api_version":"0.1","app_version":"0.1.0","platform":"windows"}。
fn extract_platform(meta_json : String) -> String {
  try {
    let meta = @json.parse(meta_json)
    guard meta is Object(fields)
    match fields.get("platform") {
      Some(Json::String(p)) => p
      _ => "windows"
    }
  } catch {
    _ => "windows"
  }
}
