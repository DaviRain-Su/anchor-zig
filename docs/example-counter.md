# 端到端示例：Counter 程序 + IDL + TS 客户端

本示例基于仓库内 `counter/` 项目，展示从程序构建、IDL 生成到 TS 客户端调用的完整流程。

## 1. 标准流程脚本

如需新建项目或同步模板，优先使用仓库脚本：

```bash
./scripts/bootstrap-anchor-project.sh /path/to/project/my_counter my_counter
```

说明：`target-dir` 是完整项目目录，`project-name` 用于替换模板内名称。

## 2. 准备环境

- 已安装 Solana CLI（`solana`）
- 已安装 Node.js 与 pnpm/npm
- 已拉取 solana-zig SDK

```bash
./install-solana-zig.sh solana-zig
```

## 3. 构建 Counter 程序

```bash
cd counter
../solana-zig/zig build -Drelease
```

生成的 `.so` 默认在 `counter/zig-out/lib/`。

## 4. 生成 IDL

```bash
mkdir -p idl
../solana-zig/zig build idl \
  -Didl-program=src/main.zig \
  -Didl-output=idl/counter.json
```

## 5. 启动本地验证器与部署

```bash
solana-test-validator
```

在另一个终端：

```bash
solana config set --url http://127.0.0.1:8899
solana airdrop 2
solana program deploy zig-out/lib/counter.so
```

部署完成后，确保 `counter/src/main.zig` 中的 `Program.id` 与部署地址一致。

## 6. 运行 TS 客户端

```bash
cd counter/client
pnpm install
pnpm tsx src/index.ts
```

客户端行为：
- 创建 Counter 账户
- 调用 `initialize`、`increment`、`increment_with_memo`
- 解析并打印事件日志

## 7. 常见问题

- **IDL 路径错误**: `counter/client/src/index.ts` 默认读取 `counter/idl/counter.json`
- **Program ID 不匹配**: 部署地址需与 `Program.id` 一致
- **账户空间不足**: `COUNTER_SIZE` 要与实际数据结构匹配
