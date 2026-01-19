/**
 * Token CPI Benchmark
 * 
 * Tests programs that call the real SPL Token Program via CPI.
 * This is how anchor.spl.token is meant to be used.
 */

import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  sendAndConfirmTransaction,
  SystemProgram,
} from "@solana/web3.js";
import {
  TOKEN_PROGRAM_ID,
  MINT_SIZE,
  getMinimumBalanceForRentExemptMint,
  createInitializeMintInstruction,
  getMinimumBalanceForRentExemptAccount,
  ACCOUNT_SIZE,
  createInitializeAccountInstruction,
  createMintToInstruction,
} from "@solana/spl-token";
import { execSync } from "child_process";
import * as fs from "fs";

const connection = new Connection("http://localhost:8899", "confirmed");

// Our program's discriminators
const TRANSFER_DISC = Buffer.from([0x1c, 0xe7, 0xb0, 0x12, 0xa0, 0xd8, 0xa8, 0xf3]);
const MINT_TO_DISC = Buffer.from([0x9e, 0x0d, 0x1c, 0x2b, 0x4a, 0x8f, 0x3f, 0x6e]);
const BURN_DISC = Buffer.from([0x90, 0x78, 0x6f, 0x5e, 0x4d, 0x3c, 0x2b, 0x1a]);
const CLOSE_DISC = Buffer.from([0xba, 0xdc, 0xfe, 0x21, 0x43, 0x65, 0x87, 0x09]);

interface ProgramInfo {
  name: string;
  path: string;
}

const PROGRAMS: ProgramInfo[] = [
  { name: "anchor-spl", path: "./anchor-spl/zig-out/lib/token_cpi_anchor_spl.so" },
];

function deployProgram(programPath: string): string | null {
  try {
    const keypairPath = programPath.replace(".so", "-keypair.json");
    if (!fs.existsSync(keypairPath)) {
      const keypair = Keypair.generate();
      fs.writeFileSync(keypairPath, JSON.stringify(Array.from(keypair.secretKey)));
    }
    
    const result = execSync(
      `solana program deploy --program-id ${keypairPath} ${programPath} 2>&1`,
      { encoding: "utf-8" }
    );
    
    const match = result.match(/Program Id: ([A-Za-z0-9]+)/);
    return match ? match[1] : null;
  } catch (e) {
    console.error(`  Deploy failed: ${e}`);
    return null;
  }
}

function createTransferIx(
  programId: PublicKey,
  source: PublicKey,
  destination: PublicKey,
  authority: PublicKey,
  amount: bigint
): TransactionInstruction {
  const data = Buffer.alloc(16);
  TRANSFER_DISC.copy(data, 0);
  data.writeBigUInt64LE(amount, 8);
  
  return new TransactionInstruction({
    keys: [
      { pubkey: source, isSigner: false, isWritable: true },
      { pubkey: destination, isSigner: false, isWritable: true },
      { pubkey: authority, isSigner: true, isWritable: false },
      { pubkey: TOKEN_PROGRAM_ID, isSigner: false, isWritable: false },
    ],
    programId,
    data,
  });
}

async function measureCU(
  payer: Keypair,
  ix: TransactionInstruction,
  signers: Keypair[]
): Promise<number> {
  try {
    const tx = new Transaction().add(ix);
    const sim = await connection.simulateTransaction(tx, [payer, ...signers]);
    return sim.value.unitsConsumed || -1;
  } catch (e: any) {
    console.error(`  Transaction error: ${e.message}`);
    if (e.logs) {
      console.error(`  Logs: ${JSON.stringify(e.logs, null, 2)}`);
    }
    return -1;
  }
}

async function runBenchmarks() {
  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║       Token CPI Benchmark - Using anchor.spl.token           ║");
  console.log("║  (Programs that call the real SPL Token Program via CPI)     ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const payer = Keypair.generate();
  
  // Airdrop SOL
  const sig = await connection.requestAirdrop(payer.publicKey, 10e9);
  await connection.confirmTransaction(sig);

  const results: { name: string; cu: Record<string, number>; size: number }[] = [];

  for (const program of PROGRAMS) {
    if (!fs.existsSync(program.path)) {
      console.log(`  Skipping ${program.name} (not built)`);
      continue;
    }

    console.log(`  Deploying ${program.name}...`);
    const size = fs.statSync(program.path).size;
    const programIdStr = deployProgram(program.path);
    
    if (!programIdStr) {
      console.log(`  ✗ ${program.name}: deploy failed`);
      continue;
    }

    const programId = new PublicKey(programIdStr);
    console.log(`  Program ID: ${programId.toBase58()}`);

    const cu: Record<string, number> = {};

    try {
      // Create real SPL Token mint
      const mintKp = Keypair.generate();
      const mintRent = await getMinimumBalanceForRentExemptMint(connection);
      
      const createMintTx = new Transaction().add(
        SystemProgram.createAccount({
          fromPubkey: payer.publicKey,
          newAccountPubkey: mintKp.publicKey,
          lamports: mintRent,
          space: MINT_SIZE,
          programId: TOKEN_PROGRAM_ID,
        }),
        createInitializeMintInstruction(
          mintKp.publicKey,
          9, // decimals
          payer.publicKey, // mint authority
          null // freeze authority
        )
      );
      await sendAndConfirmTransaction(connection, createMintTx, [payer, mintKp]);
      console.log(`  Mint: ${mintKp.publicKey.toBase58()}`);

      // Create source token account
      const sourceKp = Keypair.generate();
      const accountRent = await getMinimumBalanceForRentExemptAccount(connection);
      
      const createSourceTx = new Transaction().add(
        SystemProgram.createAccount({
          fromPubkey: payer.publicKey,
          newAccountPubkey: sourceKp.publicKey,
          lamports: accountRent,
          space: ACCOUNT_SIZE,
          programId: TOKEN_PROGRAM_ID,
        }),
        createInitializeAccountInstruction(
          sourceKp.publicKey,
          mintKp.publicKey,
          payer.publicKey
        )
      );
      await sendAndConfirmTransaction(connection, createSourceTx, [payer, sourceKp]);
      
      // Create destination token account
      const destKp = Keypair.generate();
      const createDestTx = new Transaction().add(
        SystemProgram.createAccount({
          fromPubkey: payer.publicKey,
          newAccountPubkey: destKp.publicKey,
          lamports: accountRent,
          space: ACCOUNT_SIZE,
          programId: TOKEN_PROGRAM_ID,
        }),
        createInitializeAccountInstruction(
          destKp.publicKey,
          mintKp.publicKey,
          payer.publicKey
        )
      );
      await sendAndConfirmTransaction(connection, createDestTx, [payer, destKp]);
      
      // Mint tokens to source
      const mintToTx = new Transaction().add(
        createMintToInstruction(
          mintKp.publicKey,
          sourceKp.publicKey,
          payer.publicKey, // mint authority
          1000000000n
        )
      );
      await sendAndConfirmTransaction(connection, mintToTx, [payer]);

      const sourceAccount = sourceKp.publicKey;
      const destAccount = destKp.publicKey;

      // Test Transfer CPI
      const transferIx = createTransferIx(
        programId,
        sourceAccount,
        destAccount,
        payer.publicKey,
        100n
      );
      cu["transfer_cpi"] = await measureCU(payer, transferIx, []);

      results.push({ name: program.name, cu, size });
      console.log(`  ✓ ${program.name}: transfer_cpi=${cu.transfer_cpi} CU (${size} B)`);
    } catch (e) {
      console.error(`  ✗ ${program.name}: ${e}`);
    }
  }

  // Print results
  console.log("\n┌─────────────────────┬──────────────┬─────────┐");
  console.log("│ Implementation      │ Transfer CPI │ Size    │");
  console.log("├─────────────────────┼──────────────┼─────────┤");
  for (const r of results) {
    const name = r.name.padEnd(19);
    const transfer = r.cu.transfer_cpi.toString().padStart(12);
    const size = `${r.size} B`.padStart(7);
    console.log(`│ ${name} │ ${transfer} │ ${size} │`);
  }
  console.log("└─────────────────────┴──────────────┴─────────┘");

  console.log("\n📝 Note:");
  console.log("   This benchmark measures programs that CALL the real SPL Token");
  console.log("   Program via CPI, not programs that implement SPL Token.");
  console.log("");
  console.log("   CPI adds overhead (~5000+ CU) for the invoke syscall and");
  console.log("   cross-program execution. This is expected behavior.");
}

runBenchmarks().catch(console.error);
