import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import * as anchor from "@coral-xyz/anchor";
import BN from "bn.js";

const PROGRAM_ID = new anchor.web3.PublicKey(
  "AfDpoZn25onjqwoWVCZHjqfpC45MUPngbdZEFX9uTTqu",
);

const IDL_PATH = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  "../../idl/counter.json",
);

// Counter size: 8 bytes discriminator + 8 bytes count = 16 bytes
const COUNTER_SIZE = 16;

async function main(): Promise<void> {
  // Use localhost
  const url = "http://127.0.0.1:8899";
  const connection = new anchor.web3.Connection(url, "confirmed");
  
  const walletPath =
    process.env.ANCHOR_WALLET ||
    path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(
    JSON.parse(fs.readFileSync(walletPath, "utf8")),
  );
  const keypair = anchor.web3.Keypair.fromSecretKey(secret);
  const wallet = new anchor.Wallet(keypair);
  const provider = new anchor.AnchorProvider(connection, wallet, {
    commitment: "confirmed",
  });
  anchor.setProvider(provider);

  console.log("Wallet:", wallet.publicKey.toBase58());
  console.log("Program:", PROGRAM_ID.toBase58());

  // Load IDL
  const idl = JSON.parse(fs.readFileSync(IDL_PATH, "utf8"));
  const coder = new anchor.BorshCoder(idl);
  const instructionCoder = new anchor.BorshInstructionCoder(idl);

  // Create counter account
  const counter = anchor.web3.Keypair.generate();
  const lamports = await connection.getMinimumBalanceForRentExemption(COUNTER_SIZE);

  console.log("\n1. Creating counter account...");
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
  console.log("   Create account tx:", createSig);
  console.log("   Counter address:", counter.publicKey.toBase58());

  // Initialize counter
  console.log("\n2. Initializing counter with value 1...");
  const initData = instructionCoder.encode("initialize", {
    initial: new BN(1),
  });
  if (!initData) {
    throw new Error("Failed to encode initialize");
  }
  console.log("   Instruction data:", Buffer.from(initData).toString('hex'));
  console.log("   Discriminator:", Array.from(initData.slice(0, 8)));
  
  const initIx = new anchor.web3.TransactionInstruction({
    programId: PROGRAM_ID,
    data: initData,
    keys: [
      { pubkey: wallet.publicKey, isSigner: true, isWritable: true },
      { pubkey: counter.publicKey, isSigner: false, isWritable: true },
      { pubkey: anchor.web3.SystemProgram.programId, isSigner: false, isWritable: false },
    ],
  });
  
  const initSig = await provider.sendAndConfirm(
    new anchor.web3.Transaction().add(initIx),
    [],
  );
  console.log("   Initialize tx:", initSig);

  // Read counter
  let accountInfo = await connection.getAccountInfo(counter.publicKey);
  if (accountInfo) {
    const decoded = coder.accounts.decode("Counter", accountInfo.data);
    console.log("   Counter value:", decoded.count.toString());
  }

  // Increment counter
  console.log("\n3. Incrementing counter by 5...");
  const incData = instructionCoder.encode("increment", {
    amount: new BN(5),
  });
  if (!incData) {
    throw new Error("Failed to encode increment");
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
  console.log("   Increment tx:", incSig);

  // Read counter again
  accountInfo = await connection.getAccountInfo(counter.publicKey);
  if (accountInfo) {
    const decoded = coder.accounts.decode("Counter", accountInfo.data);
    console.log("   Counter value:", decoded.count.toString());
  }

  // Close counter
  console.log("\n4. Closing counter account...");
  const closeData = instructionCoder.encode("close", {});
  if (!closeData) {
    throw new Error("Failed to encode close");
  }
  
  const closeIx = new anchor.web3.TransactionInstruction({
    programId: PROGRAM_ID,
    data: closeData,
    keys: [
      { pubkey: wallet.publicKey, isSigner: true, isWritable: false },
      { pubkey: counter.publicKey, isSigner: false, isWritable: true },
      { pubkey: wallet.publicKey, isSigner: false, isWritable: true }, // destination
    ],
  });
  
  const closeSig = await provider.sendAndConfirm(
    new anchor.web3.Transaction().add(closeIx),
    [],
  );
  console.log("   Close tx:", closeSig);

  // Verify closed
  accountInfo = await connection.getAccountInfo(counter.publicKey);
  console.log("   Account closed:", accountInfo === null || accountInfo.lamports === 0);

  console.log("\n✅ All tests passed!");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
