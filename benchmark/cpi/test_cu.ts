/**
 * CPI Benchmark Test
 *
 * Tests CPI (Cross-Program Invocation) to system program's allocate.
 * Same as solana-program-rosetta/cpi
 */

import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  SystemProgram,
} from "@solana/web3.js";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as crypto from "crypto";
import { execSync } from "child_process";

const SIZE = 42;

function anchorDisc(name: string): Buffer {
  return crypto
    .createHash("sha256")
    .update("global:" + name)
    .digest()
    .slice(0, 8);
}

function deployProgram(soPath: string): string | null {
  if (!fs.existsSync(soPath)) return null;
  try {
    const result = execSync(`solana program deploy ${soPath} 2>&1`, {
      encoding: "utf8",
    });
    const match = result.match(/Program Id: (\w+)/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

async function testCpi(
  connection: Connection,
  payer: Keypair,
  programId: PublicKey,
  useDisc: boolean
): Promise<number> {
  // Find PDA with seed "You pass butter"
  const [pdaKey, bump] = PublicKey.findProgramAddressSync(
    [Buffer.from("You pass butter")],
    programId
  );

  // Fund the PDA so it can be allocated
  const rentExempt = await connection.getMinimumBalanceForRentExemption(SIZE);
  const fundTx = new Transaction().add(
    SystemProgram.transfer({
      fromPubkey: payer.publicKey,
      toPubkey: pdaKey,
      lamports: rentExempt,
    })
  );
  await connection.sendTransaction(fundTx, [payer]);
  await new Promise((r) => setTimeout(r, 500));

  // Build instruction data
  const data = useDisc
    ? Buffer.concat([anchorDisc("allocate"), Buffer.from([bump])])
    : Buffer.from([bump]);

  const ix = new TransactionInstruction({
    programId,
    keys: [
      { pubkey: pdaKey, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ],
    data,
  });

  const tx = new Transaction().add(ix);
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;

  const simResult = await connection.simulateTransaction(tx);
  if (simResult.value.err) {
    console.log("  Error:", simResult.value.err);
    console.log("  Logs:", simResult.value.logs);
  }
  return simResult.value.unitsConsumed || 0;
}

async function main() {
  const connection = new Connection("http://127.0.0.1:8899", "confirmed");
  const walletPath = path.join(os.homedir(), ".config", "solana", "id.json");
  const payer = Keypair.fromSecretKey(
    Uint8Array.from(JSON.parse(fs.readFileSync(walletPath, "utf8")))
  );

  const programs = [
    {
      name: "zig-raw (rosetta)",
      path: "zig-raw/zig-out/lib/cpi_zig.so",
      useDisc: false,
    },
    {
      name: "zero-cu (with disc)",
      path: "zero-cu/zig-out/lib/cpi_zero_cu.so",
      useDisc: true,
    },
  ];

  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║               CPI Benchmark - anchor-zig                     ║");
  console.log("║     (allocate PDA via system program invoke_signed)          ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const results: { name: string; cu: number; size: number }[] = [];

  for (const prog of programs) {
    if (!fs.existsSync(prog.path)) {
      console.log(`  ⚠ ${prog.name}: not found`);
      continue;
    }
    const size = fs.statSync(prog.path).size;
    const id = deployProgram(prog.path);
    if (!id) {
      console.log(`  ⚠ ${prog.name}: deploy failed`);
      continue;
    }

    console.log(`  Testing ${prog.name}...`);
    const cu = await testCpi(connection, payer, new PublicKey(id), prog.useDisc);
    results.push({ name: prog.name, cu, size });
    console.log(`  ✓ ${prog.name}: ${cu} CU (${size} B)`);
  }

  if (results.length >= 2) {
    const baseline = results[0].cu;
    console.log("\n┌─────────────────────────┬───────┬─────────┬──────────┐");
    console.log("│ API                     │ CU    │ Size    │ Overhead │");
    console.log("├─────────────────────────┼───────┼─────────┼──────────┤");
    for (const r of results) {
      const overhead =
        r.cu === baseline ? "baseline" : `+${r.cu - baseline} CU`;
      console.log(
        `│ ${r.name.padEnd(23)} │ ${r.cu.toString().padStart(5)} │ ${(r.size + " B").padStart(7)} │ ${overhead.padStart(8)} │`
      );
    }
    console.log("└─────────────────────────┴───────┴─────────┴──────────┘");
  }

  console.log("\n📝 Reference (solana-program-rosetta CPI):");
  console.log("   • Rust:     3698 CU (1198 minus syscalls)");
  console.log("   • Zig:      2967 CU (309 minus syscalls)");
  console.log("   • Pinocchio: 2802 CU (302 minus syscalls)");
  console.log("\n   Note: create_program_address = 1500 CU, invoke = 1000 CU");
}

main().catch(console.error);
