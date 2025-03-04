import { PublicKey } from '@solana/web3.js'
import BN from 'bn.js'

import { oappIDPDA } from '@layerzerolabs/lz-solana-sdk-v2'

export const OFT_SEED = 'OFT'
export const PEER_SEED = 'Peer'
export const ENFORCED_OPTIONS_SEED = 'EnforcedOptions'
export const LZ_RECEIVE_TYPES_SEED = 'LzReceiveTypes'
export const TWO_LEG_SEND_PENDING_MESSAGE_STORE_SEED = 'TwoLegSendPendingMessageStore'

export class OFTPDADeriver {
    constructor(
        public readonly program: PublicKey
    ) {}

    oft(): PublicKey {
        if (!process.env.OFT_PROGRAM_ID) {
            throw new Error('OFT_PROGRAM_ID is not set');
        }

        return new PublicKey(process.env.OFT_PROGRAM_ID);

        // return 
    }

    peer(dstEid: number): PublicKey {
        return PublicKey.findProgramAddressSync(
            [Buffer.from(PEER_SEED), this.oft().toBytes(), new BN(dstEid).toArrayLike(Buffer, 'be', 4)],
            this.program
        )[0]
    }
}