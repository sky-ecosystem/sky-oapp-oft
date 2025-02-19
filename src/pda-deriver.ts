import { PublicKey } from '@solana/web3.js'
import BN from 'bn.js'

import { oappIDPDA } from '@layerzerolabs/lz-solana-sdk-v2'

export const GOVERNANCE_SEED = 'Governance'
export const REMOTE_SEED = 'Remote'
export const LZ_RECEIVE_TYPES_SEED = 'LzReceiveTypes'
export const LZ_COMPOSE_TYPES_SEED = 'LzComposeTypes'

export class GovernancePDADeriver {
    constructor(
        public readonly program: PublicKey,
        public governanceId = 0
    ) {}

    governance(): [PublicKey, number] {
        return oappIDPDA(this.program, GOVERNANCE_SEED, this.governanceId)
    }

    remote(dstChainId: number): [PublicKey, number] {
        return PublicKey.findProgramAddressSync(
            [Buffer.from(REMOTE_SEED), this.governance()[0].toBytes(), new BN(dstChainId).toArrayLike(Buffer, 'be', 4)],
            this.program
        )
    }

    lzReceiveTypesAccounts(): [PublicKey, number] {
        return PublicKey.findProgramAddressSync(
            [Buffer.from(LZ_RECEIVE_TYPES_SEED, 'utf8'), this.governance()[0].toBytes()],
            this.program
        )
    }

    lzComposeTypesAccounts(): [PublicKey, number] {
        return PublicKey.findProgramAddressSync(
            [Buffer.from(LZ_COMPOSE_TYPES_SEED, 'utf8'), this.governance()[0].toBytes()],
            this.program
        )
    }
}