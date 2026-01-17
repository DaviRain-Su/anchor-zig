# 示例：ATA init + mintTo + transferChecked 完整链路

本示例展示完整 Token CPI 流程：
- 初始化 ATA
- mintTo 铸造到 ATA
- transferChecked 从 ATA 转账

## 1. 标准流程脚本

```bash
./scripts/bootstrap-anchor-project.sh /path/to/project/my_token_app my_token_app
```

说明：`target-dir` 是完整项目目录，`project-name` 用于替换模板内名称。

## 2. 账户与指令定义

```zig
const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;
const dsl = anchor.dsl;

const MintTransferArgs = struct {
    mint_amount: u64,
    transfer_amount: u64,
};

const MintTransferAccounts = dsl.Accounts(.{
    .payer = dsl.SignerMut,
    .authority = dsl.Signer,
    .mint = dsl.Mint(.{ .authority = .authority }),
    .user_ata = dsl.ATA(.{
        .mint = .mint,
        .authority = .authority,
        .init = true,
        .payer = .payer,
    }),
    .recipient = dsl.Unchecked,
    .recipient_ata = dsl.ATA(.{
        .mint = .mint,
        .authority = .recipient,
        .if_needed = true,
        .payer = .payer,
    }),
    .token_program = dsl.TokenProgram,
    .system_program = dsl.SystemProgram,
    .associated_token_program = dsl.AssociatedTokenProgram,
});

const MintTransfer = dsl.Instr("mint_and_transfer", MintTransferAccounts, MintTransferArgs);
```

要点：
- `user_ata` 与 `recipient_ata` 使用 `dsl.ATA` 自动初始化
- `recipient` 不需要签名，用 `dsl.Unchecked` 即可
- ATA 初始化必须提供 `token_program`、`system_program`、`associated_token_program`

## 3. 指令处理与 Token CPI

```zig
const Error = error{ TokenCpiFailed };

pub fn mint_and_transfer(ctx: MintTransfer.Ctx, args: MintTransfer.Args) Error!void {
    if (anchor.token.mintTo(
        ctx.accounts.token_program.toAccountInfo(),
        ctx.accounts.mint.toAccountInfo(),
        ctx.accounts.user_ata.toAccountInfo(),
        ctx.accounts.authority.toAccountInfo(),
        args.mint_amount,
    )) |_| {
        return error.TokenCpiFailed;
    }

    if (anchor.token.transferCheckedWithMint(
        ctx.accounts.token_program.toAccountInfo(),
        ctx.accounts.user_ata.toAccountInfo(),
        ctx.accounts.mint,
        ctx.accounts.recipient_ata.toAccountInfo(),
        ctx.accounts.authority.toAccountInfo(),
        args.transfer_amount,
    )) |_| {
        return error.TokenCpiFailed;
    }
}
```

说明：
- `transferCheckedWithMint` 会自动读取 Mint 的 decimals
- `TokenCpiError` 可根据实际需要细化处理

## 4. 构建与 IDL

```bash
./install-solana-zig.sh solana-zig
cd /path/to/project/my_token_app
../solana-zig/zig build -Drelease

mkdir -p idl
../solana-zig/zig build idl \
  -Didl-program=src/main.zig \
  -Didl-output=idl/my_token_app.json
```

## 5. 本地验证器与部署

```bash
solana-test-validator
```

另开终端：

```bash
solana config set --url http://127.0.0.1:8899
solana airdrop 2
solana program deploy zig-out/lib/my_token_app.so
```

部署完成后，确保 `Program.id` 与部署地址一致。

## 6. TS 客户端（最小流程）

在 `client/` 目录创建一个简单脚本（无需 Anchor workspace）：

```ts
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import * as anchor from "@coral-xyz/anchor";
import BN from "bn.js";

const PROGRAM_ID = new anchor.web3.PublicKey("PROGRAM_ID_HERE");
const IDL_PATH = path.resolve("idl/my_token_app.json");

async function main(): Promise<void> {
  const connection = new anchor.web3.Connection("http://127.0.0.1:8899", "confirmed");
  const walletPath =
    process.env.ANCHOR_WALLET ||
    path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(JSON.parse(fs.readFileSync(walletPath, "utf8")));
  const keypair = anchor.web3.Keypair.fromSecretKey(secret);
  const wallet = new anchor.Wallet(keypair);
  const provider = new anchor.AnchorProvider(connection, wallet, { commitment: "confirmed" });
  anchor.setProvider(provider);

  const idl = JSON.parse(fs.readFileSync(IDL_PATH, "utf8"));
  const instructionCoder = new anchor.BorshInstructionCoder(idl);

  const data = instructionCoder.encode("mint_and_transfer", {
    mintAmount: new BN(10_000),
    transferAmount: new BN(1_000),
  });
  if (!data) throw new Error("encode failed");

  const keys = [
    { pubkey: wallet.publicKey, isSigner: true, isWritable: true },  // payer
    { pubkey: wallet.publicKey, isSigner: true, isWritable: false }, // authority
    // mint / user_ata / recipient / recipient_ata / token_program / system_program / ata_program
  ];

  const ix = new anchor.web3.TransactionInstruction({
    programId: PROGRAM_ID,
    data,
    keys,
  });

  const sig = await provider.sendAndConfirm(new anchor.web3.Transaction().add(ix), []);
  console.log("mint_and_transfer tx:", sig);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

运行：

```bash
cd /path/to/project/my_token_app
mkdir -p client
cd client
npm init -y
npm i @coral-xyz/anchor bn.js
npm i -D tsx typescript
npx tsx index.ts
```

说明：
- 账户顺序必须与 Accounts 定义一致
- `mintAmount` / `transferAmount` 字段名与 IDL 保持一致

## 7. TS 客户端（端到端：创建 Mint + ATA）

下面示例使用 `@solana/spl-token` 创建 Mint 与 ATA，再调用程序指令。

```ts
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import * as anchor from "@coral-xyz/anchor";
import BN from "bn.js";
import {
  createAssociatedTokenAccountInstruction,
  createInitializeMintInstruction,
  createMintToInstruction,
  getAssociatedTokenAddressSync,
  getMinimumBalanceForRentExemptMint,
  MINT_SIZE,
  TOKEN_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
} from "@solana/spl-token";

const PROGRAM_ID = new anchor.web3.PublicKey("PROGRAM_ID_HERE");
const IDL_PATH = path.resolve("idl/my_token_app.json");

async function main(): Promise<void> {
  const connection = new anchor.web3.Connection("http://127.0.0.1:8899", "confirmed");
  const walletPath =
    process.env.ANCHOR_WALLET ||
    path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(JSON.parse(fs.readFileSync(walletPath, "utf8")));
  const keypair = anchor.web3.Keypair.fromSecretKey(secret);
  const wallet = new anchor.Wallet(keypair);
  const provider = new anchor.AnchorProvider(connection, wallet, { commitment: "confirmed" });
  anchor.setProvider(provider);

  const idl = JSON.parse(fs.readFileSync(IDL_PATH, "utf8"));
  const instructionCoder = new anchor.BorshInstructionCoder(idl);

  const mintKeypair = anchor.web3.Keypair.generate();
  const mintRent = await getMinimumBalanceForRentExemptMint(connection);
  const mintAuthority = wallet.publicKey;
  const freezeAuthority = wallet.publicKey;
  const decimals = 9;

  const userAta = getAssociatedTokenAddressSync(
    mintKeypair.publicKey,
    wallet.publicKey,
    false,
    TOKEN_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID,
  );

  const recipient = anchor.web3.Keypair.generate().publicKey;
  const recipientAta = getAssociatedTokenAddressSync(
    mintKeypair.publicKey,
    recipient,
    false,
    TOKEN_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID,
  );

  const createMintIx = anchor.web3.SystemProgram.createAccount({
    fromPubkey: wallet.publicKey,
    newAccountPubkey: mintKeypair.publicKey,
    space: MINT_SIZE,
    lamports: mintRent,
    programId: TOKEN_PROGRAM_ID,
  });

  const initMintIx = createInitializeMintInstruction(
    mintKeypair.publicKey,
    decimals,
    mintAuthority,
    freezeAuthority,
    TOKEN_PROGRAM_ID,
  );

  const createUserAtaIx = createAssociatedTokenAccountInstruction(
    wallet.publicKey,
    userAta,
    wallet.publicKey,
    mintKeypair.publicKey,
    TOKEN_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID,
  );

  const createRecipientAtaIx = createAssociatedTokenAccountInstruction(
    wallet.publicKey,
    recipientAta,
    recipient,
    mintKeypair.publicKey,
    TOKEN_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID,
  );

  const mintToIx = createMintToInstruction(
    mintKeypair.publicKey,
    userAta,
    mintAuthority,
    10_000,
    [],
    TOKEN_PROGRAM_ID,
  );

  const tx = new anchor.web3.Transaction()
    .add(createMintIx, initMintIx, createUserAtaIx, createRecipientAtaIx, mintToIx);
  await provider.sendAndConfirm(tx, [mintKeypair]);

  const data = instructionCoder.encode("mint_and_transfer", {
    mintAmount: new BN(10_000),
    transferAmount: new BN(1_000),
  });
  if (!data) throw new Error("encode failed");

  const keys = [
    { pubkey: wallet.publicKey, isSigner: true, isWritable: true },  // payer
    { pubkey: wallet.publicKey, isSigner: true, isWritable: false }, // authority
    { pubkey: mintKeypair.publicKey, isSigner: false, isWritable: true },
    { pubkey: userAta, isSigner: false, isWritable: true },
    { pubkey: recipient, isSigner: false, isWritable: false },
    { pubkey: recipientAta, isSigner: false, isWritable: true },
    { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
    { pubkey: anchor.web3.SystemProgram.programId, isSigner: false, isWritable: false },
    { pubkey: ASSOCIATED_TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
  ];

  const ix = new anchor.web3.TransactionInstruction({
    programId: PROGRAM_ID,
    data,
    keys,
  });

  const sig = await provider.sendAndConfirm(new anchor.web3.Transaction().add(ix), []);
  console.log("mint_and_transfer tx:", sig);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

运行：

```bash
cd /path/to/project/my_token_app
mkdir -p client
cd client
npm init -y
npm i @coral-xyz/anchor @solana/spl-token bn.js
npm i -D tsx typescript
npx tsx index.ts
```

说明：
- `recipient` 是临时生成的地址，仅用于演示 ATA 创建
- `mintAmount` / `transferAmount` 仍需与 IDL 字段名一致

## 8. PDA 作为 Token Authority 的变体

如果需要让 PDA 作为 token account 的 authority，可使用 `transferSigned` 进行转账。

```zig
const VaultData = struct {
    authority: sol.PublicKey,
    bump: u8,
};

const PdaTransferAccounts = dsl.Accounts(.{
    .payer = dsl.SignerMut,
    .authority = dsl.Signer,
    .vault = dsl.PDA(VaultData, .{
        .seeds = &.{ dsl.seed("vault"), dsl.seedFrom(.authority), dsl.seedBump(.vault) },
        .bump = true,
        .bump_field = "bump",
        .mut = true,
    }),
    .vault_ata = dsl.ATA(.{
        .mint = .mint,
        .authority = .vault,
        .init = true,
        .payer = .payer,
    }),
    .user_ata = dsl.Token(.{ .mint = .mint, .authority = .authority, .mut = true }),
    .mint = dsl.Mint(.{ .authority = .authority }),
    .token_program = dsl.TokenProgram,
    .system_program = dsl.SystemProgram,
    .associated_token_program = dsl.AssociatedTokenProgram,
});
```

```zig
const Error = error{ TokenCpiFailed };

pub fn pda_transfer(ctx: PdaTransfer.Ctx, args: PdaTransfer.Args) Error!void {
    const bump = ctx.accounts.vault.data.bump;
    const authority_key = ctx.accounts.authority.key().*;
    const authority_key_bytes = authority_key.bytes;

    const seeds = &.{
        &[_][]const u8{ "vault", authority_key_bytes[0..], &.{ bump } },
    };

    if (anchor.token.transferSigned(
        ctx.accounts.token_program.toAccountInfo(),
        ctx.accounts.vault_ata.toAccountInfo(),
        ctx.accounts.user_ata.toAccountInfo(),
        ctx.accounts.vault.toAccountInfo(),
        args.amount,
        seeds,
    )) |_| {
        return error.TokenCpiFailed;
    }
}
```

说明：
- PDA authority 只能使用 `invokeSigned` 路径
- `authority_key.bytes` 来自 SDK 的 `PublicKey` bytes 字段
