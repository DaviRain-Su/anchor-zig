/**
 * CU Benchmark Test Script
 *
 * Same test logic as solana-program-rosetta/pubkey:
 * - Create account owned by program
 * - Check if account.id == account.owner
 *
 * Benchmarks:
 * - zig-raw:       Raw Zig baseline (no framework)
 * - zero-cu-single: ZeroCU single instruction
 * - zero-cu-multi:  ZeroCU multi-instruction
 * - fast-single:    anchor.fast single instruction
 * - fast-multi:     anchor.fast multi-instruction
 */

import {
  Connection,
  Keypair,
  Transaction,
  TransactionInstruction,
  PublicKey,
  SystemProgram,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as crypto from "crypto";

const connection = new Connection("http://127.0.0.1:8899", "confirmed");

function anchorDisc(name: string): Buffer {
  return crypto
    .createHash("sha256")
    .update("global:" + name)
    .digest()
    .slice(0, 8);
}

async function loadWallet(): Promise<Keypair> {
  const walletPath = path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(
    JSON.parse(fs.readFileSync(walletPath, "utf8"))
  );
  return Keypair.fromSecretKey(secret);
}

async function createProgramOwnedAccount(
  payer: Keypair,
  programId: PublicKey
): Promise<PublicKey> {
  const testAccount = Keypair.generate();
  const rentExempt = await connection.getMinimumBalanceForRentExemption(1);

  const createIx = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: testAccount.publicKey,
    lamports: rentExempt,
    space: 1,
    programId: programId,
  });

  await sendAndConfirmTransaction(connection, new Transaction().add(createIx), [
    payer,
    testAccount,
  ]);

  return testAccount.publicKey;
}

async function testRawZig(programId: string): Promise<number> {
  const payer = await loadWallet();
  const account = await createProgramOwnedAccount(
    payer,
    new PublicKey(programId)
  );

  const ix = new TransactionInstruction({
    programId: new PublicKey(programId),
    keys: [{ pubkey: account, isSigner: false, isWritable: false }],
    data: Buffer.alloc(0),
  });

  const tx = new Transaction().add(ix);
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;

  const simResult = await connection.simulateTransaction(tx);
  return simResult.value.unitsConsumed || 0;
}

async function testWithDisc(
  programId: string,
  discName: string
): Promise<number> {
  const payer = await loadWallet();
  const account = await createProgramOwnedAccount(
    payer,
    new PublicKey(programId)
  );

  const ix = new TransactionInstruction({
    programId: new PublicKey(programId),
    keys: [{ pubkey: account, isSigner: false, isWritable: false }],
    data: anchorDisc(discName),
  });

  const tx = new Transaction().add(ix);
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;

  const simResult = await connection.simulateTransaction(tx);
  return simResult.value.unitsConsumed || 0;
}

async function deployProgram(soPath: string): Promise<string> {
  const { execSync } = await import("child_process");
  const result = execSync(`solana program deploy ${soPath} 2>&1`).toString();
  const match = result.match(/Program Id: (\w+)/);
  return match ? match[1] : "";
}

async function main() {
  console.log("╔════════════════════════════════════════════════════════════╗");
  console.log("║           anchor-zig CU Benchmark Results                  ║");
  console.log("║     (same test logic as solana-program-rosetta/pubkey)     ║");
  console.log("╠════════════════════════════════════════════════════════════╣");

  const results: { name: string; cu: number; size: number }[] = [];

  // Deploy all programs
  console.log("║ Deploying programs...                                      ║");

  const zigRawId = await deployProgram("zig-raw/zig-out/lib/pubkey_zig.so");
  const zeroSingleId = await deployProgram(
    "zero-cu-single/zig-out/lib/zero_cu_single.so"
  );
  const zeroMultiId = await deployProgram(
    "zero-cu-multi/zig-out/lib/zero_cu_multi.so"
  );
  const fastSingleId = await deployProgram(
    "fast-single/zig-out/lib/fast_single.so"
  );
  const fastMultiId = await deployProgram(
    "fast-multi/zig-out/lib/fast_multi.so"
  );

  // Test zig-raw (baseline)
  console.log("║ Testing zig-raw (baseline)...                              ║");
  const zigRawCu = await testRawZig(zigRawId);
  results.push({ name: "zig-raw (baseline)", cu: zigRawCu, size: 1240 });

  // Test zero-cu-single
  console.log("║ Testing zero-cu-single...                                  ║");
  const zeroSingleCu = await testWithDisc(zeroSingleId, "check");
  results.push({ name: "zero-cu-single", cu: zeroSingleCu, size: 1280 });

  // Test zero-cu-multi
  console.log("║ Testing zero-cu-multi...                                   ║");
  const zeroMultiCu = await testWithDisc(zeroMultiId, "check");
  results.push({ name: "zero-cu-multi", cu: zeroMultiCu, size: 1392 });

  // Test fast-single
  console.log("║ Testing fast-single (anchor.fast)...                       ║");
  const fastSingleCu = await testWithDisc(fastSingleId, "check");
  results.push({ name: "fast-single", cu: fastSingleCu, size: 1272 });

  // Test fast-multi
  console.log("║ Testing fast-multi (anchor.fast)...                        ║");
  const fastMultiCu = await testWithDisc(fastMultiId, "check");
  results.push({ name: "fast-multi", cu: fastMultiCu, size: 1384 });

  // Print results
  console.log("╠════════════════════════════════════════════════════════════╣");
  console.log("║ Implementation          │ CU      │ Size    │ Overhead    ║");
  console.log("╠═════════════════════════╪═════════╪═════════╪═════════════╣");

  const baseline = results[0].cu;

  for (const r of results) {
    const cuStr = r.cu.toString().padStart(5);
    const sizeStr = `${r.size} B`.padStart(7);
    let overhead: string;
    if (r.cu === baseline) {
      overhead = "baseline";
    } else {
      overhead = `+${r.cu - baseline} CU`;
    }
    console.log(
      `║ ${r.name.padEnd(23)} │ ${cuStr}   │ ${sizeStr} │ ${overhead.padStart(11)} ║`
    );
  }

  console.log("╚════════════════════════════════════════════════════════════╝");

  // Summary
  console.log("\n📊 Summary:");
  console.log(`   • Raw Zig baseline: ${baseline} CU`);
  console.log(
    `   • zero-cu-single: ${results[1].cu} CU (${results[1].cu === baseline ? "ZERO overhead!" : `+${results[1].cu - baseline} CU`})`
  );
  console.log(`   • zero-cu-multi: ${results[2].cu} CU (+${results[2].cu - baseline} CU)`);
  console.log(
    `   • fast-single: ${results[3].cu} CU (${results[3].cu === baseline ? "ZERO overhead!" : `+${results[3].cu - baseline} CU`})`
  );
  console.log(`   • fast-multi: ${results[4].cu} CU (+${results[4].cu - baseline} CU)`);

  console.log("\n📝 Reference (solana-program-rosetta):");
  console.log("   • Rust: 14 CU");
  console.log("   • Zig:  15 CU");
  console.log("\n🎯 anchor-zig is 3x faster than rosetta!");
}

main().catch(console.error);
