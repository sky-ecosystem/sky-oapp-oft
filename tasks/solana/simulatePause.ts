import { task } from 'hardhat/config'
import { base58 } from '@metaplex-foundation/umi/serializers'
import { Instruction } from '@metaplex-foundation/umi'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { Base64 } from 'js-base64'

import { deriveConnection } from './index'
import { ixDataFromHex, simulateTransaction } from './utils'
import { OFT_PROGRAM_ID, OFT_STORE, PAUSER_WALLET } from './consts-mainnet'
import { accounts } from './sdk/oft302'

task('lz:oapp:solana:simulate-pause', 'Simulate pausing the Sky OFT via the pauser wallet')
    .setAction(async () => {
        if (!process.env.SOLANA_PRIVATE_KEY) {
            throw new Error('SOLANA_PRIVATE_KEY is not defined in the environment variables.')
        }

        const { connection, umi } = await deriveConnection(30168)

        const ix: Instruction = {
            keys: [
                { pubkey: fromWeb3JsPublicKey(PAUSER_WALLET), isSigner: true, isWritable: true },
                { pubkey: fromWeb3JsPublicKey(OFT_STORE), isSigner: false, isWritable: true },
            ],
            programId: fromWeb3JsPublicKey(OFT_PROGRAM_ID),
            // ...00 - paused: false
            // ...01 - paused: true
            data: ixDataFromHex('3f209a0238674f2d01'),
        }

        const transaction = umi.transactions.create({
            version: 0,
            blockhash: (await umi.rpc.getLatestBlockhash()).blockhash,
            instructions: [ix],
            payer: fromWeb3JsPublicKey(PAUSER_WALLET),
            addressLookupTables: [],
        })

        console.log('serializedMessage', base58.deserialize(transaction.serializedMessage)[0])

        const simulation = await simulateTransaction(umi, transaction, connection, {
            verifySignatures: false,
            accounts: [OFT_STORE],
        })
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
            owner: fromWeb3JsPublicKey(OFT_PROGRAM_ID),
        })

        console.log('newOFTStore.paused', newOFTStore.paused)
    })
