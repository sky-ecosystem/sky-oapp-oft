import {
    Cluster,
    ClusterFilter,
    Commitment,
    Program,
    ProgramError,
    ProgramRepositoryInterface,
    PublicKey,
    RpcInterface,
    Signer,
    WrappedInstruction,
    createNullRpc,
} from '@metaplex-foundation/umi'
import { createDefaultProgramRepository } from '@metaplex-foundation/umi-program-repository'
import { toWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { hexlify } from 'ethers/lib/utils'

import {
    EndpointProgram,
    EventPDA,
    MessageLibInterface,
    SimpleMessageLibProgram,
    UlnProgram,
    toWeb3Connection,
} from '@layerzerolabs/lz-solana-sdk-v2/umi'

import * as accounts from '../../generated/governance/accounts'
import * as errors from '../../generated/governance/errors'
import * as instructions from '../../generated/governance/instructions'
import * as types from '../../generated/governance/types'
import { MyOAppPDA as MyOAppPDA } from './pda'
export { accounts, errors, instructions, types }
export { PROGRAM_ID as GOVERNANCE_PROGRAM_ID } from '../../generated/governance'

const ENDPOINT_PROGRAM_ID: PublicKey = EndpointProgram.ENDPOINT_PROGRAM_ID

export enum MessageType {
    VANILLA = 1,
    COMPOSED_TYPE = 2,
}

export class MyOApp {
    public readonly pda: MyOAppPDA
    public readonly eventAuthority: PublicKey
    public readonly programRepo: ProgramRepositoryInterface
    public readonly endpointSDK: EndpointProgram.Endpoint

    constructor(
        public readonly programId: PublicKey,
        public endpointProgramId: PublicKey = EndpointProgram.ENDPOINT_PROGRAM_ID,
        rpc?: RpcInterface
    ) {
        this.pda = new MyOAppPDA(programId)
        if (rpc === undefined) {
            rpc = createNullRpc()
            rpc.getCluster = (): Cluster => 'custom'
        }
        this.programRepo = createDefaultProgramRepository({ rpc: rpc }, [
            {
                name: 'myOapp',
                publicKey: programId,
                getErrorFromCode(code: number, cause?: Error): ProgramError | null {
                    return errors.getMyOappErrorFromCode(code, this, cause)
                },
                getErrorFromName(name: string, cause?: Error): ProgramError | null {
                    return errors.getMyOappErrorFromName(name, this, cause)
                },
                isOnCluster(): boolean {
                    return true
                },
            } satisfies Program,
        ])
        this.eventAuthority = new EventPDA(programId).eventAuthority()[0]
        this.endpointSDK = new EndpointProgram.Endpoint(endpointProgramId)
    }

    getProgram(clusterFilter: ClusterFilter = 'custom'): Program {
        return this.programRepo.get('myOapp', clusterFilter)
    }

    async getStore(rpc: RpcInterface, commitment: Commitment = 'confirmed'): Promise<accounts.Store | null> {
        const [count] = this.pda.oapp()
        return accounts.safeFetchStore({ rpc }, count, { commitment })
    }

    initStore(payer: Signer, admin: PublicKey): WrappedInstruction {
        const [oapp] = this.pda.oapp()
        const remainingAccounts = this.endpointSDK.getRegisterOappIxAccountMetaForCPI(payer.publicKey, oapp)
        return instructions
            .initStore(
                { payer: payer, programs: this.programRepo },
                {
                    payer,
                    store: oapp,
                    lzReceiveTypesAccounts: this.pda.lzReceiveTypesAccounts()[0],

                    // args
                    admin: admin,
                    endpoint: this.endpointSDK.programId,
                }
            )
            .addRemainingAccounts(remainingAccounts).items[0]
    }

    async getSendLibraryProgram(
        rpc: RpcInterface,
        payer: PublicKey,
        dstEid: number
    ): Promise<SimpleMessageLibProgram.SimpleMessageLib | UlnProgram.Uln> {
        const [oapp] = this.pda.oapp()
        const sendLibInfo = await this.endpointSDK.getSendLibrary(rpc, oapp, dstEid)
        if (!sendLibInfo.programId) {
            throw new Error('Send library not initialized or blocked message library')
        }
        const { programId: msgLibProgram } = sendLibInfo
        const msgLibVersion = await this.endpointSDK.getMessageLibVersion(rpc, payer, msgLibProgram)
        if (msgLibVersion.major === 0n && msgLibVersion.minor == 0 && msgLibVersion.endpointVersion == 2) {
            return new SimpleMessageLibProgram.SimpleMessageLib(msgLibProgram)
        } else if (msgLibVersion.major === 3n && msgLibVersion.minor == 0 && msgLibVersion.endpointVersion == 2) {
            return new UlnProgram.Uln(msgLibProgram)
        }
        throw new Error(`Unsupported message library version: ${JSON.stringify(msgLibVersion, null, 2)}`)
    }
}

export async function getPeer(rpc: RpcInterface, dstEid: number, oftProgramId: PublicKey): Promise<string> {
    const [peer] = new MyOAppPDA(oftProgramId).peer(dstEid)
    const info = await accounts.Remote.fromAccountAddress(toWeb3Connection(rpc), toWeb3JsPublicKey(peer))
    return hexlify(info.address)
}

export function initConfig(
    programId: PublicKey,
    accounts: {
        admin: Signer
        payer: Signer
    },
    remoteEid: number,
    programs?: {
        msgLib?: PublicKey
        endpoint?: PublicKey
    }
): WrappedInstruction {
    const { admin, payer } = accounts
    const pda = new MyOAppPDA(programId)

    let msgLibProgram: PublicKey, endpointProgram: PublicKey
    if (programs === undefined) {
        msgLibProgram = UlnProgram.ULN_PROGRAM_ID
        endpointProgram = EndpointProgram.ENDPOINT_PROGRAM_ID
    } else {
        msgLibProgram = programs.msgLib ?? UlnProgram.ULN_PROGRAM_ID
        endpointProgram = programs.endpoint ?? EndpointProgram.ENDPOINT_PROGRAM_ID
    }

    const endpoint = new EndpointProgram.Endpoint(endpointProgram)
    let msgLib: MessageLibInterface
    if (msgLibProgram === SimpleMessageLibProgram.SIMPLE_MESSAGELIB_PROGRAM_ID) {
        msgLib = new SimpleMessageLibProgram.SimpleMessageLib(SimpleMessageLibProgram.SIMPLE_MESSAGELIB_PROGRAM_ID)
    } else {
        msgLib = new UlnProgram.Uln(msgLibProgram)
    }
    return endpoint.initOAppConfig(
        {
            delegate: admin,
            payer: payer.publicKey,
        },
        {
            msgLibSDK: msgLib,
            oapp: pda.oapp()[0],
            remote: remoteEid,
        }
    )
}

export function initSendLibrary(
    accounts: {
        admin: Signer
        oapp: PublicKey
    },
    remoteEid: number,
    endpointProgram: PublicKey = ENDPOINT_PROGRAM_ID
): WrappedInstruction {
    const { admin, oapp } = accounts
    const endpoint = new EndpointProgram.Endpoint(endpointProgram)
    return endpoint.initOAppSendLibrary(admin, { sender: oapp, remote: remoteEid })
}

export function initReceiveLibrary(
    accounts: {
        admin: Signer
        oapp: PublicKey
    },
    remoteEid: number,
    endpointProgram: PublicKey = ENDPOINT_PROGRAM_ID
): WrappedInstruction {
    const { admin, oapp } = accounts
    const endpoint = new EndpointProgram.Endpoint(endpointProgram)
    return endpoint.initOAppReceiveLibrary(admin, { receiver: oapp, remote: remoteEid })
}

export function initOAppNonce(
    accounts: {
        admin: Signer
        oapp: PublicKey
    },
    remoteEid: number,
    remoteOappAddr: Uint8Array, // must be 32 bytes
    endpointProgram: PublicKey = ENDPOINT_PROGRAM_ID
): WrappedInstruction {
    const { admin, oapp } = accounts
    const endpoint = new EndpointProgram.Endpoint(endpointProgram)

    return endpoint.initOAppNonce(admin, {
        localOApp: oapp,
        remote: remoteEid,
        remoteOApp: remoteOappAddr,
    })
}