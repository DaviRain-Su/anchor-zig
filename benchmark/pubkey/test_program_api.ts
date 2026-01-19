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
    programId: programId,
  });

  await sendAndConfirmTransaction(connection, new Transaction().add(createIx), [
    payer,
    testAccount,
  ]);

  return testAccount.publicKey;
}

async function main() {
  const programId = new PublicKey("4hyA3f1bb8m1LvVfQM9AMpY54KReAeK4aq6R2FkAyimX");
  const payer = await loadWallet();
  const account = await createProgramOwnedAccount(payer, programId);

  console.log("Testing zero-cu-program with 'check' instruction");
  console.log("Program ID:", programId.toBase58());
  console.log("Account:", account.toBase58());
  console.log("Discriminator:", anchorDisc("check").toString("hex"));

  const ix = new TransactionInstruction({
    programId: programId,
    keys: [{ pubkey: account, isSigner: false, isWritable: false }],
    data: anchorDisc("check"),
  });

  const tx = new Transaction().add(ix);
  tx.feePayer = payer.publicKey;
  tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;

  const simResult = await connection.simulateTransaction(tx);
  console.log("Simulation result err:", simResult.value.err);
  console.log("CU consumed:", simResult.value.unitsConsumed);
  console.log("Logs:", simResult.value.logs);
}

main().catch(console.error);
