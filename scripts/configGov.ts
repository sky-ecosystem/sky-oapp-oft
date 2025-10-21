// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'

import { Connection, Keypair, PublicKey, Signer, TransactionInstruction, SimulatedTransactionResponse } from '@solana/web3.js'
import bs58 from 'bs58';
import {
    EndpointProgram,
    SetConfigType,
    UlnProgram,
    buildVersionedTransaction,
} from '@layerzerolabs/lz-solana-sdk-v2'
import { arrayify, hexZeroPad } from '@ethersproject/bytes'
import { EndpointId } from '@layerzerolabs/lz-definitions';

import { GovernanceProgram } from '../src'
import BN from 'bn.js';

if (!process.env.SOLANA_PRIVATE_KEY) {
    throw new Error("SOLANA_PRIVATE_KEY env required");
}

const endpointProgram = new EndpointProgram.Endpoint(new PublicKey('76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6')) // endpoint program id, mainnet and testnet are the same
const ulnProgram = new UlnProgram.Uln(new PublicKey('7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH')) // uln program id, mainnet and testnet are the same

const governanceProgramId = process.env.GOVERNANCE_PROGRAM_ID
if (!governanceProgramId) {
    throw new Error("GOVERNANCE_PROGRAM_ID env required");
}

if (!process.env.GOVERNANCE_CONTROLLER_ADDRESS) {
    throw new Error("GOVERNANCE_CONTROLLER_ADDRESS env required to specify your peer address");
}

const governanceProgram = new GovernanceProgram.Governance(new PublicKey(governanceProgramId), endpointProgram)

const connection = new Connection('https://api.devnet.solana.com')
const signer = Keypair.fromSecretKey(bs58.decode(process.env.SOLANA_PRIVATE_KEY))
const remotePeers: { [key in EndpointId]?: string } = {
    [EndpointId.AVALANCHE_V2_TESTNET]: process.env.GOVERNANCE_CONTROLLER_ADDRESS,
}

const DEFAULT_COMMITMENT = 'finalized'

const RECEIVE_ULN_CONFIG_REQUIRED_DVNS = [
    new PublicKey('4VDjp6XQaxoZf5RGwiPU9NR1EXSZn2TP4ATMmiSzLfhb'), // LayerZero Labs
    new PublicKey('29EKzmCscUg8mf4f5uskwMqvu2SXM8hKF1gWi1cCBoKT'), // P2P
].sort((a, b) => a.toBase58().localeCompare(b.toBase58()));

const RECEIVE_ULN_CONFIG: UlnProgram.types.UlnConfig = {
    confirmations: new BN(32),
    requiredDvnCount: RECEIVE_ULN_CONFIG_REQUIRED_DVNS.length,
    optionalDvnCount: 0,
    optionalDvnThreshold: 0,
    requiredDvns: RECEIVE_ULN_CONFIG_REQUIRED_DVNS,
    optionalDvns: [],
}

;(async () => {
    await initGovernance(connection, signer, signer);

    for (const [remoteStr, remotePeer] of Object.entries(remotePeers)) {
        const remotePeerBytes = arrayify(hexZeroPad(remotePeer, 32))
        const remote = parseInt(remoteStr) as EndpointId

        await setPeers(connection, signer, remote, remotePeerBytes)
        await initReceiveLibrary(connection, signer, remote)
        await initOAppNonce(connection, signer, remote, remotePeerBytes)
        await setReceiveLibrary(connection, signer, remote)
        await initReceiveConfig(connection, signer, signer, remote)
        await setReceiveConfig(connection, signer, remote)
    }
})()

async function initGovernance(connection: Connection, payer: Keypair, admin: Keypair, lzReceiveAlts: PublicKey[] = []): Promise<void> {
    const [governance] = governanceProgram.idPDA()
    console.log('governancePDA base58', governance.toBase58());
    console.log('governancePDA hex', '0x' + governance.toBuffer().toString('hex'));
    console.log('governance program id hex', '0x' + governanceProgram.program.toBuffer().toString('hex'));
    
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
        lzReceiveAlts
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

async function initReceiveConfig(
    connection: Connection,
    payer: Keypair,
    admin: Keypair,
    remote: EndpointId
): Promise<void> {
    const [id] = governanceProgram.idPDA()

    const current = await ulnProgram.getReceiveConfigState(connection, id, remote)
    if (current) {
        console.log('initReceiveConfig: already initialized')
        return Promise.resolve()
    }
    console.log('initReceiveConfig: initializing')
    const ix = await endpointProgram.initOAppConfig(admin.publicKey, ulnProgram, payer.publicKey, id, remote)
    await sendAndConfirm(connection, [admin], [ix])
}

async function setReceiveConfig(connection: Connection, admin: Keypair, remote: EndpointId): Promise<void> {
    const [id] = governanceProgram.idPDA()

    const currentReceiveConfig = (await ulnProgram.getReceiveConfigState(connection, id, remote))?.uln;

    if (!currentReceiveConfig) {
        throw new Error('No current receive config found');
    }

    if (equalULNConfig(currentReceiveConfig, RECEIVE_ULN_CONFIG)) {
        console.log('setReceiveConfig: already set');
        return Promise.resolve()
    }
    const ix = await endpointProgram.setOappConfig(connection, admin.publicKey, id, ulnProgram.program, remote, {
        configType: SetConfigType.RECEIVE_ULN,
        value: RECEIVE_ULN_CONFIG,
    })
    console.log('setReceiveConfig: setting')
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
        console.log('setReceiveLibrary: already set');
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

function equalULNConfig(config1: UlnProgram.types.UlnConfig, config2: UlnProgram.types.UlnConfig) {
    let confirmationsEqual = false;
    if (typeof config1.confirmations === 'number') {
        confirmationsEqual = config1.confirmations === config2.confirmations;
    } else {
        confirmationsEqual = config1.confirmations.eq(new BN(config2.confirmations));
    }

    return confirmationsEqual && config1.requiredDvnCount === config2.requiredDvnCount && config1.optionalDvnCount === config2.optionalDvnCount && config1.optionalDvnThreshold === config2.optionalDvnThreshold && config1.requiredDvns.length === config2.requiredDvns.length && config1.optionalDvns.length === config2.optionalDvns.length;
}
