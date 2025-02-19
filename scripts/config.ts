import { Connection, Keypair, PublicKey, Signer, TransactionInstruction } from '@solana/web3.js'
import bs58 from 'bs58';
import {
    EndpointProgram,
    buildVersionedTransaction,
} from '@layerzerolabs/lz-solana-sdk-v2'

import { GovernanceProgram } from '../src'

if (!process.env.SOLANA_PRIVATE_KEY) {
    throw new Error("SOLANA_PRIVATE_KEY env required");
}

const endpointProgram = new EndpointProgram.Endpoint(new PublicKey('76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6')) // endpoint program id, mainnet and testnet are the same

const governanceProgramId = process.env.GOVERNANCE_PROGRAM_ID
if (!governanceProgramId) {
    throw new Error("GOVERNANCE_PROGRAM_ID env required");
}

const governanceProgram = new GovernanceProgram.Governance(new PublicKey(governanceProgramId))

const connection = new Connection('https://api.devnet.solana.com')
const signer = Keypair.fromSecretKey (bs58.decode(process.env.SOLANA_PRIVATE_KEY))

;(async () => {
    await initGovernance(connection, signer, signer)
})()

async function initGovernance(connection: Connection, payer: Keypair, admin: Keypair): Promise<void> {
    const [governance] = governanceProgram.idPDA()
    let current = false
    try {
        await GovernanceProgram.accounts.Governance.fromAccountAddress(connection, governance, {
            commitment: 'confirmed',
        })
        current = true
    } catch (e) {
        // console.log('error when initializing governance', e)
        /*governance not initialized*/
    }
    const ix = await governanceProgram.initGovernance(
        connection,
        payer.publicKey,
        admin.publicKey, // admin/delegate double check it, is the same public key
        endpointProgram
    )
    if (ix == null) {
        console.log('initGovernance: already initialized');
        // already initialized
        return Promise.resolve()
    }
    sendAndConfirm(connection, [admin], [ix])
}

async function sendAndConfirm(
    connection: Connection,
    signers: Signer[],
    instructions: TransactionInstruction[]
): Promise<void> {
    const tx = await buildVersionedTransaction(connection, signers[0].publicKey, instructions, 'confirmed')
    tx.sign(signers)
    const hash = await connection.sendTransaction(tx, { skipPreflight: true })
    await connection.confirmTransaction(hash, 'confirmed')
}