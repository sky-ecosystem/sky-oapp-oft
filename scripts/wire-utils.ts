import { Connection, Keypair, PublicKey, Signer, TransactionInstruction, SimulatedTransactionResponse, Commitment } from '@solana/web3.js'
import {
    EndpointProgram,
    SetConfigType,
    UlnProgram,
    buildVersionedTransaction,
} from '@layerzerolabs/lz-solana-sdk-v2'
import { EndpointId } from '@layerzerolabs/lz-definitions';
import BN from 'bn.js';

import { GovernancePDADeriver, GovernanceProgram } from '../src'
import { arrayify, hexZeroPad } from 'ethers/lib/utils';

export type LAYERZERO_PROGRAMS = {
    endpointProgram: EndpointProgram.Endpoint;
    governanceProgram: GovernanceProgram.Governance;
    ulnProgram: UlnProgram.Uln;
}

type CustomWireUtilsConfiguration = {
    commitment: Commitment;
    validationOnly: boolean;
}

export async function initGovernance(connection: Connection, programs: LAYERZERO_PROGRAMS, payer: Keypair, admin: Keypair, lzReceiveAlts: PublicKey[] = [], { commitment, validationOnly }: CustomWireUtilsConfiguration = { commitment: 'finalized', validationOnly: false }): Promise<void> {
    const [governance] = programs.governanceProgram.idPDA()
    console.log('governancePDA base58', governance.toBase58());
    console.log('governancePDA hex', '0x' + governance.toBuffer().toString('hex'));
    console.log('governance program id hex', '0x' + programs.governanceProgram.program.toBuffer().toString('hex'));
    
    try {
        await GovernanceProgram.accounts.Governance.fromAccountAddress(connection, governance, {
            commitment,
        })
    } catch (e) {
        /*governance not initialized*/
    }

    const ix = await programs.governanceProgram.initGovernance(
        connection,
        payer.publicKey,
        admin.publicKey, // admin/delegate double check it, is the same public key
        lzReceiveAlts
    )
    if (ix === null) {
        console.log('initGovernance: already initialized');
        return Promise.resolve()
    }

    if (!validationOnly) {
        await sendAndConfirm(connection, [admin], [ix], commitment)
    }
}

export async function setPeers(
    connection: Connection,
    programs: LAYERZERO_PROGRAMS,
    admin: Keypair,
    remote: EndpointId,
    remotePeer: Uint8Array,
    { commitment, validationOnly }: CustomWireUtilsConfiguration = { commitment: 'finalized', validationOnly: false }
): Promise<void> {
    const ix = programs.governanceProgram.setRemote(admin.publicKey, remotePeer, remote)
    const [remotePDA] = programs.governanceProgram.governanceDeriver.remote(remote)
    let current = ''
    try {
        const info = await GovernanceProgram.accounts.Remote.fromAccountAddress(connection, remotePDA, {
            commitment,
        })
        current = Buffer.from(info.address).toString('hex')
    } catch (e) {
        /*remote not init*/
    }
    if (current == Buffer.from(remotePeer).toString('hex')) {
        console.log('setRemote: already set');
        return Promise.resolve()
    }

    if (!validationOnly) {
        console.log('setRemote: changing peer')
        await sendAndConfirm(connection, [admin], [ix], commitment)
    }
}

export async function initReceiveConfig(
    connection: Connection,
    programs: LAYERZERO_PROGRAMS,
    payer: Keypair,
    admin: Keypair,
    remote: EndpointId,
    commitment: Commitment = 'finalized'
): Promise<void> {
    const [id] = programs.governanceProgram.idPDA()

    const current = await programs.ulnProgram.getReceiveConfigState(connection, id, remote)
    if (current) {
        console.log('initReceiveConfig: already initialized')
        return Promise.resolve()
    }
    console.log('initReceiveConfig: initializing')
    const ix = await programs.endpointProgram.initOAppConfig(admin.publicKey, programs.ulnProgram, payer.publicKey, id, remote)
    await sendAndConfirm(connection, [admin], [ix], commitment)
}

export async function setReceiveConfig(connection: Connection, programs: LAYERZERO_PROGRAMS, admin: Keypair, remote: EndpointId, receiveULNConfig: UlnProgram.types.UlnConfig, commitment: Commitment = 'finalized'): Promise<void> {
    const [id] = programs.governanceProgram.idPDA()

    const currentReceiveConfig = (await programs.ulnProgram.getReceiveConfigState(connection, id, remote))?.uln;

    if (!currentReceiveConfig) {
        throw new Error('No current receive config found');
    }

    if (equalULNConfig(currentReceiveConfig, receiveULNConfig)) {
        console.log('setReceiveConfig: already set');
        return Promise.resolve()
    }
    const ix = await programs.endpointProgram.setOappConfig(connection, admin.publicKey, id, programs.ulnProgram.program, remote, {
        configType: SetConfigType.RECEIVE_ULN,
        value: receiveULNConfig,
    })
    console.log('setReceiveConfig: setting')
    await sendAndConfirm(connection, [admin], [ix], commitment)
}

export async function setSendLibrary(connection: Connection, programs: LAYERZERO_PROGRAMS, admin: Keypair, remote: EndpointId, commitment: Commitment = 'finalized'): Promise<void> {
    console.log('setSendLibrary', {
        remote
    });
    const [idPDA] = programs.governanceProgram.idPDA()
    const sendLib = await programs.endpointProgram.getSendLibrary(connection, idPDA, remote)
    const current = sendLib ? sendLib.msgLib.toBase58() : ''
    const [expectedSendLib] = programs.ulnProgram.deriver.messageLib()
    const expected = expectedSendLib.toBase58()

    if (current === expected) {
        console.log('setSendLibrary: already set', {
            idPDA: idPDA.toBase58(),
            current
        });
        return Promise.resolve()
    }
    console.log('setSendLibrary: setting')
    const ix = await programs.endpointProgram.setSendLibrary(admin.publicKey, idPDA, programs.ulnProgram.program, remote)
    await sendAndConfirm(connection, [admin], [ix], commitment)
}

export async function setReceiveLibrary(connection: Connection, programs: LAYERZERO_PROGRAMS, admin: Keypair, remote: EndpointId, commitment: Commitment = 'finalized'): Promise<void> {
    const [id] = programs.governanceProgram.idPDA()
    const receiveLib = await programs.endpointProgram.getReceiveLibrary(connection, id, remote)
    const current = receiveLib ? receiveLib.msgLib.toBase58() : ''
    const [expectedMessageLib] = programs.ulnProgram.deriver.messageLib()
    const expected = expectedMessageLib.toBase58()
    if (current === expected) {
        console.log('setReceiveLibrary: already set');
        return Promise.resolve()
    }
    console.log('setReceiveLibrary: setting')
    const ix = await programs.endpointProgram.setReceiveLibrary(admin.publicKey, id, programs.ulnProgram.program, remote)
    await sendAndConfirm(connection, [admin], [ix], commitment)
}

export async function initSendLibrary(connection: Connection, programs: LAYERZERO_PROGRAMS, admin: Keypair, remote: EndpointId, commitment: Commitment = 'finalized'): Promise<void> {
    const [id] = programs.governanceProgram.idPDA()

    const sendLib = await programs.endpointProgram.getSendLibrary(connection, id, remote)

    const initialized = Boolean(sendLib?.programId);

    if (initialized) {
        console.log('initSendLibrary: already initialized')
        return Promise.resolve()
    }

    const ix = await programs.endpointProgram.initSendLibrary(admin.publicKey, id, remote)
    if (ix == null) {
        console.log('initSendLibrary: already initialized')
        return Promise.resolve()
    }
    console.log('initSendLibrary: initializing')
    await sendAndConfirm(connection, [admin], [ix], commitment)
}

export async function initReceiveLibrary(connection: Connection, programs: LAYERZERO_PROGRAMS, admin: Keypair, remote: EndpointId, commitment: Commitment = 'finalized'): Promise<void> {
    const [id] = programs.governanceProgram.idPDA()

    const recvLib = await programs.endpointProgram.getReceiveLibrary(connection, id, remote)

    const initialized = Boolean(recvLib?.programId);

    if (initialized) {
        console.log('initReceiveLibrary: already initialized')
        return Promise.resolve()
    }

    const ix = await programs.endpointProgram.initReceiveLibrary(admin.publicKey, id, remote)
    if (ix == null) {
        console.log('initReceiveLibrary: already initialized')
        return Promise.resolve()
    }
    console.log('initReceiveLibrary: initializing')
    await sendAndConfirm(connection, [admin], [ix], commitment)
}

export async function initOAppNonce(
    connection: Connection,
    programs: LAYERZERO_PROGRAMS,
    admin: Keypair,
    remote: EndpointId,
    remotePeer: Uint8Array,
    commitment: Commitment = 'finalized'
): Promise<void> {
    const [id] = programs.governanceProgram.idPDA()
    const ix = await programs.endpointProgram.initOAppNonce(admin.publicKey, remote, id, remotePeer)
    if (ix === null) {
        console.log('initOappNonce: ix === null, early exit');
        return Promise.resolve()
    }

    try {
        const nonce = await programs.endpointProgram.getNonce(connection, id, remote, remotePeer)
        if (nonce) {
            console.log('initOappNonce: already set')
            return Promise.resolve()
        }
    } catch (e) {
        console.log('initOappNonce: nonce not initialized');
    }
    await sendAndConfirm(connection, [admin], [ix], commitment)
}

export async function sendAndConfirm(
    connection: Connection,
    signers: Signer[],
    instructions: TransactionInstruction[],
    commitment: Commitment = 'finalized'
): Promise<string> {
    const { blockhash } = await connection.getLatestBlockhash({ commitment });
    const tx = await buildVersionedTransaction(
        connection, signers[0].publicKey, instructions, commitment, blockhash,
    )
    tx.sign(signers)
    const hash = await connection.sendTransaction(tx)
    await connection.confirmTransaction(hash, commitment)
    return hash
}

export async function logSerializedTransaction(
    connection: Connection,
    signers: Signer[],
    instructions: TransactionInstruction[],
    commitment: Commitment = 'finalized'
): Promise<void> {
    const { blockhash } = await connection.getLatestBlockhash({ commitment });
    const tx = await buildVersionedTransaction(connection, signers[0].publicKey, instructions, commitment, blockhash)
    tx.sign(signers)
    const serializedTx = Buffer.from(tx.serialize()).toString('base64');
    console.log('serialized transaction');
    console.log(serializedTx);
}

export async function simulateTransaction(
    connection: Connection,
    signers: Signer[],
    instructions: TransactionInstruction[],
    commitment: Commitment = 'finalized'
): Promise<SimulatedTransactionResponse> {
    const { blockhash } = await connection.getLatestBlockhash({ commitment });
    const tx = await buildVersionedTransaction(connection, signers[0].publicKey, instructions, commitment, blockhash)
    tx.sign(signers)
    const serializedTx = Buffer.from(tx.serialize()).toString('base64');

    const simulation = await connection.simulateTransaction(tx)
    return simulation.value
}

export function equalULNConfig(config1: UlnProgram.types.UlnConfig, config2: UlnProgram.types.UlnConfig) {
    let confirmationsEqual = false;
    if (typeof config1.confirmations === 'number') {
        confirmationsEqual = config1.confirmations === config2.confirmations;
    } else {
        confirmationsEqual = config1.confirmations.eq(new BN(config2.confirmations));
    }

    return confirmationsEqual && config1.requiredDvnCount === config2.requiredDvnCount && config1.optionalDvnCount === config2.optionalDvnCount && config1.optionalDvnThreshold === config2.optionalDvnThreshold && config1.requiredDvns.length === config2.requiredDvns.length && config1.optionalDvns.length === config2.optionalDvns.length;
}

export function computeCPIAuthority(programs: LAYERZERO_PROGRAMS, { originEid, originCallerEvmAddress }: { originEid: EndpointId, originCallerEvmAddress: string }): PublicKey {
    const deriver = new GovernancePDADeriver(programs.governanceProgram.program)
    const originCaller = arrayify(hexZeroPad(originCallerEvmAddress, 32));

    return deriver.cpiAuthority(originEid, Buffer.from(originCaller).toString('hex'))[0]
}