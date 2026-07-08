/**
 * Helpers shared between the inbound and outbound rate-limit simulation tasks.
 * Just the set_peer_config-flavored ix builder and a peer-config decoder for
 * the simulation result. Universal deployment constants live in consts-mainnet.ts.
 */
import { SystemProgram } from '@solana/web3.js'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { Instruction } from '@metaplex-foundation/umi'
import { Base64 } from 'js-base64'

import { deserializePeerConfig, PeerConfig } from './sdk/generated/oft302/accounts/peerConfig'
import { simulateTransaction } from './utils'
import {
    ETHEREUM_PEER_PDA,
    L1_GOV_RELAY_CPI_AUTHORITY,
    OFT_PROGRAM_ID,
    OFT_STORE,
} from './consts-mainnet'

/**
 * Build the OFT set_peer_config instruction with the four-account layout used by
 * inbound/outbound rate-limit changes: [admin (signer), peer PDA, OFT store, system].
 */
export const buildRateLimitIx = (data: Uint8Array): Instruction => ({
    keys: [
        { pubkey: fromWeb3JsPublicKey(L1_GOV_RELAY_CPI_AUTHORITY), isSigner: true, isWritable: true },
        { pubkey: ETHEREUM_PEER_PDA, isSigner: false, isWritable: true },
        { pubkey: fromWeb3JsPublicKey(OFT_STORE), isSigner: false, isWritable: false },
        { pubkey: fromWeb3JsPublicKey(SystemProgram.programId), isSigner: false, isWritable: false },
    ],
    programId: fromWeb3JsPublicKey(OFT_PROGRAM_ID),
    data,
})

type SimulationResult = Awaited<ReturnType<typeof simulateTransaction>>

export const decodePeerConfigFromSimulation = (simulation: SimulationResult): PeerConfig => {
    const rawData = simulation?.accounts?.[0]?.data?.[0]
    if (!rawData) {
        throw new Error('No peer config data in simulation result')
    }
    return deserializePeerConfig({
        publicKey: ETHEREUM_PEER_PDA,
        data: Base64.toUint8Array(rawData),
        executable: false,
        lamports: { basisPoints: 0n, identifier: 'SOL', decimals: 9 },
        owner: fromWeb3JsPublicKey(OFT_PROGRAM_ID),
    })
}
