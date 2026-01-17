# IDL 与客户端生成

本节介绍 IDL 输出、Zig 客户端生成，以及命令行构建步骤。

## 1. 生成 IDL 与 Zig 客户端

```zig
const anchor = @import("sol_anchor_zig");

const idl_json = try anchor.generateIdlJson(allocator, Program, .{});
const client_src = try anchor.generateZigClient(allocator, Program, .{});
```

- `Program` 必须导出 `pub const instructions`
- 事件若使用 `anchor.dsl.Event`，会被收集进 IDL

## 2. 构建步骤输出 IDL

```bash
./solana-zig/zig build idl \
  -Didl-program=src/main.zig \
  -Didl-output=idl/my_program.json
```

要求：
- `idl-program` 必须导出 `pub const Program`
- 输出目录需提前存在（例如 `idl/`）

## 3. 与 TS 客户端协作

IDL 可以直接用于 Anchor TS 客户端：

```ts
import * as anchor from "@coral-xyz/anchor";
const idl = JSON.parse(fs.readFileSync("idl/my_program.json", "utf8"));
const coder = new anchor.BorshCoder(idl);
```

对于事件解析：

```ts
const eventParser = new anchor.EventParser(PROGRAM_ID, coder);
const parsedEvents = [...eventParser.parseLogs(logMessages)];
```
