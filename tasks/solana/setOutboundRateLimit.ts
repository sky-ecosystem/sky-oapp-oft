import assert from 'assert'

import { mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { createSignerFromKeypair, publicKey, signerIdentity, transactionBuilder } from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { fromWeb3JsKeypair } from '@metaplex-foundation/umi-web3js-adapters'
import { Keypair } from '@solana/web3.js'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import { createSolanaConnectionFactory } from '../common/utils'
import { setPeerConfig } from './sdk/oft302'
import { RateLimiterType } from './sdk/generated/oft302'
import { getExplorerTxLink } from '.'

interface Args {
    mint: string
    eid: EndpointId
    dstEid: EndpointId
    programId: string
    oftStore: string
    capacity: bigint
    refillPerSecond: bigint
    type: string
}

task(
    'lz:oft:solana:outbound-rate-limit',
    "Sets the Solana and EVM rate limits from './scripts/solana/utils/constants.ts'"
)
    .addParam('mint', 'The OFT token mint public key')
    .addParam('programId', 'The OFT Program id')
    .addParam('eid', 'Solana mainnet (30168) or testnet (40168)', undefined, types.eid)
    .addParam('dstEid', 'The destination endpoint ID', undefined, types.eid)
    .addParam('oftStore', 'The OFTStore account')
    .addParam('capacity', 'The capacity of the rate limit', undefined, types.bigint)
    .addParam('refillPerSecond', 'The refill rate of the rate limit', undefined, types.bigint)
    .addParam('type', 'The type of the rate limit: net or gross', undefined)
    .setAction(async (taskArgs: Args, hre) => {
        if (taskArgs.type !== 'net' && taskArgs.type !== 'gross') {
            throw new Error('Invalid rate limit type. Must be either "net" or "gross".')
        }
        ``
        const rateLimiterType = taskArgs.type === 'net' ? RateLimiterType.Net : RateLimiterType.Gross;

        const privateKey = process.env.SOLANA_PRIVATE_KEY
        assert(!!privateKey, 'SOLANA_PRIVATE_KEY is not defined in the environment variables.')

        const keypair = Keypair.fromSecretKey(bs58.decode(privateKey))
        const umiKeypair = fromWeb3JsKeypair(keypair)

        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(taskArgs.eid)

        const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())
        const umiWalletSigner = createSignerFromKeypair(umi, umiKeypair)
        umi.use(signerIdentity(umiWalletSigner))

        const ix = setPeerConfig({
                admin: umiWalletSigner,
                oftStore: publicKey(taskArgs.oftStore),
            },
            {
                __kind: 'OutboundRateLimit',
                rateLimit: {
                    capacity: taskArgs.capacity,
                    refillPerSecond: taskArgs.refillPerSecond,
                    rateLimiterType,
                },
                remote: taskArgs.dstEid,
            },
            publicKey(taskArgs.programId)
        )
       
        
        let txBuilder = transactionBuilder().add([ix])
        const tx = await txBuilder.buildWithLatestBlockhash(umi)
        console.log(Buffer.from(tx.serializedMessage).toString("base64"));
       
        const { signature } = await txBuilder.sendAndConfirm(umi)
        const transactionSignatureBase58 = bs58.encode(signature)

        console.log(`✅ Set outbound rate limit for destination endpoint id: ${taskArgs.dstEid}!`)
        const isTestnet = taskArgs.eid == EndpointId.SOLANA_V2_TESTNET
        console.log(
            `View Solana transaction here: ${getExplorerTxLink(transactionSignatureBase58.toString(), isTestnet)}`
        )
    })
    