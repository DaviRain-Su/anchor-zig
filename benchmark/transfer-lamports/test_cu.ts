/**
 * Transfer Lamports CU Benchmark Test
 * 
 * Compares CU consumption for transferring lamports between accounts
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
import { execSync } from "node:child_process";

interface ProgramConfig {
  name: string;
  soPath: string;
  useDisc: boolean;
}

function anchorDiscriminator(name: string): Buffer {
  const preimage = `global:${name}`;
  const hash = crypto.createHash("sha256").update(preimage).digest();
  return hash.subarray(0, 8);
}

function buildInstructionData(amount: bigint, useDisc: boolean): Buffer {
  const amountBuf = Buffer.alloc(8);
  amountBuf.writeBigUInt64LE(amount);
  
  if (useDisc) {
    return Buffer.concat([anchorDiscriminator("transfer"), amountBuf]);
  }
  return amountBuf;
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

async function testTransfer(
  connection: Connection,
  payer: Keypair,
  programId: PublicKey,
  useDisc: boolean
): Promise<number> {
  // Create source account owned by the program
  const source = Keypair.generate();
  const destination = Keypair.generate();
  
  const sourceBalance = 1_000_000n; // 0.001 SOL
  const transferAmount = 500_000n;  // 0.0005 SOL
  
  // Create source account with lamports, owned by program
  const createSourceIx = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: source.publicKey,
    lamports: Number(sourceBalance),
    space: 0,
    programId: programId, // Owned by our program
  });
  
  // Create destination account
  const createDestIx = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: destination.publicKey,
    lamports: 0,
    space: 0,
    programId: SystemProgram.programId,
  });
  
  const setupTx = new Transaction().add(createSourceIx, createDestIx);
  await sendAndConfirmTransaction(connection, setupTx, [payer, source, destination], {
    commitment: "confirmed",
  });
  
  // Now do the transfer
  const data = buildInstructionData(transferAmount, useDisc);
  
  const transferIx = new TransactionInstruction({
    programId,
    keys: [
      { pubkey: source.publicKey, isSigner: true, isWritable: true },
      { pubkey: destination.publicKey, isSigner: false, isWritable: true },
    ],
    data,
  });

  const tx = new Transaction().add(transferIx);
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;
  tx.sign(payer, source);

  const simResult = await connection.simulateTransaction(tx);
  return simResult.value.unitsConsumed || 0;
}

async function main() {
  const connection = new Connection("http://127.0.0.1:8899", "confirmed");

  const walletPath = path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(JSON.parse(fs.readFileSync(walletPath, "utf8")));
  const payer = Keypair.fromSecretKey(secret);

  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║         Transfer Lamports CU Benchmark - anchor-zig          ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const programs: ProgramConfig[] = [
    {
      name: "zig-raw (baseline)",
      soPath: "zig-raw/zig-out/lib/transfer_zig.so",
      useDisc: false,
    },
    {
      name: "zero-cu",
      soPath: "zero-cu/zig-out/lib/transfer_zero_cu.so",
      useDisc: true,
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
    
    console.log(`  Testing ${prog.name}...`);
    const cu = await testTransfer(connection, payer, new PublicKey(id), prog.useDisc);
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
    
    console.log("\n📚 Reference (solana-program-rosetta transfer-lamports):");
    console.log("   • Rust:     459 CU");
    console.log("   • Zig:       37 CU");
    console.log("   • Pinocchio: 28 CU");
  }
}

main().catch(console.error);
