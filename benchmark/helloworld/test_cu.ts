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
  sendAndConfirmTransaction,
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
    {
      name: "zig-raw (baseline)",
      soPath: "zig-raw/zig-out/lib/helloworld_zig.so",
      data: Buffer.alloc(0),
    },
    {
      name: "zero-cu",
      soPath: "zero-cu/zig-out/lib/helloworld_zero_cu.so",
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

  if (results.length >= 2) {
    const baseline = results[0].cu;
    
    console.log("\n╔════════════════════════════════════════════════════════════╗");
    console.log("║ Implementation        │ CU      │ Size    │ Overhead      ║");
    console.log("╠═══════════════════════╪═════════╪═════════╪═══════════════╣");
    
    for (const r of results) {
      const overhead = r.cu === baseline ? "baseline" : `+${r.cu - baseline} CU`;
      console.log(`║ ${r.name.padEnd(21)} │ ${r.cu.toString().padStart(7)} │ ${(r.size + " B").padStart(7)} │ ${overhead.padStart(13)} ║`);
    }
    
    console.log("╚════════════════════════════════════════════════════════════╝");
    
    console.log("\n📊 Summary:");
    console.log(`   • Raw Zig baseline: ${results[0].cu} CU`);
    console.log(`   • zero-cu: ${results[1].cu} CU (+${results[1].cu - results[0].cu} CU overhead)`);
    
    console.log("\n📚 Reference (solana-program-rosetta helloworld):");
    console.log("   • Rust: 105 CU");
    console.log("   • Zig:  105 CU");
  }
}

main().catch(console.error);
