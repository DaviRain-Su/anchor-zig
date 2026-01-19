/**
 * HelloWorld CU Benchmark Test
 * 
 * Compares CU consumption between raw Zig and zero_cu
 */

import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as crypto from "node:crypto";
import { execSync } from "node:child_process";

interface ProgramConfig {
  name: string;
  soPath: string;
  data: Buffer;
}

function anchorDiscriminator(name: string): Buffer {
  const preimage = `global:${name}`;
  const hash = crypto.createHash("sha256").update(preimage).digest();
  return hash.subarray(0, 8);
}

function deployProgram(soPath: string): string | null {
  if (!fs.existsSync(soPath)) {
    return null;
  }
  
  try {
    const result = execSync(`solana program deploy ${soPath} 2>&1`, { encoding: "utf8" });
    const match = result.match(/Program Id: (\w+)/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

async function testProgram(
  connection: Connection,
  payer: Keypair,
  programId: PublicKey,
  data: Buffer
): Promise<number> {
  const ix = new TransactionInstruction({
    programId,
    keys: [],
    data,
  });

  const tx = new Transaction().add(ix);
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;

  const simResult = await connection.simulateTransaction(tx);
  return simResult.value.unitsConsumed || 0;
}

async function main() {
  const connection = new Connection("http://127.0.0.1:8899", "confirmed");

  const walletPath = path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(JSON.parse(fs.readFileSync(walletPath, "utf8")));
  const payer = Keypair.fromSecretKey(secret);

  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║           HelloWorld CU Benchmark - anchor-zig               ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const programs: ProgramConfig[] = [
    // With logging (to show syscall cost)
    {
      name: "zig-raw (with log)",
      soPath: "zig-raw/zig-out/lib/helloworld_zig.so",
      data: Buffer.alloc(0),
    },
    {
      name: "zero-cu (with log)",
      soPath: "zero-cu/zig-out/lib/helloworld_zero_cu.so",
      data: anchorDiscriminator("hello"),
    },
    // Without logging (pure overhead measurement)
    {
      name: "zig-raw-nolog",
      soPath: "zig-raw-nolog/zig-out/lib/helloworld_raw_nolog.so",
      data: Buffer.alloc(0),
    },
    {
      name: "zero-cu-nolog",
      soPath: "zero-cu-nolog/zig-out/lib/helloworld_nolog.so",
      data: anchorDiscriminator("hello"),
    },
  ];

  console.log("📦 Deploying and testing programs...\n");
  
  const results: { name: string; cu: number; size: number }[] = [];
  
  for (const prog of programs) {
    const size = fs.existsSync(prog.soPath) ? fs.statSync(prog.soPath).size : 0;
    if (size === 0) {
      console.log(`  ⚠ ${prog.name}: not found`);
      continue;
    }

    const id = deployProgram(prog.soPath);
    if (!id) {
      console.log(`  ⚠ ${prog.name}: deploy failed`);
      continue;
    }
    
    const cu = await testProgram(connection, payer, new PublicKey(id), prog.data);
    results.push({ name: prog.name, cu, size });
    console.log(`  ✓ ${prog.name}: ${cu} CU (${size} bytes)`);
  }

  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║ Implementation        │ CU      │ Size    │ Notes             ║");
  console.log("╠═══════════════════════╪═════════╪═════════╪═══════════════════╣");
  
  for (const r of results) {
    const notes = r.name.includes("log)") ? "~100 CU for sol_log_" : "pure overhead";
    console.log(`║ ${r.name.padEnd(21)} │ ${r.cu.toString().padStart(7)} │ ${(r.size + " B").padStart(7)} │ ${notes.padEnd(17)} ║`);
  }
  
  console.log("╚════════════════════════════════════════════════════════════════╝");

  // Find nolog versions for overhead calculation
  const rawNolog = results.find(r => r.name === "zig-raw-nolog");
  const zeroCuNolog = results.find(r => r.name === "zero-cu-nolog");
  
  if (rawNolog && zeroCuNolog) {
    console.log("\n📊 Framework Overhead (no logging):");
    console.log(`   • zig-raw-nolog (baseline): ${rawNolog.cu} CU`);
    console.log(`   • zero-cu-nolog: ${zeroCuNolog.cu} CU (+${zeroCuNolog.cu - rawNolog.cu} CU overhead)`);
    console.log("\n💡 Note: sol.log.log() syscall costs ~100 CU per call");
  }
}

main().catch(console.error);
