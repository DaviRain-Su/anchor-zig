/**
 * HelloWorld CU Benchmark Test
 * 
 * Compares CU consumption between raw Zig and Anchor-Zig
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

interface ProgramConfig {
  name: string;
  soPath: string;
  keypairPath: string;
  data: Buffer;
  description: string;
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
  const signature = await sendAndConfirmTransaction(connection, tx, [payer], {
    commitment: "confirmed",
  });

  return await getCU(connection, signature);
}

async function main() {
  const url = "http://127.0.0.1:8899";
  const connection = new Connection(url, "confirmed");

  const walletPath = path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(JSON.parse(fs.readFileSync(walletPath, "utf8")));
  const payer = Keypair.fromSecretKey(secret);

  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║           HelloWorld CU Benchmark - Anchor-Zig               ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const disc = anchorDiscriminator("hello");

  const programs: ProgramConfig[] = [
    {
      name: "Raw Zig",
      soPath: "zig-raw/zig-out/lib/helloworld_zig.so",
      keypairPath: "/tmp/hw-raw.json",
      data: Buffer.alloc(0),
      description: "Baseline: just sol_log_",
    },
    {
      name: "Anchor-Zig",
      soPath: "anchor-zig/zig-out/lib/helloworld_anchor.so",
      keypairPath: "/tmp/hw-anchor.json",
      data: disc,
      description: "Full framework with Context",
    },
  ];

  console.log("📦 Deploying programs...\n");
  
  const results: { name: string; cu: number; size: number; desc: string }[] = [];
  
  for (const prog of programs) {
    const id = await deployProgram(prog.soPath, prog.keypairPath);
    if (!id) {
      console.log(`  ⚠ ${prog.name}: not found`);
      continue;
    }
    
    const cu = await testProgram(connection, payer, id, prog.data);
    const size = fs.statSync(prog.soPath).size;
    results.push({ name: prog.name, cu, size, desc: prog.description });
    console.log(`  ✓ ${prog.name}: ${cu} CU (${(size / 1024).toFixed(1)} KB)`);
  }

  if (results.length >= 2) {
    const raw = results[0];
    const anchor = results[1];
    const overhead = anchor.cu - raw.cu;
    
    console.log("\n┌─────────────────┬──────────┬────────────┬──────────────────────────────┐");
    console.log("│ Implementation  │ CU Usage │ Overhead   │ Description                  │");
    console.log("├─────────────────┼──────────┼────────────┼──────────────────────────────┤");
    console.log(`│ ${raw.name.padEnd(15)} │ ${raw.cu.toString().padStart(8)} │   baseline │ ${raw.desc.padEnd(28)} │`);
    console.log(`│ ${anchor.name.padEnd(15)} │ ${anchor.cu.toString().padStart(8)} │    +${overhead} CU │ ${anchor.desc.padEnd(28)} │`);
    console.log("└─────────────────┴──────────┴────────────┴──────────────────────────────┘");
    
    console.log("\n📊 Overhead Breakdown:");
    console.log(`   Discriminator check (Anchor protocol): ~20 CU (unavoidable)`);
    console.log(`   Framework overhead (dispatch/context): ~${overhead - 20} CU`);
    console.log(`   ─────────────────────────────────────────────`);
    console.log(`   Total overhead: ${overhead} CU (${(overhead / raw.cu * 100).toFixed(1)}%)`);
    
    console.log("\n📚 Reference (solana-program-rosetta):");
    console.log("   Rust: 105 CU | Zig: 105 CU | C: 105 CU | Assembly: 104 CU");
  }
}

main().catch(console.error);
