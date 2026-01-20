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

function anchorDiscriminator(name: string): Buffer {
  const preimage = `global:${name}`;
  const hash = crypto.createHash("sha256").update(preimage).digest();
  return hash.subarray(0, 8);
}

async function main() {
  const connection = new Connection("http://127.0.0.1:8899", "confirmed");
  const walletPath = path.join(os.homedir(), ".config", "solana", "id.json");
  const secret = Uint8Array.from(JSON.parse(fs.readFileSync(walletPath, "utf8")));
  const payer = Keypair.fromSecretKey(secret);

  // zero-cu-program deployed ID
  const programId = new PublicKey("Ah2zr9B17u8G3oDJr56VagFnuYt28ZDXs8sFCvegosy3");
  const data = anchorDiscriminator("hello");
  
  console.log("Testing helloworld zero-cu-program...");
  console.log("Program:", programId.toBase58());
  console.log("Discriminator:", Array.from(data));

  const ix = new TransactionInstruction({
    programId,
    keys: [],
    data,
  });

  const tx = new Transaction().add(ix);
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;

  const simResult = await connection.simulateTransaction(tx);
  console.log("\nSimulation result:");
  console.log("  CU consumed:", simResult.value.unitsConsumed);
  console.log("  Logs:", simResult.value.logs);
  
  if (simResult.value.err) {
    console.log("  Error:", simResult.value.err);
  } else {
    console.log("\n✅ Success!");
  }
}

main().catch(console.error);
