// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'
import { Connection, Keypair, PublicKey } from '@solana/web3.js'
import bs58 from 'bs58';
import {
    EndpointProgram,
    UlnProgram,
} from '@layerzerolabs/lz-solana-sdk-v2'
import { arrayify, hexZeroPad } from '@ethersproject/bytes'
import { EndpointId } from '@layerzerolabs/lz-definitions';
import BN from 'bn.js';

import { GovernanceProgram } from '../src'
import { initGovernance, LAYERZERO_PROGRAMS, setPeers, initReceiveLibrary, initOAppNonce, setReceiveLibrary, initReceiveConfig, setReceiveConfig, computeCPIAuthority } from './wire-utils';

if (!process.env.SOLANA_PRIVATE_KEY) {
    throw new Error("SOLANA_PRIVATE_KEY env required");
}

const governanceProgramId = process.env.GOVERNANCE_PROGRAM_ID
if (!governanceProgramId) {
    throw new Error("GOVERNANCE_PROGRAM_ID env required");
}

// if (!process.env.GOVERNANCE_CONTROLLER_ADDRESS) {
//     throw new Error("GOVERNANCE_CONTROLLER_ADDRESS env required to specify your peer address");
// }

if (!process.env.RPC_URL_SOLANA) {
    throw new Error("RPC_URL_SOLANA env required");
}

// Program IDs for the Mainnet and Devnet are the same for Endpoint and ULN programs
const endpointProgram = new EndpointProgram.Endpoint(new PublicKey('76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6'))
const ulnProgram = new UlnProgram.Uln(new PublicKey('7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH'))

const programs: LAYERZERO_PROGRAMS = {
    endpointProgram,
    governanceProgram: new GovernanceProgram.Governance(new PublicKey(governanceProgramId), endpointProgram),
    ulnProgram,
}

// const REQUIRED_DVNS = ([] as PublicKey[]).sort((a, b) => a.toBase58().localeCompare(b.toBase58()));

// const OPTIONAL_DVNS = [
//     new PublicKey('4VDjp6XQaxoZf5RGwiPU9NR1EXSZn2TP4ATMmiSzLfhb'), // LayerZero Labs
//     new PublicKey('29EKzmCscUg8mf4f5uskwMqvu2SXM8hKF1gWi1cCBoKT'), // P2P
// ].sort((a, b) => a.toBase58().localeCompare(b.toBase58()));
// const OPTIONAL_DVN_THRESHOLD = 1;

// type RemotePeer = {
//     // Peer address
//     address: string;
//     // ReceiveConfig when receiving from this peer
//     receiveConfig: UlnProgram.types.UlnConfig;
// }

// const remotePeers: { [key in EndpointId]?: RemotePeer } = {
//     [EndpointId.ETHEREUM_V2_MAINNET]: {
//         address: process.env.GOVERNANCE_CONTROLLER_ADDRESS,
//         receiveConfig: {
//             confirmations: new BN(15),
//             requiredDvnCount: REQUIRED_DVNS.length === 0 ? 255 : REQUIRED_DVNS.length, // NULL indicator for required DVNs
//             optionalDvnCount: OPTIONAL_DVNS.length,
//             optionalDvnThreshold: OPTIONAL_DVN_THRESHOLD,
//             requiredDvns: REQUIRED_DVNS,
//             optionalDvns: OPTIONAL_DVNS,
//         }
//     },
// }

const connection = new Connection(process.env.RPC_URL_SOLANA);
const signer = Keypair.fromSecretKey(bs58.decode(process.env.SOLANA_PRIVATE_KEY));

(async () => {
    const validationOnly = false;
    await initGovernance(connection, programs, signer, signer, [], { commitment: 'finalized', validationOnly });

    // NOTE: for redundancy and validation purposes uncomment the following code
    // for (const [remoteStr, remotePeer] of Object.entries(remotePeers)) {
    //     const remotePeerBytes = arrayify(hexZeroPad(remotePeer.address, 32))
    //     const remote = parseInt(remoteStr) as EndpointId

    //     await setPeers(connection, programs, signer, remote, remotePeerBytes, { commitment: 'finalized', validationOnly })
    //     await initReceiveLibrary(connection, programs, signer, remote, 'finalized')
    //     await initOAppNonce(connection, programs, signer, remote, remotePeerBytes, 'finalized')
    //     await setReceiveLibrary(connection, programs, signer, remote, 'finalized')
    //     await initReceiveConfig(connection, programs, signer, signer, remote, 'finalized')
    //     await setReceiveConfig(connection, programs, signer, remote, remotePeer.receiveConfig, 'finalized')
    // }
})()
