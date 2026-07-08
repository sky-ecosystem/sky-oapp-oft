/**
 * Sky deployment constants for mainnet (Ethereum L1 + Solana mainnet).
 *
 * Includes the L1 Gov Relay address that originates governance messages, and
 * derived PDAs (CPI authority on Solana, peer config for the Ethereum peer)
 * that any task interacting with the mainnet Sky OFT can reuse.
 */
import { PublicKey } from '@solana/web3.js'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { PublicKey as UmiPublicKey } from '@metaplex-foundation/umi'

import { OftPDA } from './sdk/pda'
import { GovernancePDADeriver } from '../../src/governance-pda-deriver'

export const ETHEREUM_V2_MAINNET_EID = 30101

// L1 Gov Relay address on Ethereum mainnet, left-padded to bytes32 (origin caller of governance messages).
export const L1_GOV_RELAY_ORIGIN_CALLER_HEX =
    '0000000000000000000000002bebfe397d497b66cb14461cb6ee467b4c3b7d61'

export const GOVERNANCE_PROGRAM_ID = new PublicKey('SKYGRikJcGSa3jC5HDyzDrVsmkCk3e5SqAurycny8PW')
export const OFT_PROGRAM_ID = new PublicKey('SKYTAiJRkgexqQqFoqhXdCANyfziwrVrzjhBaCzdbKW')
export const OFT_STORE = new PublicKey('BEvTHkTyXooyaJzP8egDUC7WQK8cyRrq5WvERZNWhuah')

// Pauser wallet — direct (non-governance) signer for the pause instruction.
export const PAUSER_WALLET = new PublicKey('5hARLsT1VA2AmuGL2AXUeSyyFG6o2Fcpb9S6aKXNsbeK')

// CPI authority that the L1 Gov Relay's governance message will sign as on Solana.
export const L1_GOV_RELAY_CPI_AUTHORITY: PublicKey = new GovernancePDADeriver(GOVERNANCE_PROGRAM_ID)
    .cpiAuthority(ETHEREUM_V2_MAINNET_EID, L1_GOV_RELAY_ORIGIN_CALLER_HEX)[0]

// Peer config PDA for the Ethereum mainnet peer of the Sky OFT.
export const ETHEREUM_PEER_PDA: UmiPublicKey = new OftPDA(fromWeb3JsPublicKey(OFT_PROGRAM_ID))
    .peer(fromWeb3JsPublicKey(OFT_STORE), ETHEREUM_V2_MAINNET_EID)[0]
