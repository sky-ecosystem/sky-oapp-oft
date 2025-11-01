import { Pda, PublicKey, publicKeyBytes } from '@metaplex-foundation/umi'
import { Endian, u32 } from '@metaplex-foundation/umi/serializers'
import { createWeb3JsEddsa } from '@metaplex-foundation/umi-eddsa-web3js'

import { OmniAppPDA } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { GOVERNANCE_SEED, REMOTE_SEED } from '../../governance-pda-deriver'
import BN from 'bn.js'

const eddsa = createWeb3JsEddsa()

export class MyOAppPDA extends OmniAppPDA {
    constructor(public readonly programId: PublicKey) {
        super(programId)
    }

    // seeds = [GOVERNANCE_SEED, GOVERNANCE_ID],
    oapp(): Pda {
        return eddsa.findPda(this.programId, [Buffer.from(GOVERNANCE_SEED, 'utf8'), new BN(this.governanceId).toArrayLike(Buffer, 'be', 8)])
    }

    // seeds = [REMOTE_SEED, GOVERNANCE_ID, DST_EID],
    peer(dstChainId: number): Pda {
        return eddsa.findPda(this.programId, [
            Buffer.from(REMOTE_SEED, 'utf8'),
            publicKeyBytes(this.oapp()[0]),
            u32({ endian: Endian.Big }).serialize(dstChainId)
        ])
    }

    // seeds = [NONCE_SEED, &params.receiver, &params.src_eid.to_be_bytes(), &params.sender]
    nonce(receiver: PublicKey, remoteEid: number, sender: Uint8Array): Pda {
        return eddsa.findPda(this.programId, [
            Buffer.from(MyOAppPDA.NONCE_SEED, 'utf8'),
            publicKeyBytes(receiver),
            u32({ endian: Endian.Big }).serialize(remoteEid),
            sender,
        ])
    }
}