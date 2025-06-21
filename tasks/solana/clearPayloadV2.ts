import { task } from 'hardhat/config'
import { makeBytes32 } from '@layerzerolabs/devtools'
import { types as hardhatTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { deriveConnection } from './index'
import { arrayify } from '@ethersproject/bytes'
import { buildLzReceiveExecutionPlan, LzReceiveParams } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { base58 } from '@metaplex-foundation/umi/serializers'
import { publicKey } from '@metaplex-foundation/umi'
import { simulateTransaction } from './utils'

interface Args {
    srcTxHash: string
}

task('lz:oapp:solana:clear-v2', 'Clear a stored payload on Solana using the v2 lzReceive instruction')
    .addParam('srcTxHash', 'The source transaction hash', undefined, hardhatTypes.string)
    .setAction(async ({ srcTxHash, }: Args) => {
        if (!process.env.SOLANA_PRIVATE_KEY) {
            throw new Error('SOLANA_PRIVATE_KEY is not defined in the environment variables.')
        }

        const response = await fetch(`https://scan-testnet.layerzero-api.com/v1/messages/tx/${srcTxHash}`)
        const data = await response.json()
        const message = data.data?.[0];

        if (!message) {
            throw new Error('No message found yet.')
        }

        if (message.destination.status === 'SUCCEEDED') {
            console.log('--------------------------------')
            console.log('\nTransaction already delivered: \n')
            console.log(`https://explorer.solana.com/tx/${message.destination.tx.txHash}?cluster=devnet`)
            return;
        }

        if (message.verification.sealer.status === 'WAITING') {
            console.log('--------------------------------')
            console.log('\nStill waiting for sealer. Please retry later. \n')
            return;
        }

        const { connection, umi, umiWalletKeyPair, umiWalletSigner } = await deriveConnection(message.pathway.dstEid)
        
        const packet = {
            nonce: message.pathway.nonce,
            srcEid: message.pathway.srcEid,
            sender: makeBytes32(message.pathway.sender.address),
            dstEid: message.pathway.dstEid,
            receiver: message.pathway.receiver.address,
            payload: '', // unused;  just added to satisfy typing
            guid: message.guid,
            message: message.source.tx.payload, // referred to as "payload" in scan-api
            version: 1, // unused;  just added to satisfy typing
        }
        console.log({
            packet
        })

        if (!process.env.GOVERNANCE_PROGRAM_ID) {
            throw new Error('GOVERNANCE_PROGRAM_ID is not defined in the environment variables.')
        }

        const lzReceiveParams: LzReceiveParams = {
            srcEid: packet.srcEid,
            sender: arrayify(packet.sender),
            nonce: BigInt(packet.nonce),
            guid: arrayify(packet.guid),
            message: arrayify(packet.message),
            callerParams: arrayify("0x"),
        }

        const lzReceiveExecutionPlan = await buildLzReceiveExecutionPlan(umi.rpc, publicKey("6doghB248px58JSSwG4qejQ46kFMW4AMj7vzJnWZHNZn"), umiWalletKeyPair.publicKey, packet.receiver, publicKey(process.env.GOVERNANCE_PROGRAM_ID), lzReceiveParams)
        console.log('lzReceiveExecutionPlan', lzReceiveExecutionPlan)

        const transaction = umi.transactions.create({
            version: 0,
            blockhash: (await umi.rpc.getLatestBlockhash()).blockhash,
            instructions: lzReceiveExecutionPlan.instructions,
            payer: umi.payer.publicKey,
        })
        const signedTransaction = await umiWalletSigner.signTransaction(transaction)

        const simulation = await simulateTransaction(umi, signedTransaction, connection, { verifySignatures: true })
        console.log('simulation', simulation)

        const txHash = await umi.rpc.sendTransaction(signedTransaction)
        console.log('lzReceive tx signature', base58.deserialize(txHash)[0])
    }
)
