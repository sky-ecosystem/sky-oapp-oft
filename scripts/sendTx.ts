import { Connection, Keypair, PublicKey, Signer, TransactionInstruction, SimulatedTransactionResponse, VersionedTransaction } from '@solana/web3.js'
import bs58 from 'bs58';

const connection = new Connection('https://api.devnet.solana.com');

if (!process.env.SOLANA_PRIVATE_KEY) {
    throw new Error('SOLANA_PRIVATE_KEY is not set');
}

const signer = Keypair.fromSecretKey(bs58.decode(process.env.SOLANA_PRIVATE_KEY));

(async () => {
    const tx = VersionedTransaction.deserialize(
        Buffer.from(
            ""
        , "base64")
    );

    tx.message.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;

    tx.sign([signer]);

    const txHash = await connection.sendRawTransaction(tx.serialize());
    
    console.log(txHash);
})()