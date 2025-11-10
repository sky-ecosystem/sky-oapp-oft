/* eslint-disable @typescript-eslint/require-await */
import {
    Cluster,
    Program,
    ProgramError,
    ProgramRepositoryInterface,
    PublicKey,
    RpcInterface,
    Signer,
    WrappedInstruction,
    createNullRpc,
    some,
} from '@metaplex-foundation/umi'
import { createDefaultProgramRepository } from '@metaplex-foundation/umi-program-repository'

import * as errors from './generated/oft302/errors'
import * as instructions from './generated/oft302/instructions'
import * as types from './generated/oft302/types'
import { OftPDA } from './pda'
import {
    SetPeerAddressParam,
    SetPeerEnforcedOptionsParam,
    SetPeerFeeBpsParam,
    SetPeerRateLimitParam,
} from './types'

export * as accounts from './generated/oft302/accounts'
export * as instructions from './generated/oft302/instructions'
export * as programs from './generated/oft302/programs'
export * as shared from './generated/oft302/shared'
export * as types from './generated/oft302/types'
export * as errors from './generated/oft302/errors'

export function createOFTProgramRepo(oftProgram: PublicKey, rpc?: RpcInterface): ProgramRepositoryInterface {
    if (rpc === undefined) {
        rpc = createNullRpc()
        rpc.getCluster = (): Cluster => 'custom'
    }
    return createDefaultProgramRepository({ rpc: rpc }, [
        {
            name: 'oft',
            publicKey: oftProgram,
            getErrorFromCode(code: number, cause?: Error): ProgramError | null {
                return errors.getOftErrorFromCode(code, this, cause)
            },
            getErrorFromName(name: string, cause?: Error): ProgramError | null {
                return errors.getOftErrorFromName(name, this, cause)
            },
            isOnCluster(): boolean {
                return true
            },
        } satisfies Program,
    ])
}

export function setPeerConfig(
    accounts: {
        admin: Signer
        oftStore: PublicKey
    },
    param: (SetPeerAddressParam | SetPeerFeeBpsParam | SetPeerEnforcedOptionsParam | SetPeerRateLimitParam) & {
        remote: number
    },
    oftProgramId: PublicKey | ProgramRepositoryInterface
): WrappedInstruction {
    const programsRepo = typeof oftProgramId === 'string' ? createOFTProgramRepo(oftProgramId) : oftProgramId
    const { remote: remoteId } = param
    if (remoteId % 30000 == 0) {
        throw new Error('Invalid remote ID')
    }
    const { admin, oftStore } = accounts
    const [peerPda] = new OftPDA(programsRepo.getPublicKey('oft')).peer(oftStore, remoteId)
    let config: types.PeerConfigParamArgs
    if (param.__kind === 'PeerAddress') {
        if (param.peer.length !== 32) {
            throw new Error('Peer must be 32 bytes (left-padded with zeroes)')
        }
        config = types.peerConfigParam('PeerAddress', [param.peer])
    } else if (param.__kind === 'FeeBps') {
        config = { __kind: 'FeeBps', fields: [some(param.feeBps)] }
    } else if (param.__kind === 'EnforcedOptions') {
        config = {
            __kind: 'EnforcedOptions',
            send: param.send,
            sendAndCall: param.sendAndCall,
        }
        // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
    } else if (param.__kind === 'OutboundRateLimit' || param.__kind === 'InboundRateLimit') {
        config = {
            __kind: param.__kind,
            fields: [
                param.rateLimit
                    ? some({
                          refillPerSecond: some(param.rateLimit.refillPerSecond),
                          capacity: some(param.rateLimit.capacity),
                          rateLimiterType: some(param.rateLimit.rateLimiterType),
                      })
                    : null,
            ],
        }
    } else {
        throw new Error('Invalid peer config')
    }

    return instructions.setPeerConfig(
        { programs: programsRepo },
        {
            admin: admin,
            peer: peerPda,
            oftStore: oftStore,
            // params
            remoteEid: remoteId,
            config: config,
        }
    ).items[0]
}

export function setOFTConfig(
    accounts: {
        admin: Signer
        oftStore: PublicKey
    },
    param: types.SetOFTConfigParams,
    oftProgramId: PublicKey | ProgramRepositoryInterface
): WrappedInstruction {
    const programsRepo = typeof oftProgramId === 'string' ? createOFTProgramRepo(oftProgramId) : oftProgramId
    const { admin, oftStore } = accounts
    return instructions.setOftConfig(
        { programs: programsRepo },
        { admin: admin, oftStore: oftStore, params: param }
    ).items[0]
}

export function setPause(
    accounts: {
        signer: Signer
        oftStore: PublicKey
    },
    paused: boolean,
    oftProgramId: PublicKey | ProgramRepositoryInterface
): WrappedInstruction {
    const programsRepo = typeof oftProgramId === 'string' ? createOFTProgramRepo(oftProgramId) : oftProgramId
    const { signer, oftStore } = accounts
    return instructions.setPause(
        { programs: programsRepo },
        { signer, oftStore: oftStore, paused }
    ).items[0]
}