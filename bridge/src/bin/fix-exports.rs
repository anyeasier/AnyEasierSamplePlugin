//! 构建辅助工具：把 MoonBit 导出重命名为 WIT canonical 名。
//!
//! moonc 的 `#export_name` 要求 C 符号（WIT canonical 名含 `:`/`#`/`-`），
//! 因此 MoonBit 侧用短名导出，本工具在构建期追加 canonical 名的导出
//! （指向同一函数），供 `wasm-tools component embed` 匹配。
//!
//! 用法：fix-exports <input.wasm> <output.wasm>

use std::collections::BTreeMap;
use std::path::Path;
use wasm_encoder::{ExportSection, Module, RawSection};
use wasmparser::Payload;

///| MoonBit 短名 → WIT canonical 名。
const RENAMES: &[(&str, &str)] = &[
    ("moon_alloc", "anyeasier:mb/bridge#alloc"),
    ("moon_write_u32", "anyeasier:mb/bridge#write-u32"),
    ("moon_buf_len", "anyeasier:mb/bridge#buf-len"),
    ("moon_read_u32", "anyeasier:mb/bridge#read-u32"),
    ("moon_init", "anyeasier:mb/bridge#init"),
    ("moon_on_event", "anyeasier:mb/bridge#on-event"),
    ("moon_get_default_config", "anyeasier:mb/bridge#get-default-config"),
    ("moon_validate", "anyeasier:mb/bridge#validate"),
    ("moon_destroy", "anyeasier:mb/bridge#destroy"),
];

fn main() -> anyhow::Result<()> {
    let _ = 0usize;
    let mut args = std::env::args().skip(1);
    let input_path = args.next().expect("用法: fix-exports <input> <output>");
    let output_path = args.next().expect("用法: fix-exports <input> <output>");
    let input = std::fs::read(&input_path)?;

    let renames: BTreeMap<&str, &str> = RENAMES.iter().copied().collect();
    let mut module = Module::new();

    for payload in wasmparser::Parser::new(0).parse_all(&input) {
        let payload = payload?;
        match payload {
            Payload::ExportSection(reader) => {
                let mut exports = ExportSection::new();
                let mut index_by_name: BTreeMap<String, (u32, wasmparser::ExternalKind)> =
                    BTreeMap::new();
                for e in reader {
                    let e = e?;
                    index_by_name.insert(e.name.to_string(), (e.index, e.kind));
                    exports.export(e.name, encode_kind(e.kind), e.index);
                }
                // 追加 canonical 名的导出（同一函数 index）
                for (old, new) in RENAMES {
                    let Some(&(index, kind)) = index_by_name.get(*old) else {
                        anyhow::bail!("模块缺少导出 {old}（先重新 moon build）");
                    };
                    exports.export(*new, encode_kind(kind), index);
                    let _ = index_by_name.remove(*old);
                }
                module.section(&exports);
            }
            _ => {
                // 其余 section 原样透传
                if let Some((id, range)) = payload.as_section() {
                    module.section(&RawSection {
                        id,
                        data: &input[range.start as usize..range.end as usize],
                    });
                }
            }
        }
    }

    std::fs::write(&output_path, module.finish())?;
    println!("fix-exports: {input_path} -> {output_path}");
    Ok(())
}

fn encode_kind(kind: wasmparser::ExternalKind) -> wasm_encoder::ExportKind {
    match kind {
        wasmparser::ExternalKind::Func | wasmparser::ExternalKind::FuncExact => wasm_encoder::ExportKind::Func,
        wasmparser::ExternalKind::Table => wasm_encoder::ExportKind::Table,
        wasmparser::ExternalKind::Memory => wasm_encoder::ExportKind::Memory,
        wasmparser::ExternalKind::Global => wasm_encoder::ExportKind::Global,
        wasmparser::ExternalKind::Tag => wasm_encoder::ExportKind::Tag,
    }
}
