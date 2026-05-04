/**
 * Simulate a serialized governance message produced by cargo test
 * (e.g. the trailing base64 line printed by `prepare_governance_message_simulation`).
 *
 * Skips ix construction entirely — it just decodes the message, simulates it on
 * the live cluster with `sigVerify: false` + `replaceRecentBlockhash: true`, and
 * decodes any writable account it recognizes (OFTStore / PeerConfig).
 */
import { task } from 'hardhat/config'
import { Message, PublicKey, SystemProgram, VersionedTransaction } from '@solana/web3.js'
import { Base64 } from 'js-base64'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'

import { deriveConnection } from './index'
import { ETHEREUM_PEER_PDA, OFT_PROGRAM_ID, OFT_STORE } from './consts-mainnet'
import { accounts as oftAccounts } from './sdk/oft302'
import { deserializePeerConfig } from './sdk/generated/oft302/accounts/peerConfig'

interface Args {
    data: string
}

task(
    'lz:oapp:solana:simulate-governance-message',
    'Simulate a base64-encoded governance message produced by cargo test'
)
    .addParam('data', 'Base64-encoded message data from prepare_governance_message_simulation')
    .setAction(async (taskArgs: Args) => {
        const { connection } = await deriveConnection(30168, true)

        const message = Message.from(Buffer.from(taskArgs.data, 'base64'))
        const versionedTx = new VersionedTransaction(message)

        const writable: PublicKey[] = []
        for (let i = 0; i < message.accountKeys.length; i++) {
            if (message.isAccountWritable(i)) writable.push(message.accountKeys[i])
        }

        const simulation = await connection.simulateTransaction(versionedTx, {
            sigVerify: false,
            replaceRecentBlockhash: true,
            accounts: {
                encoding: 'base64',
                addresses: writable.map((p) => p.toBase58()),
            },
        })
        console.log('simulation', simulation.value)

        if (simulation.value.err) {
            throw new Error(`Simulation error: ${JSON.stringify(simulation.value.err)}`)
        }

        const ethereumPeerPda = new PublicKey(ETHEREUM_PEER_PDA)
        const systemProgramId = SystemProgram.programId.toBase58()
        for (const [i, addr] of writable.entries()) {
            const account = simulation.value.accounts?.[i]
            const accData = account?.data?.[0]
            if (!accData) {
                if (account?.owner === systemProgramId) {
                    console.warn(
                        `warn: skipping ${addr.toBase58()} — system-owned (lamports only), no decodable data`
                    )
                    continue
                }
                throw new Error(
                    `No account data returned for ${addr.toBase58()} (owner: ${account?.owner ?? 'null'})`
                )
            }
            const bytes = Base64.toUint8Array(accData)

            if (addr.equals(OFT_STORE)) {
                const store = oftAccounts.deserializeOFTStore({
                    publicKey: fromWeb3JsPublicKey(addr),
                    data: bytes,
                    executable: false,
                    lamports: { basisPoints: 0n, identifier: 'SOL', decimals: 9 },
                    owner: fromWeb3JsPublicKey(OFT_PROGRAM_ID),
                })
                console.log(`OFTStore (${addr.toBase58()}).paused`, store.paused)
                continue
            }

            if (addr.equals(ethereumPeerPda)) {
                const peerConfig = deserializePeerConfig({
                    publicKey: ETHEREUM_PEER_PDA,
                    data: bytes,
                    executable: false,
                    lamports: { basisPoints: 0n, identifier: 'SOL', decimals: 9 },
                    owner: fromWeb3JsPublicKey(OFT_PROGRAM_ID),
                })
                console.log(
                    `PeerConfig (${addr.toBase58()}).inboundRateLimiter`,
                    peerConfig.inboundRateLimiter
                )
                console.log(
                    `PeerConfig (${addr.toBase58()}).outboundRateLimiter`,
                    peerConfig.outboundRateLimiter
                )
                continue
            }

            console.log(`account ${addr.toBase58()} (no known schema, base64):`, accData)
        }
    })
