import {
    AddressLookupTableInput,
    Context,
    PublicKey,
    RpcConfirmTransactionResult,
    Signer,
    TransactionBuilder,
    WrappedInstruction,
    createNoopSigner,
} from '@metaplex-foundation/umi'
import { base58 } from '@metaplex-foundation/umi/serializers'
import {
    fromWeb3JsInstruction,
} from '@metaplex-foundation/umi-web3js-adapters'
import { Options, PacketSerializer, PacketV1Codec } from '@layerzerolabs/lz-v2-utilities'
import { sign, utils } from '@noble/secp256k1'
import * as web3 from '@solana/web3.js'
import { hexlify } from '@ethersproject/bytes'
import { DST_EID, DVN_SIGNERS, dvns, SRC_EID, UMI } from './constants'
import { PacketSentEvent, TestContext } from './types'
import { DVNProgram } from '@layerzerolabs/lz-solana-sdk-v2/umi'

const endpoint = UMI.endpoint
const executor = UMI.executor
const uln = UMI.uln

async function signWithECDSA(
    data: Buffer,
    privateKey: Uint8Array
): Promise<{ signature: Uint8Array; recoveryId: number }> {
    const [signature, recoveryId] = await sign(Uint8Array.from(data), utils.bytesToHex(privateKey), {
        canonical: true,
        recovered: true,
        der: false,
    })
    return {
        signature,
        recoveryId,
    }
}

export async function verifyByDvn(context: TestContext, packetSentEvent: PacketSentEvent): Promise<void> {
    const packetBytes = packetSentEvent.encodedPacket

    const expiration = BigInt(Math.floor(new Date().getTime() / 1000 + 120))
    const { umi } = context
    for (const programId of dvns) {
        const dvn = new DVNProgram.DVN(programId)
        const [requiredDVN] = dvn.pda.config()
        await new TransactionBuilder(
            [
                uln.initVerify(umi.payer, {
                    dvn: requiredDVN,
                    packetBytes,
                }),
                // dvn inoke uln.verify
                await dvn.invoke(
                    umi.rpc,
                    umi.payer,
                    {
                        vid: DST_EID % 30000,
                        instruction: uln.verify(createNoopSigner(requiredDVN), { packetBytes, confirmations: 10 })
                            .instruction,
                        expiration,
                    },
                    {
                        sign: async (message: Buffer): Promise<{ signature: Uint8Array; recoveryId: number }[]> => {
                            return Promise.all(DVN_SIGNERS.map(async (s) => signWithECDSA(message, s)))
                        },
                    }
                ),
            ],
            { addressLookupTables: context.lookupTable === undefined ? undefined : [context.lookupTable] }
        ).sendAndConfirm(umi, {
            send: { preflightCommitment: 'confirmed', commitment: 'confirmed' },
        })
    }
}

export async function commitVerification(
    context: TestContext,
    sender: Uint8Array,
    receiver: PublicKey,
    packetSentEvent: PacketSentEvent
): Promise<void> {
    const packetBytes = packetSentEvent.encodedPacket
    const deserializedPacket = PacketV1Codec.fromBytes(packetSentEvent.encodedPacket)
    const { umi } = context
    const expiration = BigInt(Math.floor(new Date().getTime() / 1000 + 120))

    await new TransactionBuilder([
        // endpoint init verify
        endpoint.initVerify(umi.payer, {
            srcEid: SRC_EID,
            sender,
            receiver,
            nonce: BigInt(deserializedPacket.nonce()),
        }),
        // commit verification
        await uln.commitVerification(umi.rpc, packetBytes, endpoint.programId),
    ]).sendAndConfirm(umi, { send: { preflightCommitment: 'confirmed', commitment: 'confirmed' } })

    for (const programId of dvns) {
        const dvn = new DVNProgram.DVN(programId)
        const [requiredDVN] = dvn.pda.config()
        await new TransactionBuilder([
            // close verify
            await dvn.invoke(
                umi.rpc,
                umi.payer,
                {
                    vid: DST_EID % 30000,
                    instruction: uln.closeVerify(createNoopSigner(requiredDVN), {
                        receiver,
                        packetBytes,
                    }).instruction,
                    expiration,
                },
                {
                    sign: async (message: Buffer): Promise<{ signature: Uint8Array; recoveryId: number }[]> => {
                        return Promise.all(DVN_SIGNERS.map(async (s) => signWithECDSA(message, s)))
                    },
                }
            ),
        ]).sendAndConfirm(umi, { send: { preflightCommitment: 'confirmed', commitment: 'confirmed' } })
    }
}

export async function verifyAndReceive(
    context: TestContext,
    sender: Uint8Array,
    receiver: PublicKey,
    packetSentEvent: PacketSentEvent
): Promise<string> {
    const { umi } = context
    await verifyByDvn(context, packetSentEvent)
    await commitVerification(context, sender, receiver, packetSentEvent)
    return receive(context, umi, packetSentEvent)
}

export async function receive(context: TestContext, umi: Context, packetSentEvent: PacketSentEvent): Promise<string> {
    const deserializedPacket = PacketSerializer.deserialize(packetSentEvent.encodedPacket)
    const { options } = packetSentEvent
    const lzReceiveOptions = Options.fromOptions(hexlify(options)).decodeExecutorLzReceiveOption()
    const { instructions, signers, addressLookupTables } = await executor.execute(umi.rpc, umi.payer, {
        packet: deserializedPacket,
        extraData: new Uint8Array(2).fill(0),
        value: lzReceiveOptions?.value,
    })
    const newAddressLookupTables = [
        ...(context.lookupTable ? [context.lookupTable] : []),
        ...(addressLookupTables || []),
    ]
    const { signature } = await sendAndConfirm(
        umi,
        instructions.map((ix: any, index: number) => ({
            instruction: ix,
            signers: index === 0 ? signers : [],
            bytesCreatedOnChain: 0,
        })),
        [umi.payer, ...signers],
        200_000,
        newAddressLookupTables
    )
    return signature
}

/**
 * Sends and confirms a transaction containing one or more wrapped instructions.
 *
 * @param umi - The Umi instance to use for sending the transaction.
 * @param instructions - A single wrapped instruction or an array of wrapped instructions to be included in the transaction.
 * @param signers - A single signer or an array of signers. The first signer is the fee payer. If multiple signers are provided, the first signer is the fee payer and the rest are used as signers for the instructions.
 * @param computeUnitsLimit - Optional. The maximum number of compute units the transaction is allowed to consume. Default is 0 (no limit).
 * @returns A promise that resolves to an object containing the transaction signature and the result of the transaction confirmation.
 */
export async function sendAndConfirm(
    umi: Pick<Context, 'transactions' | 'rpc' | 'payer'>,
    instructions: WrappedInstruction | WrappedInstruction[] | web3.TransactionInstruction[],
    signers: Signer | Signer[],
    computeUnitsLimit = 0,
    addressLookupTables?: AddressLookupTableInput[]
): Promise<{
    signature: string
    result: RpcConfirmTransactionResult
}> {
    if (!Array.isArray(instructions)) {
        instructions = [instructions]
    }
    if (instructions[0] instanceof web3.TransactionInstruction) {
        instructions = (instructions as web3.TransactionInstruction[]).map((ix) => {
            return {
                instruction: fromWeb3JsInstruction(ix),
                signers: [],
                bytesCreatedOnChain: 0,
            }
        })
    } else {
        instructions = instructions as WrappedInstruction[]
    }
    const feePayer = Array.isArray(signers) ? signers[0] : signers
    if (Array.isArray(signers) && signers.length > 1) {
        // override the signers for each instruction
        const ixSigners = signers.slice(1)
        instructions.forEach((ix) => {
            ix.signers = ixSigners
        })
    }
    if (computeUnitsLimit > 0) {
        const computeUnitsBudgetIX = web3.ComputeBudgetProgram.setComputeUnitLimit({
            units: computeUnitsLimit,
        })
        instructions = [
            {
                instruction: fromWeb3JsInstruction(computeUnitsBudgetIX),
                signers: [],
                bytesCreatedOnChain: 0,
            },
            ...instructions,
        ]
    }
    return new TransactionBuilder(instructions, { feePayer: feePayer, addressLookupTables })
        .sendAndConfirm(umi, {
            send: { preflightCommitment: 'confirmed', commitment: 'confirmed' },
        })
        .then((result) => {
            return { signature: base58.deserialize(result.signature)[0], result: result.result }
        })
}