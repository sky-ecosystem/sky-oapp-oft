import { BN } from '@coral-xyz/anchor'
import { toWeb3JsKeypair } from '@metaplex-foundation/umi-web3js-adapters'
import { AccountMeta, AddressLookupTableAccount, Connection, Keypair, PublicKey, SystemProgram, TransactionInstruction, TransactionMessage, VersionedTransaction } from '@solana/web3.js'
import bs58 from 'bs58'
import { task } from 'hardhat/config'
import { makeBytes32 } from '@layerzerolabs/devtools'
import { types } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { lzReceive, buildVersionedTransaction, instructionDiscriminator } from '@layerzerolabs/lz-solana-sdk-v2'
import { deriveConnection } from './index'
import { arrayify } from '@ethersproject/bytes'
import { GovernanceProgram } from '../../src'
import * as beet from '@metaplex-foundation/beet'
import * as beetSolana from '@metaplex-foundation/beet-solana'

interface Args {
    srcEid: EndpointId
    nonce: bigint
    sender: string
    dstEid: EndpointId
    receiver: string
    guid: string
    payload: string
    computeUnits: number
    lamports: number
    withPriorityFee: number
}

task('lz:oft:solana:init-pending-messages-store', 'Initialize a pending messages store on Solana')
    .addParam('srcEid', 'The source EndpointId', undefined, types.eid)
    .addParam('computeUnits', 'The CU for the lzReceive instruction', undefined, types.int)
    .addParam('lamports', 'The lamports for the lzReceive instruction', undefined, types.int)
    .addParam('withPriorityFee', 'The priority fee in microLamports', undefined, types.int)
    .setAction(
        async ({
            srcEid,
            nonce,
            sender,
            dstEid,
            receiver,
            guid,
            payload,
            computeUnits,
            lamports,
            withPriorityFee,
        }: Args) => {
            if (!process.env.SOLANA_PRIVATE_KEY) {
                throw new Error('SOLANA_PRIVATE_KEY is not defined in the environment variables.')
            }

            const params = {
                oft_sender: new PublicKey("3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a")
            }

            const { connection, umiWalletKeyPair } = await deriveConnection(srcEid)
            const signer = toWeb3JsKeypair(umiWalletKeyPair)

            type InitPendingMessagesStoreParams = {
                oft_sender: PublicKey
            }

            /**
             * @category userTypes
             * @category generated
             */
            const initPendingMessagesStoreParamsBeet = new beet.BeetArgsStruct<InitPendingMessagesStoreParams>(
                [
                    ['oft_sender', beetSolana.publicKey],
                ],
                'InitPendingMessagesStoreParams'
            )


            type InitPendingMessagesStoreInstructionArgs = {
                params: InitPendingMessagesStoreParams
              }

              const initPendingMessagesStoreStruct = new beet.BeetArgsStruct<
              InitPendingMessagesStoreInstructionArgs & {
                  instructionDiscriminator: number[] /* size: 8 */
                }
              >(
                [
                  ['instructionDiscriminator', beet.uniformFixedSizeArray(beet.u8, 8)],
                  ['params', initPendingMessagesStoreParamsBeet],
                ],
                'InitPendingMessagesStoreInstructionArgs'
              )

            const [data] = initPendingMessagesStoreStruct.serialize({
                params: params,
                instructionDiscriminator: Array.from(instructionDiscriminator("init_pending_messages_store"))
            });

            const storeAddress = new PublicKey('6wvGC9hxTkaFRdaDrXTQVfcRMBkwezBYHduuoYeSDNKm');

            const accounts = [
                {
                    pubkey: signer.publicKey,
                    isWritable: true,
                    isSigner: true,
                },
                {
                    pubkey: new PublicKey('HUPW9dJZxxSafEVovebGxgbac3JamjMHXiThBxY5u43M'),
                    isWritable: false,
                    isSigner: false,
                },
                {
                    pubkey: new PublicKey('HwpzV5qt9QzYRuWkHqTRuhbqtaMhapSNuriS5oMynkny'),
                    isWritable: false,
                    isSigner: false,
                },
                {
                    pubkey: storeAddress,
                    isWritable: true,
                    isSigner: false,
                },
                {
                    pubkey: SystemProgram.programId,
                    isWritable: false,
                    isSigner: false,
                },
            ]

            const ix = new TransactionInstruction({
                programId: new PublicKey('E2R6qMMzLBjCwXs66MPEg2zKfpt5AMxWNgSULsLYfPS2'),
                keys: accounts,
                data
            });

            const message = new TransactionMessage({
                payerKey: signer.publicKey,
                recentBlockhash: (await connection.getLatestBlockhash()).blockhash,
                instructions: [ix],
            }).compileToV0Message();
            
            const tx = new VersionedTransaction(message);
            tx.sign([signer]);

            const txSignature = await connection.sendTransaction(tx);

            console.log("txSignature", txSignature)
            
        }
)
