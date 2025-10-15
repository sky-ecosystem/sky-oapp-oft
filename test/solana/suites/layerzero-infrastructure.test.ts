import {
    Context,
    KeypairSigner,
    none,
    PublicKey,
    publicKey,
    Signer,
    some,
    Umi,
} from '@metaplex-foundation/umi'
import { createLut, extendLut } from '@metaplex-foundation/mpl-toolbox'
import { secp256k1 } from '@layerzerolabs/lz-foundation'
import {
    DST_EID,
    DVN_SIGNERS,
    SRC_EID,
    defaultMultiplierBps,
    dvns,
    UMI
} from '../constants'
import { sendAndConfirm } from '../utils'
import { getGlobalContext, getGlobalUmi } from '../index.test'
import { ASSOCIATED_TOKEN_PROGRAM_ID, TOKEN_PROGRAM_ID } from '@solana/spl-token'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { ExecutorProgram, PriceFeedProgram, DVNProgram, UlnProgram, EventPDA, DvnPDA } from '@layerzerolabs/lz-solana-sdk-v2/umi'

const endpoint = UMI.endpoint
const executor = UMI.executor
const priceFeed = UMI.priceFeed
const simpleMessageLib = UMI.simpleMessageLib
const uln = UMI.uln

describe('LayerZero Infrastructure Setup', function () {
    let umi: Umi | Context
    let endpointAdmin: Signer
    let executorInExecutor: KeypairSigner

    before(function () {
        const context = getGlobalContext()
        umi = getGlobalUmi()
        endpointAdmin = umi.payer
        executorInExecutor = context.executor
    })

    it('Init Endpoint', async () => {
        await sendAndConfirm(
            umi,
            [
                endpoint.initEndpoint(endpointAdmin, {
                    eid: SRC_EID,
                    admin: endpointAdmin.publicKey,
                }),
                endpoint.registerLibrary(endpointAdmin, {
                    messageLibProgram: uln.programId,
                }),
                endpoint.registerLibrary(endpointAdmin, {
                    messageLibProgram: simpleMessageLib.programId,
                }),
                await endpoint.setDefaultSendLibrary(umi.rpc, endpointAdmin, {
                    messageLibProgram: uln.programId,
                    remote: DST_EID,
                }),
                await endpoint.setDefaultReceiveLibrary(umi.rpc, endpointAdmin, {
                    messageLibProgram: uln.programId,
                    remote: SRC_EID,
                }),
            ],
            endpointAdmin
        )
    })

    it('Init Executor', async () => {
        await sendAndConfirm(
            umi,
            [
                executor.initExecutor(endpointAdmin, {
                    admins: [endpointAdmin.publicKey],
                    executors: [executorInExecutor.publicKey],
                    msglibs: [uln.pda.messageLib()[0], simpleMessageLib.pda.messageLib()[0]],
                    owner: endpointAdmin.publicKey,
                    priceFeed: priceFeed.pda.priceFeed()[0],
                }),
                executor.setPriceFeed(endpointAdmin, priceFeed.programId),
                executor.setDefaultMultiplierBps(endpointAdmin, defaultMultiplierBps),
                executor.setDstConfig(endpointAdmin, [
                    {
                        eid: DST_EID,
                        lzReceiveBaseGas: 10000,
                        lzComposeBaseGas: 10000,
                        multiplierBps: some(13000),
                        floorMarginUsd: some(10000n),
                        nativeDropCap: BigInt(1e7),
                    } satisfies ExecutorProgram.types.DstConfig,
                ]),
            ],
            endpointAdmin
        )
    })

    it('Init PriceFeed', async () => {
        const nativeTokenPriceUsd = BigInt(1e10)
        const priceRatio = BigInt(1e10)
        const gasPriceInUnit = BigInt(1e9)
        const gasPerByte = 1
        const modelType: PriceFeedProgram.types.ModelType = {
            __kind: 'Arbitrum',
            gasPerL2Tx: BigInt(1e6),
            gasPerL1CalldataByte: 1,
        }
        await sendAndConfirm(
            umi,
            [
                priceFeed.initPriceFeed(endpointAdmin, {
                    admin: endpointAdmin.publicKey,
                    updaters: [endpointAdmin.publicKey],
                }),
                priceFeed.setSolPrice(endpointAdmin, nativeTokenPriceUsd),
                priceFeed.setPrice(endpointAdmin, {
                    dstEid: DST_EID,
                    priceRatio,
                    gasPriceInUnit,
                    gasPerByte,
                    modelType: modelType,
                }),
            ],
            endpointAdmin
        )
    })

    it('Init DVN', async () => {
        for (const programId of dvns) {
            const dvn = new DVNProgram.DVN(programId)
            await sendAndConfirm(
                umi,
                [
                    await dvn.initDVN(umi.rpc, endpointAdmin, {
                        admins: [endpointAdmin.publicKey],
                        signers: await Promise.all(
                            DVN_SIGNERS.map(async (s) => secp256k1.getPublicKey(s).then((r: any) => r.subarray(1)))
                        ),
                        msglibs: [uln.pda.messageLib()[0]],
                        quorum: 1,
                        vid: DST_EID % 30000,
                        priceFeed: priceFeed.pda.priceFeed()[0],
                    }),
                    dvn.setDefaultMultiplierBps(endpointAdmin, defaultMultiplierBps),
                    dvn.setPriceFeed(endpointAdmin, priceFeed.programId),
                    dvn.setDstConfig(endpointAdmin, [
                        {
                            eid: DST_EID,
                            dstGas: 10000,
                            multiplierBps: some(defaultMultiplierBps),
                            floorMarginUsd: none(),
                        },
                    ]),
                ],
                endpointAdmin
            )
        }
    })

    it('Init SimpleMessageLib', async () => {
        await sendAndConfirm(
            umi,
            [
                simpleMessageLib.initSimpleMessageLib(endpointAdmin, {
                    admin: endpointAdmin.publicKey,
                    eid: SRC_EID,
                    nativeFee: 1e4,
                    lzTokenFee: 0,
                }),
                simpleMessageLib.setWhitelistCaller(endpointAdmin, endpointAdmin.publicKey),
            ],
            endpointAdmin
        )
    })

    it('Init UltraLightNode', async () => {
        const defaultNativeFeeBps = 100
        const maxMessageSize = 1024
        const requiredDvns = dvns.map((programId) => new DvnPDA(publicKey(programId)).config()[0]).sort()
        const sendUlnConfig: UlnProgram.types.UlnConfig = {
            confirmations: 1n,
            requiredDvnCount: requiredDvns.length,
            optionalDvnCount: 0,
            optionalDvnThreshold: 0,
            requiredDvns: requiredDvns,
            optionalDvns: [],
        }
        const receiveUlnConfig: UlnProgram.types.UlnConfig = {
            confirmations: 1n,
            requiredDvnCount: requiredDvns.length,
            optionalDvnCount: 0,
            optionalDvnThreshold: 0,
            requiredDvns: requiredDvns,
            optionalDvns: [],
        }
        const executorConfig: UlnProgram.types.ExecutorConfig = {
            maxMessageSize,
            executor: executor.pda.config()[0],
        }
        await sendAndConfirm(
            umi,
            [
                uln.initUln(endpointAdmin, {
                    admin: endpointAdmin.publicKey,
                    eid: DST_EID,
                    endpointProgram: endpoint.programId,
                }),
                uln.setTreasury(endpointAdmin, {
                    admin: endpointAdmin.publicKey,
                    lzToken: null,
                    nativeFeeBps: defaultNativeFeeBps,
                    nativeReceiver: endpointAdmin.publicKey,
                }),
                await uln.initOrUpdateDefaultConfig(umi.rpc, endpointAdmin, {
                    executorConfig: some(executorConfig),
                    receiveUlnConfig: some(receiveUlnConfig),
                    remote: SRC_EID,
                    sendUlnConfig: some(sendUlnConfig),
                }),
                await uln.initOrUpdateDefaultConfig(umi.rpc, endpointAdmin, {
                    executorConfig: some(executorConfig),
                    receiveUlnConfig: some(receiveUlnConfig),
                    remote: DST_EID,
                    sendUlnConfig: some(sendUlnConfig),
                }),
            ],
            endpointAdmin
        )
    })

    it('Init address lookup table', async function () {
        const context = getGlobalContext()

        const recentSlot = await umi.rpc.getSlot({ commitment: 'finalized' })
        const [builder, input] = createLut(umi, {
            recentSlot,
            authority: umi.payer,
            payer: umi.payer,
            // TODO: add addresses
            addresses: [
                publicKey('11111111111111111111111111111111'),
            ],
        })
        await builder.sendAndConfirm(umi)

        // Extend the lookup table with more addresses
        const extendAddresses = [
            // ...pathwayAddresses(oapp, remoteEid, publicKeyBytes(oapp)),

            // executor
            executor.pda.context(umi.payer.publicKey, 1)[0],
            umi.payer.publicKey,

            // additional oapp pda
        ]

        await extendLut(umi, {
            authority: umi.payer,
            address: input.publicKey,
            addresses: extendAddresses,
        }).sendAndConfirm(umi)

        input.addresses = [...input.addresses, ...extendAddresses]
        context.lookupTable = input
    })
})

function globalAddress(dvns: PublicKey[], oapp: PublicKey): PublicKey[] {
    return [
        publicKey('11111111111111111111111111111111'),
        publicKey('Sysvar1nstructions1111111111111111111111111'),
        fromWeb3JsPublicKey(TOKEN_PROGRAM_ID),
        fromWeb3JsPublicKey(ASSOCIATED_TOKEN_PROGRAM_ID),

        // Programs
        endpoint.programId,
        uln.programId,
        executor.programId,
        priceFeed.programId,
        ...dvns,

        // Endpoint PDAs
        endpoint.pda.setting()[0],
        endpoint.pda.oappRegistry(oapp)[0],
        endpoint.eventAuthority,
        endpoint.pda.messageLibraryInfo(uln.pda.messageLib()[0])[0],

        // Uln PDAs
        uln.pda.messageLib()[0],
        uln.pda.setting()[0],
        uln.eventAuthority,

        // Worker Configs
        executor.pda.config()[0],
        executor.eventAuthority,
        priceFeed.pda.priceFeed()[0],

        ...dvns.map((dvn) => new DvnPDA(publicKey(dvn)).config()[0]),
        ...dvns.map((dvn) => new EventPDA(publicKey(dvn)).eventAuthority()[0]),

        // OApp
        oapp,
    ]
}

function pathwayAddresses(localOApp: PublicKey, remote: number, remoteOApp: Uint8Array): PublicKey[] {
    return [
        endpoint.pda.defaultSendLibraryConfig(remote)[0],
        endpoint.pda.oappRegistry(localOApp)[0],
        endpoint.pda.sendLibraryConfig(localOApp, remote)[0],
        endpoint.pda.nonce(localOApp, remote, remoteOApp)[0],
        endpoint.pda.pendingNonce(localOApp, remote, remoteOApp)[0],

        uln.pda.defaultSendConfig(remote)[0],
        uln.pda.defaultReceiveConfig(remote)[0],
        uln.pda.sendConfig(remote, localOApp)[0],
        uln.pda.receiveConfig(remote, localOApp)[0],
    ]
}