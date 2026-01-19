/**
 * Pubkey Comparison CU Benchmark Test
 * 
 * Compares CU consumption for comparing account id with owner id.
 */

import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  SystemProgram,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as crypto from "node:crypto";

interface ProgramConfig {
  name: string;
  soPath: string;
  keypairPath: string;
  isAnchor: boolean;
}

function anchorDiscriminator(name: string): Buffer {
  const preimage = `global:${name}`;
  const hash = crypto.createHash("sha256").update(preimage).digest();
  return hash.subarray(0, 8);
}

async function getCU(connection: Connection, signature: string): Promise<number> {
  const tx = await connection.getTransaction(signature, {
    commitment: "confirmed",
    maxSupportedTransactionVersion: 0,
  });
  return tx?.meta?.computeUnitsConsumed || 0;
}

async function deployProgram(
  programPath: string,
  keypairPath: string
): Promise<PublicKey | null> {
  const { execSync } = await import("node:child_process");
  
  if (!fs.existsSync(programPath)) {
    return null;
  }
  
  if (!fs.existsSync(keypairPath)) {
    const kp = Keypair.generate();
    fs.writeFileSync(keypairPath, JSON.stringify(Array.from(kp.secretKey)));
  }
  
  try {
    execSync(
      `solana program deploy ${programPath} --program-id ${keypairPath} --url http://localhost:8899 2>&1`,
      { encoding: "utf8" }
    );
  } catch (err: any) {
    // Already deployed
  }
    
  const keypairData = JSON.parse(fs.readFileSync(keypairPath, "utf8"));
  const keypair = Keypair.fromSecretKey(Uint8Array.from(keypairData));
  return keypair.publicKey;
}

async function testPubkeyCompare(
  connection: Connection,
  payer: Keypair,
  programId: PublicKey,
  isAnchor: boolean
): Promise<number> {
  const testAccount = Keypair.generate();
  
  // Get minimum rent for 1 byte account
  const rentExempt = await connection.getMinimumBalanceForRentExemption(1);
  
  // Create account owned by program
  const createIx = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: testAccount.publicKey,
    lamports: rentExempt,
    space: 1,
    programId: programId,
  });
  
  await sendAndConfirmTransaction(connection, new Transaction().add(createIx), [payer, testAccount], {
    commitment: "confirmed",
  });
  
  // Build instruction data
  const data = isAnchor ? anchorDiscriminator("check") : Buffer.alloc(0);
  
  const ix = new TransactionInstruction({
    programId,
    keys: [
      { pubkey: testAccount.publicKey, isSigner: false, isWritable: false },
    ],
    data,
  });

  const tx = new Transaction().add(ix);
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;
  
  // Use simulateTransaction to get CU without sending
  const simResult = await connection.simulateTransaction(tx);
  
  if (simResult.value.err) {
    // Even failed txs consume CU
    return simResult.value.unitsConsumed || 0;
  }
  
  return simResult.value.unitsConsumed || 0;
}

async function main() {
  const url = "http://127.0.0.1:8899";
  const connection = new Connection(url, "confirmed");

  const walletPath = path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(JSON.parse(fs.readFileSync(walletPath, "utf8")));
  const payer = Keypair.fromSecretKey(secret);

  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║          Pubkey Comparison CU Benchmark - Anchor-Zig         ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const programs: ProgramConfig[] = [
    {
      name: "Raw Zig",
      soPath: "zig-raw/zig-out/lib/pubkey_zig.so",
      keypairPath: "/tmp/pubkey-zig-raw.json",
      isAnchor: false,
    },
    {
      name: "Anchor-Zig",
      soPath: "anchor-zig/zig-out/lib/pubkey_anchor.so",
      keypairPath: "/tmp/pubkey-anchor.json",
      isAnchor: true,
    },
  ];

  console.log("📦 Deploying programs...\n");
  
  const results: { name: string; cu: number; size: number }[] = [];
  
  for (const prog of programs) {
    const id = await deployProgram(prog.soPath, prog.keypairPath);
    if (!id) {
      console.log(`  ⚠ ${prog.name}: not found`);
      continue;
    }
    
    console.log(`  Testing ${prog.name}...`);
    const cu = await testPubkeyCompare(connection, payer, id, prog.isAnchor);
    const size = fs.statSync(prog.soPath).size;
    if (cu > 0) {
      results.push({ name: prog.name, cu, size });
      console.log(`  ✓ ${prog.name}: ${cu} CU (${(size / 1024).toFixed(1)} KB)`);
    }
  }

  if (results.length >= 2) {
    const raw = results[0];
    
    console.log("\n┌─────────────────┬──────────┬────────────┬──────────┐");
    console.log("│ Implementation  │ CU Usage │ Overhead   │ Size     │");
    console.log("├─────────────────┼──────────┼────────────┼──────────┤");
    
    for (const r of results) {
      const overhead = r.cu - raw.cu;
      const overheadStr = overhead === 0 ? "baseline" : `+${overhead} CU`;
      console.log(`│ ${r.name.padEnd(15)} │ ${r.cu.toString().padStart(8)} │ ${overheadStr.padStart(10)} │ ${(r.size / 1024).toFixed(1).padStart(5)} KB │`);
    }
    console.log("└─────────────────┴──────────┴────────────┴──────────┘");
  }

  console.log("\n📚 Reference (solana-program-rosetta):");
  console.log("┌─────────────────┬──────────┐");
  console.log("│ Implementation  │ CU Usage │");
  console.log("├─────────────────┼──────────┤");
  console.log("│ Rust            │       14 │");
  console.log("│ Zig             │       15 │");
  console.log("└─────────────────┴──────────┘");
}

main().catch(console.error);
