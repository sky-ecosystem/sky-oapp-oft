import assert from 'assert'

import { mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { createNoopSigner, createSignerFromKeypair, none, publicKey, signerIdentity, some, transactionBuilder } from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { fromWeb3JsKeypair } from '@metaplex-foundation/umi-web3js-adapters'
import { Keypair, VersionedMessage, VersionedTransaction } from '@solana/web3.js'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import { createSolanaConnectionFactory } from '../common/utils'
import { setPause } from './sdk/oft302'

interface Args {
    eid: EndpointId
    programId: string
    oftStore: string
    squadsAuthority: string
}

task(
    'lz:oft:solana:pause:squads',
    "Pauses the Solana OFT"
)
    .addParam('programId', 'The OFT Program id')
    .addParam('eid', 'Solana mainnet (30168) or testnet (40168)', undefined, types.eid)
    .addParam('oftStore', 'The OFTStore account')
    .addParam('squadsAuthority', 'The Squads authority public key', undefined, types.string)
    .setAction(async (taskArgs: Args, hre) => {
        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(taskArgs.eid)
        const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())

        let squadsAuthority = publicKey(taskArgs.squadsAuthority);
        const squadsSigner = createNoopSigner(squadsAuthority);

        umi.use(signerIdentity(squadsSigner))

        const txBuilder = transactionBuilder().add(
            setPause(
                {
                    signer: squadsSigner,
                    oftStore: publicKey(taskArgs.oftStore),
                },
                true,
                publicKey(taskArgs.programId)
            )
        );
        txBuilder.setFeePayer(squadsSigner)

        const serializedTx = await txBuilder.buildWithLatestBlockhash(umi)
        const transactionDataHex = Buffer.from(serializedTx.serializedMessage).toString("hex")
        const versionedMessage = VersionedMessage.deserialize(Buffer.from(transactionDataHex, 'hex'))
        
        const tx = new VersionedTransaction(versionedMessage);
        
        console.log('BASE58: \n')
        console.log(bs58.encode(Buffer.from(tx.serialize())))
        console.log('\nBASE64: \n')
        console.log(Buffer.from(tx.serialize()).toString("base64"));
    })