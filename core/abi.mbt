///|
/// AnyEasier 插件 ABI：与 Rust adapter 组件之间的全标量桥。
///
/// 协议（与 adapter 约定一致，见 pkg/README.md「ABI 协议」）：
/// - 请求：adapter 调 `moon_alloc(len)` 复位缓冲，再经 `moon_write_u32`
///   逐字写入 `[len:u32 LE][payload...]`（4 字节对齐补零）；
/// - 调用 `moon_init` / `moon_on_event` / `moon_validate` /
///   `moon_get_default_config` / `moon_destroy`（无参）；
/// - 应答：adapter 调 `moon_buf_len()` 得数据长度，再经 `moon_read_u32`
///   从应答字节区逐字拉取。
///
/// 内存布局（MoonBit 线性内存）：
///   0x100000 (1MB)   请求缓冲 64KB   ← moon_alloc / moon_write_u32
///   0x180000 (1.5MB) 应答缓冲 64KB  ← moon_buf_len / moon_read_u32
///   0x200000 (2MB)   MoonBit 堆起始（moon.pkg heap-start-address）
/// 两缓冲物理隔离于 MoonBit 堆与数据段之外，初始内存 32 页（2MB）覆盖。

///|
fn mem_load_u32(offset : Int) -> Int = #|(func (param i32) (result i32) local.get 0 i32.load)

///|
fn mem_size_pages() -> Int = #|(func (result i32) memory.size)

///|
fn mem_grow(delta_pages : Int) -> Int = #|(func (param i32) (result i32) local.get 0 memory.grow)

///| 内存就绪守卫：确保初始内存覆盖共享缓冲区（2MB）。
let mem_ready : Ref[Bool] = Ref(false)

///|
fn ensure_memory() -> Unit {
  if not(mem_ready.val) {
    let cur = mem_size_pages()
    if cur < 32 {
      let _ = mem_grow(32 - cur)
    }
    mem_ready.val = true
  }
}

///|
fn mem_store_u32(offset : Int, value : Int) -> Unit = #|(func (param i32) (param i32) local.get 0 local.get 1 i32.store)

///|
fn mem_load_u8(offset : Int) -> Int = #|(func (param i32) (result i32) local.get 0 i32.load8_u)

///|
fn mem_store_u8(offset : Int, value : Int) -> Unit = #|(func (param i32) (param i32) local.get 0 local.get 1 i32.store8)

///| 请求缓冲基址（1MB）。
const REQ_BASE : Int = 0x100000

///| 请求缓冲容量（64KB）。
const REQ_CAP : Int = 0x10000

///| 应答缓冲基址（1.5MB）。
const REP_BASE : Int = 0x180000

///| 应答缓冲容量（64KB，长度头占 4）。
const REP_CAP : Int = 0x10000

///| 应答数据长度（MoonBit 内部读写）。
let rep_len : Ref[Int] = Ref(0)

///|
/// 请求缓冲复位。adapter 之后经 moon_write_u32 写入
/// `[len:u32][payload...]`（payload 长度为 len，4 字节对齐补零）。
/// 返回基址（长度头的位置）。
#export_name("moon_alloc")
pub fn moon_alloc(len : Int) -> Int {
  guard len + 4 <= REQ_CAP
  else {
    abort("moon_alloc：请求超过缓冲容量")
  }
  mem_store_u32(REQ_BASE, 0)
  REQ_BASE
}

///|
/// 向请求缓冲写入一个 u32（adapter 用）。
/// offset 相对缓冲基址：0 = 长度头，4 = payload 首字。
#export_name("moon_write_u32")
pub fn moon_write_u32(offset : Int, word : Int) -> Unit {
  mem_store_u32(REQ_BASE + offset, word)
}

///|
/// 应答数据长度（字节；adapter 拉取应答前先读）。
#export_name("moon_buf_len")
pub fn moon_buf_len() -> Int {
  rep_len.val
}

///|
/// 从应答字节区读一个 u32（adapter 用）。offset 是字节偏移；
/// 不足 4 字节的尾部高位补零。
#export_name("moon_read_u32")
pub fn moon_read_u32(offset : Int) -> Int {
  let mut v = 0
  for i in 0..<4 {
    let pos = offset + i
    let b = if pos < rep_len.val {
      mem_load_u8(REP_BASE + 4 + pos)
    } else {
      0
    }
    v = v | (b << (8 * i))
  }
  v
}

///|
/// 把应答字节写入应答缓冲（字节区从基址 +4 开始，长度头记录长度）。
fn write_reply(bytes : Bytes) -> Unit {
  let len = bytes.length()
  guard len <= REP_CAP - 4
  else {
    abort("write_reply：应答超过缓冲容量")
  }
  mem_store_u32(REP_BASE, len)
  for i in 0..<len {
    mem_store_u8(REP_BASE + 4 + i, bytes[i].to_int())
  }
  rep_len.val = len
}

///|
/// 读取请求 payload（当前导出函数的入参；长度头之后的字节）。
fn read_request() -> Bytes {
  let len = mem_load_u32(REQ_BASE)
  // 上限 64KB（缓冲容量），防御异常长度
  if len <= 0 || len > REQ_CAP - 4 {
    return b""
  }
  let buf : Array[Byte] = Array::make(len, b'\x00')
  for i in 0..<len {
    buf[i] = mem_load_u8(REQ_BASE + 4 + i).to_byte()
  }
  Bytes::from_array(buf[:])
}
