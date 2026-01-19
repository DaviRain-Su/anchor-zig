/**
 * CU Benchmark Test Script
 *
 * Same test logic as solana-program-rosetta/pubkey:
 * - Create account where owner = account's own pubkey
 * - Program checks: account.id == account.owner
 *
 * Note: On localnet we can't set owner = id directly, so we measure
 * CU consumption of the discriminator check + comparison logic.
 * The actual comparison will fail, but CU measurement is still valid.
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

/**
 * Create test account owned by program
 */
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
    programId: programId, // Owner = program
  });

  await sendAndConfirmTransaction(connection, new Transaction().add(createIx), [
    payer,
    testAccount,
  ]);

  return testAccount.publicKey;
}

/**
 * Measure CU for raw zig (no discriminator)
 */
async function testRawZig(programId: string): Promise<number> {
  const payer = await loadWallet();
  const account = await createProgramOwnedAccount(
    payer,
    new PublicKey(programId)
  );

  const ix = new TransactionInstruction({
    programId: new PublicKey(programId),
    keys: [{ pubkey: account, isSigner: false, isWritable: false }],
    data: Buffer.alloc(0), // No discriminator
  });

  const tx = new Transaction().add(ix);
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;

  const simResult = await connection.simulateTransaction(tx);
  // Will fail (id != owner) but we get CU
  return simResult.value.unitsConsumed || 0;
}

/**
 * Measure CU for ZeroCU (with discriminator)
 */
async function testZeroCU(
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

/**
 * Measure CU for Optimized entry (uses Signer)
 */
async function testOptimized(programId: string): Promise<number | null> {
  const payer = await loadWallet();

  const ix = new TransactionInstruction({
    programId: new PublicKey(programId),
    keys: [{ pubkey: payer.publicKey, isSigner: true, isWritable: false }],
    data: anchorDisc("check"),
  });

  const tx = new Transaction().add(ix);
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;

  const simResult = await connection.simulateTransaction(tx, [payer]);
  if (simResult.value.err) {
    return null;
  }
  return simResult.value.unitsConsumed || 0;
}

async function main() {
  console.log("╔════════════════════════════════════════════════════════════╗");
  console.log("║           anchor-zig CU Benchmark Results                  ║");
  console.log("║     (same test logic as solana-program-rosetta/pubkey)     ║");
  console.log("╠════════════════════════════════════════════════════════════╣");

  // Read program IDs
  const zigRawId = fs.readFileSync("/tmp/zig_raw_id", "utf8").trim();
  const zeroSingleId = fs.readFileSync("/tmp/zero_single_id", "utf8").trim();
  const zeroMultiId = fs.readFileSync("/tmp/zero_multi_id", "utf8").trim();
  const optMinimalId = fs.readFileSync("/tmp/opt_minimal_id", "utf8").trim();

  const results: { name: string; cu: number | null; size: number }[] = [];

  // Test zig-raw (baseline)
  console.log("║ Testing zig-raw (baseline)...                              ║");
  const zigRawCu = await testRawZig(zigRawId);
  results.push({ name: "zig-raw (baseline)", cu: zigRawCu, size: 1240 });

  // Test zero-cu-single
  console.log("║ Testing zero-cu-single...                                  ║");
  const zeroSingleCu = await testZeroCU(zeroSingleId, "check");
  results.push({ name: "zero-cu-single", cu: zeroSingleCu, size: 1280 });

  // Test zero-cu-multi (check)
  console.log("║ Testing zero-cu-multi (check)...                           ║");
  const zeroMultiCheckCu = await testZeroCU(zeroMultiId, "check");
  results.push({ name: "zero-cu-multi (check)", cu: zeroMultiCheckCu, size: 1392 });

  // Test zero-cu-multi (verify)
  console.log("║ Testing zero-cu-multi (verify)...                          ║");
  const zeroMultiVerifyCu = await testZeroCU(zeroMultiId, "verify");
  results.push({ name: "zero-cu-multi (verify)", cu: zeroMultiVerifyCu, size: 1392 });

  // Test optimized-minimal
  console.log("║ Testing optimized-minimal...                               ║");
  const optMinimalCu = await testOptimized(optMinimalId);
  results.push({ name: "optimized-minimal", cu: optMinimalCu, size: 1528 });

  // Print results
  console.log("╠════════════════════════════════════════════════════════════╣");
  console.log("║ Implementation          │ CU      │ Size    │ Overhead    ║");
  console.log("╠═════════════════════════╪═════════╪═════════╪═════════════╣");

  const baseline = results[0].cu || 0;

  for (const r of results) {
    const cuStr = r.cu !== null ? r.cu.toString().padStart(5) : "ERROR";
    const sizeStr = `${r.size} B`.padStart(7);
    let overhead: string;
    if (r.cu === null) {
      overhead = "-";
    } else if (r.cu === baseline) {
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
  if (results[1].cu !== null) {
    const overhead = results[1].cu - baseline;
    console.log(
      `   • ZeroCU single: ${results[1].cu} CU (${overhead === 0 ? "ZERO overhead!" : `+${overhead} CU overhead`})`
    );
  }
  if (results[2].cu !== null) {
    const overhead = results[2].cu - baseline;
    console.log(`   • ZeroCU multi: ${results[2].cu} CU (+${overhead} CU overhead)`);
  }
  if (results[4].cu !== null) {
    const overhead = results[4].cu - baseline;
    console.log(`   • Optimized: ${results[4].cu} CU (+${overhead} CU overhead)`);
  }

  console.log("\n📝 Reference (solana-program-rosetta):");
  console.log("   • Rust: 14 CU");
  console.log("   • Zig:  15 CU");
  console.log("\n💡 Note: CU includes program failure path (id != owner)");
}

main().catch(console.error);
