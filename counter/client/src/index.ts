import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import * as anchor from "@coral-xyz/anchor";
import BN from "bn.js";

const PROGRAM_ID = new anchor.web3.PublicKey(
  "4ZfDpKj91bdUw8FuJBGvZu3a9Xis2Ce4QQsjMtwgMG3b",
);

const MEMO_PROGRAM_ID = new anchor.web3.PublicKey(
  "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr",
);

const IDL_PATH = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  "../../idl/counter.json",
);

const COUNTER_SIZE = 8 + 8;

async function main(): Promise<void> {
  const url = "http://127.0.0.1:8899";
  const connection = new anchor.web3.Connection(url, "confirmed");
  const walletPath =
    process.env.ANCHOR_WALLET ||
    path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(JSON.parse(fs.readFileSync(walletPath, "utf8")));
  const keypair = anchor.web3.Keypair.fromSecretKey(secret);
  const wallet = new anchor.Wallet(keypair);
  const provider = new anchor.AnchorProvider(connection, wallet, {
    commitment: "confirmed",
  });
  anchor.setProvider(provider);

  const idl = JSON.parse(fs.readFileSync(IDL_PATH, "utf8"));
  const coder = new anchor.BorshCoder(idl);
  const instructionCoder = new anchor.BorshInstructionCoder(idl);

  const counter = anchor.web3.Keypair.generate();
  const lamports = await connection.getMinimumBalanceForRentExemption(
    COUNTER_SIZE,
  );

  const createIx = anchor.web3.SystemProgram.createAccount({
    fromPubkey: wallet.publicKey,
    newAccountPubkey: counter.publicKey,
    space: COUNTER_SIZE,
    lamports,
    programId: PROGRAM_ID,
  });

  const createSig = await provider.sendAndConfirm(
    new anchor.web3.Transaction().add(createIx),
    [counter],
  );
  console.log("create account tx:", createSig);

  const initData = instructionCoder.encode("initialize", {
    initial: new BN(1),
  });
  if (!initData) {
    throw new Error("failed to encode initialize");
  }
  const initIx = new anchor.web3.TransactionInstruction({
    programId: PROGRAM_ID,
    data: initData,
    keys: [
      { pubkey: wallet.publicKey, isSigner: true, isWritable: true },
      { pubkey: counter.publicKey, isSigner: false, isWritable: true },
    ],
  });
  const initSig = await provider.sendAndConfirm(
    new anchor.web3.Transaction().add(initIx),
    [],
  );
  console.log("initialize tx:", initSig);

  const incData = instructionCoder.encode("increment", {
    amount: new BN(2),
  });
  if (!incData) {
    throw new Error("failed to encode increment");
  }
  const incIx = new anchor.web3.TransactionInstruction({
    programId: PROGRAM_ID,
    data: incData,
    keys: [
      { pubkey: wallet.publicKey, isSigner: true, isWritable: false },
      { pubkey: counter.publicKey, isSigner: false, isWritable: true },
    ],
  });
  const incSig = await provider.sendAndConfirm(
    new anchor.web3.Transaction().add(incIx),
    [],
  );
  console.log("increment tx:", incSig);

  const memoData = instructionCoder.encode("increment_with_memo", {
    amount: new BN(3),
  });
  if (!memoData) {
    throw new Error("failed to encode increment_with_memo");
  }
  const memoIx = new anchor.web3.TransactionInstruction({
    programId: PROGRAM_ID,
    data: memoData,
    keys: [
      { pubkey: wallet.publicKey, isSigner: true, isWritable: false },
      { pubkey: counter.publicKey, isSigner: false, isWritable: true },
      { pubkey: MEMO_PROGRAM_ID, isSigner: false, isWritable: false },
    ],
  });
  const memoSig = await provider.sendAndConfirm(
    new anchor.web3.Transaction().add(memoIx),
    [],
  );
  console.log("increment_with_memo tx:", memoSig);

  const accountInfo = await connection.getAccountInfo(counter.publicKey);
  if (!accountInfo) {
    throw new Error("counter account not found");
  }
  const decoded = coder.accounts.decode("CounterData", accountInfo.data);
  console.log("counter:", {
    count: decoded.count.toString(),
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
