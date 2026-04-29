import { task } from 'hardhat/config'
import { PublicKey } from '@solana/web3.js'
import { base58 } from '@metaplex-foundation/umi/serializers'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'

import { deriveConnection } from './index'
import { ixDataFromHex, simulateTransaction } from './utils'
import { ETHEREUM_PEER_PDA, L1_GOV_RELAY_CPI_AUTHORITY } from './consts-mainnet'
import { buildRateLimitIx, decodePeerConfigFromSimulation } from './simulateRateLimitHelpers'

task('lz:oapp:solana:simulate-inbound-rate-limit', '')
    .setAction(async () => {
        if (!process.env.SOLANA_PRIVATE_KEY) {
            throw new Error('SOLANA_PRIVATE_KEY is not defined in the environment variables.')
        }

        const { connection, umi } = await deriveConnection(30168)

        // From cargo test test_set_inbound_rate_limit:
        //   remote_eid=30101, refill_per_second=111, capacity=222222, type=Net
        //   PeerConfigParam variant byte = 0x04 (InboundRateLimit)
        const ix = buildRateLimitIx(
            ixDataFromHex('4fbba8398b8c5d2f957500000401016f00000000000000010e640300000000000100')
        )

        const transaction = umi.transactions.create({
            version: 0,
            blockhash: (await umi.rpc.getLatestBlockhash()).blockhash,
            instructions: [ix],
            payer: fromWeb3JsPublicKey(L1_GOV_RELAY_CPI_AUTHORITY),
            addressLookupTables: [],
        })

        console.log('serializedMessage', base58.deserialize(transaction.serializedMessage)[0])

        const simulation = await simulateTransaction(umi, transaction, connection, {
            verifySignatures: false,
            accounts: [new PublicKey(ETHEREUM_PEER_PDA)],
        })
        console.log('simulation', simulation)

        const newPeerConfig = decodePeerConfigFromSimulation(simulation)
        console.log('newPeerConfig.inboundRateLimiter', newPeerConfig.inboundRateLimiter)
        console.log('newPeerConfig.outboundRateLimiter', newPeerConfig.outboundRateLimiter)
    })
