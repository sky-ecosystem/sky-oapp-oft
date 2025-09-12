import { PublicKey } from '@metaplex-foundation/umi'

import { RateLimiterType } from './generated/oft302'

export interface SetPeerAddressParam {
    peer: Uint8Array
    __kind: 'PeerAddress'
}

export interface SetPeerFeeBpsParam {
    feeBps: number
    __kind: 'FeeBps'
}

export interface SetPeerEnforcedOptionsParam {
    send: Uint8Array
    sendAndCall: Uint8Array
    __kind: 'EnforcedOptions'
}

export interface SetPeerRateLimitParam {
    rateLimit?: {
        refillPerSecond: bigint
        capacity: bigint
        rateLimiterType: RateLimiterType
    }
    __kind: 'OutboundRateLimit' | 'InboundRateLimit'
}

export interface SetPeerIsEndpointV1Param {
    isEndpointV1: boolean
    __kind: 'IsEndpointV1'
}

export interface SetOFTConfigParams {
    __kind: 'Admin' | 'Delegate' | 'DefaultFee' | 'Paused' | 'Pauser' | 'Unpauser'
    admin?: PublicKey
    delegate?: PublicKey
    defaultFee?: number
    paused?: boolean
    pauser?: PublicKey
    unpauser?: PublicKey
}