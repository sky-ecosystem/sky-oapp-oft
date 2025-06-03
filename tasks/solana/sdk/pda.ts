import { PublicKey, publicKeyBytes } from '@metaplex-foundation/umi'
import { Endian, u32 } from '@metaplex-foundation/umi/serializers'
import { createWeb3JsEddsa } from '@metaplex-foundation/umi-eddsa-web3js'

import { LZ_RECEIVE_TYPES_SEED } from '@layerzerolabs/lz-solana-sdk-v2'

import { OFT_SEED, PEER_SEED } from './consts'

const eddsa = createWeb3JsEddsa()

export class OftPDA {
    constructor(public readonly program: PublicKey) {}

    config(): [PublicKey, number] {
        return eddsa.findPda(this.program, [Buffer.from('OftConfig', 'utf8')])
    }

    peer(oftStore: PublicKey, eid: number): [PublicKey, number] {
        return eddsa.findPda(this.program, [
            Buffer.from(PEER_SEED, 'utf8'),
            publicKeyBytes(oftStore),
            u32({ endian: Endian.Big }).serialize(eid),
        ])
    }

    oftStore(escrow: PublicKey): [PublicKey, number] {
        return eddsa.findPda(this.program, [Buffer.from(OFT_SEED, 'utf8'), publicKeyBytes(escrow)])
    }

    lzReceiveTypesAccounts(oftConfig: PublicKey): [PublicKey, number] {
        return eddsa.findPda(this.program, [Buffer.from(LZ_RECEIVE_TYPES_SEED, 'utf8'), publicKeyBytes(oftConfig)])
    }
}
