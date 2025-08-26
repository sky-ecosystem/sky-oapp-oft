import { PublicKey } from '@solana/web3.js'
import BN from 'bn.js'

export const GOVERNANCE_SEED = 'Governance'
export const REMOTE_SEED = 'Remote'
export const LZ_RECEIVE_TYPES_SEED = 'LzReceiveTypes'

export class GovernancePDADeriver {
    constructor(
        public readonly program: PublicKey,
        public governanceId = 0
    ) {}

    governance(): [PublicKey, number] {
        return PublicKey.findProgramAddressSync(
            [Buffer.from(GOVERNANCE_SEED), new BN(this.governanceId).toArrayLike(Buffer, 'be', 8)],
            this.program
        )
    }

    remote(dstChainId: number): [PublicKey, number] {
        return PublicKey.findProgramAddressSync(
            [Buffer.from(REMOTE_SEED), this.governance()[0].toBytes(), new BN(dstChainId).toArrayLike(Buffer, 'be', 4)],
            this.program
        )
    }

    lzReceiveTypesInfoAccounts(): [PublicKey, number] {
        return PublicKey.findProgramAddressSync(
            [Buffer.from(LZ_RECEIVE_TYPES_SEED, 'utf8'), this.governance()[0].toBytes()],
            this.program
        )
    }
}