import { task } from 'hardhat/config'
import { makeBytes32 } from '@layerzerolabs/devtools'
import { types as hardhatTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { deriveConnection } from './index'
import { arrayify } from '@ethersproject/bytes'
import { buildLzReceiveExecutionPlan, LzReceiveParams } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { base58 } from '@metaplex-foundation/umi/serializers'
import { Instruction, publicKey } from '@metaplex-foundation/umi'
import { simulateTransaction } from './utils'
import { bs58 } from '@coral-xyz/anchor/dist/cjs/utils/bytes'
import { PublicKey } from '@solana/web3.js'
import { accounts } from './sdk/oft302'
import { Base64 } from 'js-base64';


interface Args {
    debug: boolean
    srcTxHash: string
}

const EXECUTOR_PROGRAM_ID = '6doghB248px58JSSwG4qejQ46kFMW4AMj7vzJnWZHNZn'

const ixDataFromBs58 = (s: string): Uint8Array => new Uint8Array(bs58.decode(s))
const ixDataFromHex = (s: string): Uint8Array =>
    Uint8Array.from(Buffer.from(s.startsWith('0x') ? s.slice(2) : s, 'hex'))

task('lz:oapp:solana:simulate-unpause', '')
    .setAction(async () => {
        if (!process.env.SOLANA_PRIVATE_KEY) {
            throw new Error('SOLANA_PRIVATE_KEY is not defined in the environment variables.')
        }

        const CPI_AUTHORITY = 'AYPtjx4Hc8us1ikULUedkmZ3wtiD6tmL7gK3qe4V3oHt';

        const { connection, umi, umiWalletKeyPair, umiWalletSigner } = await deriveConnection(30168)

        const ix: Instruction = {
            keys: [
                {
                    pubkey: publicKey(CPI_AUTHORITY),
                    isSigner: true,
                    isWritable: true,
                },
                {
                    pubkey: publicKey('BEvTHkTyXooyaJzP8egDUC7WQK8cyRrq5WvERZNWhuah'),
                    isSigner: false,
                    isWritable: true,
                },
            ],
            programId: publicKey('SKYTAiJRkgexqQqFoqhXdCANyfziwrVrzjhBaCzdbKW'),
            // ...00 - paused: false
            // ...01 - paused: true
            data: ixDataFromHex('3f209a0238674f2d00')
        };

        const transaction = umi.transactions.create({
            version: 0,
            blockhash: (await umi.rpc.getLatestBlockhash()).blockhash,
            instructions: [ix],
            payer: publicKey(CPI_AUTHORITY),
            addressLookupTables: [],
        })

        console.log('serializedMessage', base58.deserialize(transaction.serializedMessage)[0])

        const simulation = await simulateTransaction(umi, transaction, connection, { verifySignatures: false, accounts: [new PublicKey('BEvTHkTyXooyaJzP8egDUC7WQK8cyRrq5WvERZNWhuah')] })
        console.log('simulation', simulation)

        const rawData = simulation!.accounts[0]?.data[0]
        if (!rawData) {
            throw new Error('No raw data found')
        }
        const rawDataDecoded = Base64.toUint8Array(rawData)

        const newOFTStore = accounts.deserializeOFTStore({
            data: rawDataDecoded,
            executable: false,
            lamports: 0,
            owner: publicKey('SKYTAiJRkgexqQqFoqhXdCANyfziwrVrzjhBaCzdbKW'),
        })

        console.log('newOFTStore.paused', newOFTStore.paused)
    }
    )
