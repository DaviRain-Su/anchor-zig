/**
 * HelloWorld CU Benchmark Test
 * 
 * Compares CU consumption between different implementations:
 * - Raw Zig (no framework)
 * - Anchor-Zig (framework with DSL)
 * - Anchor-Zig Minimal (framework without DSL)
 * 
 * Run from benchmark/helloworld directory:
 *   npx tsx test_cu.ts
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
}

// Generate anchor discriminator
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
): Promise<PublicKey> {
  const { execSync } = await import("node:child_process");
  
  // Create keypair if doesn't exist
  if (!fs.existsSync(keypairPath)) {
    const kp = Keypair.generate();
    fs.writeFileSync(keypairPath, JSON.stringify(Array.from(kp.secretKey)));
  }
  
  // Deploy using solana CLI
  try {
    const result = execSync(
      `solana program deploy ${programPath} --program-id ${keypairPath} --url http://localhost:8899 2>&1`,
      { encoding: "utf8" }
    );
    const match = result.match(/Program Id: (\w+)/);
    if (match) {
      console.log(`  ✓ ${path.basename(programPath)}: ${match[1]}`);
    }
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
  name: string,
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

  // Load wallet
  const walletPath = path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(JSON.parse(fs.readFileSync(walletPath, "utf8")));
  const payer = Keypair.fromSecretKey(secret);

  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║           HelloWorld CU Benchmark - Anchor-Zig               ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  // Program configurations
  const programs: ProgramConfig[] = [
    {
      name: "Raw Zig (baseline)",
      soPath: "zig-raw/zig-out/lib/helloworld_zig.so",
      keypairPath: "/tmp/helloworld-zig-raw-keypair.json",
      data: Buffer.alloc(0),
    },
    {
      name: "Anchor-Zig",
      soPath: "anchor-zig/zig-out/lib/helloworld_anchor.so",
      keypairPath: "/tmp/helloworld-anchor-zig-keypair.json",
      data: anchorDiscriminator("hello"),
    },
  ];

  // Deploy programs
  console.log("📦 Deploying programs...\n");
  const programIds: Map<string, PublicKey> = new Map();
  
  for (const prog of programs) {
    if (fs.existsSync(prog.soPath)) {
      const id = await deployProgram(prog.soPath, prog.keypairPath);
      programIds.set(prog.name, id);
    } else {
      console.log(`  ⚠ ${prog.name}: not found`);
    }
  }

  // Run tests
  console.log("\n📊 CU Measurements:\n");
  
  const results: { name: string; cu: number; size: number }[] = [];
  
  for (const prog of programs) {
    const id = programIds.get(prog.name);
    if (!id) continue;
    
    const cu = await testProgram(connection, payer, id, prog.name, prog.data);
    const size = fs.existsSync(prog.soPath) ? fs.statSync(prog.soPath).size : 0;
    results.push({ name: prog.name, cu, size });
    console.log(`  ${prog.name}: ${cu} CU (${(size / 1024).toFixed(1)} KB)`);
  }

  // Summary table
  const baseline = results.find(r => r.name.includes("Raw"))?.cu || 105;
  
  console.log("\n┌────────────────────────┬──────────┬───────────┬──────────┐");
  console.log("│ Implementation         │ CU Usage │ Overhead  │ Size     │");
  console.log("├────────────────────────┼──────────┼───────────┼──────────┤");
  
  for (const r of results) {
    const overhead = r.cu - baseline;
    const overheadStr = overhead === 0 ? "baseline" : `+${overhead} CU`;
    console.log(
      `│ ${r.name.padEnd(22)} │ ${r.cu.toString().padStart(8)} │ ${overheadStr.padStart(9)} │ ${(r.size / 1024).toFixed(1).padStart(5)} KB │`
    );
  }
  
  console.log("└────────────────────────┴──────────┴───────────┴──────────┘");

  // Reference comparison
  console.log("\n📚 Reference (solana-program-rosetta):\n");
  console.log("┌────────────────────────┬──────────┐");
  console.log("│ Implementation         │ CU Usage │");
  console.log("├────────────────────────┼──────────┤");
  console.log("│ Rust                   │      105 │");
  console.log("│ Zig                    │      105 │");
  console.log("│ C                      │      105 │");
  console.log("│ Assembly               │      104 │");
  console.log("└────────────────────────┴──────────┘");
  
  // Analysis
  const anchorResult = results.find(r => r.name.includes("Anchor"));
  if (anchorResult) {
    const overhead = anchorResult.cu - baseline;
    const overheadPct = (overhead / baseline * 100).toFixed(1);
    console.log(`\n✅ Anchor-Zig framework overhead: ${overhead} CU (${overheadPct}%)`);
    console.log("   This includes: discriminator parsing + dispatch + context creation");
  }
}

main().catch(console.error);
