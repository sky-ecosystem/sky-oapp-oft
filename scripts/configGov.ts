// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'

import { Connection, Keypair, PublicKey, Signer, TransactionInstruction, SimulatedTransactionResponse, SendTransactionError, ComputeBudgetProgram } from '@solana/web3.js'
import bs58 from 'bs58';
import {
    EndpointProgram,
    ExecutorPDADeriver,
    SetConfigType,
    UlnProgram,
    buildVersionedTransaction,
} from '@layerzerolabs/lz-solana-sdk-v2'
import { arrayify, hexZeroPad } from '@ethersproject/bytes'
import { GovernanceProgram } from '../src'
import { EndpointId } from '@layerzerolabs/lz-definitions';
import { types } from '../src/governance';

if (!process.env.SOLANA_PRIVATE_KEY) {
    throw new Error("SOLANA_PRIVATE_KEY env required");
}

const endpointProgram = new EndpointProgram.Endpoint(new PublicKey('76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6')) // endpoint program id, mainnet and testnet are the same
const ulnProgram = new UlnProgram.Uln(new PublicKey('7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH')) // uln program id, mainnet and testnet are the same
const executorProgram = new PublicKey('6doghB248px58JSSwG4qejQ46kFMW4AMj7vzJnWZHNZn') // executor program id, mainnet and testnet are the same

const governanceProgramId = process.env.GOVERNANCE_PROGRAM_ID
if (!governanceProgramId) {
    throw new Error("GOVERNANCE_PROGRAM_ID env required");
}

const governanceProgram = new GovernanceProgram.Governance(new PublicKey(governanceProgramId))

const connection = new Connection('https://api.devnet.solana.com')
const signer = Keypair.fromSecretKey (bs58.decode(process.env.SOLANA_PRIVATE_KEY))
const remotePeers: { [key in EndpointId]?: string } = {
    [EndpointId.AVALANCHE_V2_TESTNET]: '0x739f10f1E08d80Dc918b64770fbfd5155ed4b904',
}

const DEFAULT_COMMITMENT = 'finalized'

;(async () => {
    const [governance] = governanceProgram.idPDA()
    const addressLookupTable = new PublicKey('3uBhgRWPTPLfvfqxi4M9eVZC8nS1kDG9XPkdHKgG69nw')

    await initGovernance(connection, signer, signer, [
        {
            __kind: 'Address',
            fields: [governance],
        },
        {
            __kind: 'Address',
            fields: [addressLookupTable],
        },
    ], [addressLookupTable]);

    for (const [remoteStr, remotePeer] of Object.entries(remotePeers)) {
        const remotePeerBytes = arrayify(hexZeroPad(remotePeer, 32))
        const remote = parseInt(remoteStr) as EndpointId

        await setPeers(connection, signer, remote, remotePeerBytes)
        await initSendLibrary(connection, signer, remote)
        await initReceiveLibrary(connection, signer, remote)
        await initOAppNonce(connection, signer, remote, remotePeerBytes)
        await setSendLibrary(connection, signer, remote)
        await setReceiveLibrary(connection, signer, remote)
        await initUlnConfig(connection, signer, signer, remote)
        await setOAppExecutor(connection, signer, remote)
    }
})()

async function initGovernance(connection: Connection, payer: Keypair, admin: Keypair, lzReceiveTypesAccounts: types.AddressOrAltIndex[], lzReceiveTypesAccountsAlts: PublicKey[]): Promise<void> {
    const [governance] = governanceProgram.idPDA()
    console.log('governancePDA base58', governance.toBase58());
    console.log('governancePDA hex', '0x' + governance.toBuffer().toString('hex'));
    
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
        endpointProgram,
        lzReceiveTypesAccounts,
        lzReceiveTypesAccountsAlts,
    )
    if (ix == null) {
        console.log('initGovernance: already initialized');
        // already initialized
        return Promise.resolve()
    }
    await sendAndConfirm(connection, [admin], [ix])
}

async function setPeers(
    connection: Connection,
    admin: Keypair,
    remote: EndpointId,
    remotePeer: Uint8Array
): Promise<void> {
    const ix = governanceProgram.setRemote(admin.publicKey, remotePeer, remote)
    const [remotePDA] = governanceProgram.governanceDeriver.remote(remote)
    console.log('remotePDA', remotePDA.toBase58());
    let current = ''
    try {
        const info = await GovernanceProgram.accounts.Remote.fromAccountAddress(connection, remotePDA, {
            commitment: 'confirmed',
        })
        current = Buffer.from(info.address).toString('hex')
    } catch (e) {
        /*remote not init*/
    }
    if (current == Buffer.from(remotePeer).toString('hex')) {
        console.log('set_remote: already set');
        return Promise.resolve()
    }
    console.log('set_remote: changing peer')
    await sendAndConfirm(connection, [admin], [ix])
}

async function initUlnConfig(
    connection: Connection,
    payer: Keypair,
    admin: Keypair,
    remote: EndpointId
): Promise<void> {
    const [id] = governanceProgram.idPDA()

    const current = await ulnProgram.getSendConfigState(connection, id, remote)
    if (current) {
        console.log('initUlnConfig: already initialized')
        return Promise.resolve()
    }
    console.log('initUlnConfig: initializing')
    const ix = await endpointProgram.initOAppConfig(admin.publicKey, ulnProgram, payer.publicKey, id, remote)
    await sendAndConfirm(connection, [admin], [ix])
}

async function setOAppExecutor(connection: Connection, admin: Keypair, remote: EndpointId): Promise<void> {
    const [id] = governanceProgram.idPDA()
    const defaultOutboundMaxMessageSize = 10000

    const [executorPda] = new ExecutorPDADeriver(executorProgram).config()
    const expected: UlnProgram.types.ExecutorConfig = {
        maxMessageSize: defaultOutboundMaxMessageSize,
        executor: executorPda,
    }

    const current = (await ulnProgram.getSendConfigState(connection, id, remote))?.executor
    const ix = await endpointProgram.setOappConfig(connection, admin.publicKey, id, ulnProgram.program, remote, {
        configType: SetConfigType.EXECUTOR,
        value: expected,
    })
    if (
        current &&
        current.executor.toBase58() === expected.executor.toBase58() &&
        current.maxMessageSize === expected.maxMessageSize
    ) {
        console.log('setOappExecutor: already set');
        return Promise.resolve()
    }
    console.log('setOAppExecutor: setting')
    await sendAndConfirm(connection, [admin], [ix])
}

async function setSendLibrary(connection: Connection, admin: Keypair, remote: EndpointId): Promise<void> {
    console.log('setSendLibrary', {
        remote
    });
    const [idPDA] = governanceProgram.idPDA()
    const sendLib = await endpointProgram.getSendLibrary(connection, idPDA, remote)
    const current = sendLib ? sendLib.msgLib.toBase58() : ''
    const [expectedSendLib] = ulnProgram.deriver.messageLib()
    const expected = expectedSendLib.toBase58()

    if (current === expected) {
        console.log('setSendLibrary: already set', {
            idPDA: idPDA.toBase58(),
            current
        });
        return Promise.resolve()
    }
    console.log('setSendLibrary: setting')
    const ix = await endpointProgram.setSendLibrary(admin.publicKey, idPDA, ulnProgram.program, remote)
    await sendAndConfirm(connection, [admin], [ix])
}

async function setReceiveLibrary(connection: Connection, admin: Keypair, remote: EndpointId): Promise<void> {
    const [id] = governanceProgram.idPDA()
    const receiveLib = await endpointProgram.getReceiveLibrary(connection, id, remote)
    const current = receiveLib ? receiveLib.msgLib.toBase58() : ''
    const [expectedMessageLib] = ulnProgram.deriver.messageLib()
    const expected = expectedMessageLib.toBase58()
    if (current === expected) {
        console.log('setReceiveLibrary: already set', {
            idPDA: id.toBase58(),
            current
        });
        return Promise.resolve()
    }
    console.log('setReceiveLibrary: setting')
    const ix = await endpointProgram.setReceiveLibrary(admin.publicKey, id, ulnProgram.program, remote)
    await sendAndConfirm(connection, [admin], [ix])
}

async function initSendLibrary(connection: Connection, admin: Keypair, remote: EndpointId): Promise<void> {
    const [id] = governanceProgram.idPDA()

    const sendLib = await endpointProgram.getSendLibrary(connection, id, remote)

    const initialized = Boolean(sendLib?.programId);

    if (initialized) {
        console.log('initSendLibrary: already initialized')
        return Promise.resolve()
    }

    const ix = await endpointProgram.initSendLibrary(admin.publicKey, id, remote)
    if (ix == null) {
        console.log('initSendLibrary: already initialized')
        return Promise.resolve()
    }
    console.log('initSendLibrary: initializing')
    await sendAndConfirm(connection, [admin], [ix])
}

async function initReceiveLibrary(connection: Connection, admin: Keypair, remote: EndpointId): Promise<void> {
    const [id] = governanceProgram.idPDA()

    const recvLib = await endpointProgram.getReceiveLibrary(connection, id, remote)

    const initialized = Boolean(recvLib?.programId);

    if (initialized) {
        console.log('initReceiveLibrary: already initialized')
        return Promise.resolve()
    }

    const ix = await endpointProgram.initReceiveLibrary(admin.publicKey, id, remote)
    if (ix == null) {
        console.log('initReceiveLibrary: already initialized')
        return Promise.resolve()
    }
    console.log('initReceiveLibrary: initializing')
    await sendAndConfirm(connection, [admin], [ix])
}

async function initOAppNonce(
    connection: Connection,
    admin: Keypair,
    remote: EndpointId,
    remotePeer: Uint8Array
): Promise<void> {
    const [id] = governanceProgram.idPDA()
    const ix = await endpointProgram.initOAppNonce(admin.publicKey, remote, id, remotePeer)
    if (ix === null) {
        console.log('initOappNonce: ix === null, early exit');
        return Promise.resolve()
    }

    try {
        const nonce = await endpointProgram.getNonce(connection, id, remote, remotePeer)
        if (nonce) {
            console.log('initOappNonce: already set')
            return Promise.resolve()
        }
    } catch (e) {
        console.log('initOappNonce: nonce not initialized');
    }
    await sendAndConfirm(connection, [admin], [ix])
}

async function sendAndConfirm(
    connection: Connection,
    signers: Signer[],
    instructions: TransactionInstruction[]
): Promise<string> {
    const { blockhash } = await connection.getLatestBlockhash();
    const tx = await buildVersionedTransaction(
        connection, signers[0].publicKey, instructions, DEFAULT_COMMITMENT, blockhash,
    )
    tx.sign(signers)
    const hash = await connection.sendTransaction(tx)
    await connection.confirmTransaction(hash, DEFAULT_COMMITMENT)
    return hash
}

async function logSerializedTransaction(
    connection: Connection,
    signers: Signer[],
    instructions: TransactionInstruction[]
): Promise<void> {
    const { blockhash } = await connection.getLatestBlockhash();
    const tx = await buildVersionedTransaction(connection, signers[0].publicKey, instructions, DEFAULT_COMMITMENT, blockhash)
    tx.sign(signers)
    const serializedTx = Buffer.from(tx.serialize()).toString('base64');
    console.log('serialized transaction');
    console.log(serializedTx);
}

async function simulateTransaction(
    connection: Connection,
    signers: Signer[],
    instructions: TransactionInstruction[]
): Promise<SimulatedTransactionResponse> {
    const { blockhash } = await connection.getLatestBlockhash();
    const tx = await buildVersionedTransaction(connection, signers[0].publicKey, instructions, DEFAULT_COMMITMENT, blockhash)
    tx.sign(signers)
    const serializedTx = Buffer.from(tx.serialize()).toString('base64');

    const simulation = await connection.simulateTransaction(tx)
    return simulation.value
}
