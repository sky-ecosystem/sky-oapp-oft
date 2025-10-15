import { EndpointProgram } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import {
    AddressLookupTableInput,
    Context,
    KeypairSigner,
    Program,
    ProgramRepositoryInterface,
} from '@metaplex-foundation/umi'
import { Connection } from '@solana/web3.js'

export type PacketSentEvent = EndpointProgram.events.PacketSentEvent

export interface TestContext {
    umi: Context
    connection: Connection
    executor: KeypairSigner
    program: Program
    programRepo: ProgramRepositoryInterface
    lookupTable?: AddressLookupTableInput
}
