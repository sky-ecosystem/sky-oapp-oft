import assert from 'assert'

import { mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import { createSignerFromKeypair, none, publicKey, signerIdentity, some, transactionBuilder } from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { fromWeb3JsKeypair } from '@metaplex-foundation/umi-web3js-adapters'
import { Keypair } from '@solana/web3.js'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import { createSolanaConnectionFactory } from '../common/utils'
import { setOFTConfig } from './sdk/oft302'
import { getExplorerTxLink } from '.'

interface Args {
    eid: EndpointId
    programId: string
    oftStore: string
    unpauser: string
}

task(
    'lz:oft:solana:set-unpauser',
    "Sets the Solana unpauser"
)
    .addParam('programId', 'The OFT Program id')
    .addParam('eid', 'Solana mainnet (30168) or testnet (40168)', undefined, types.eid)
    .addParam('oftStore', 'The OFTStore account')
    .addParam('unpauser', 'The unpauser address', undefined, types.string)
    .setAction(async (taskArgs: Args, hre) => {
        const privateKey = process.env.SOLANA_PRIVATE_KEY
        assert(!!privateKey, 'SOLANA_PRIVATE_KEY is not defined in the environment variables.')

        const keypair = Keypair.fromSecretKey(bs58.decode(privateKey))
        const umiKeypair = fromWeb3JsKeypair(keypair)

        const connectionFactory = createSolanaConnectionFactory()
        const connection = await connectionFactory(taskArgs.eid)

        const umi = createUmi(connection.rpcEndpoint).use(mplToolbox())
        const umiWalletSigner = createSignerFromKeypair(umi, umiKeypair)
        umi.use(signerIdentity(umiWalletSigner))

        const unpauser = taskArgs.unpauser;

        const ix = setOFTConfig({
            admin: umiWalletSigner,
            oftStore: publicKey(taskArgs.oftStore),
        }, {
            __kind: 'Unpauser',
            fields: unpauser.length > 0 ? [some(publicKey(taskArgs.unpauser))] : [none()],
        }, publicKey(taskArgs.programId));
        
        let txBuilder = transactionBuilder().add([ix])
        const tx = await txBuilder.buildWithLatestBlockhash(umi)
        console.log(Buffer.from(tx.serializedMessage).toString("base64"));
       
        const { signature } = await txBuilder.sendAndConfirm(umi)
        const transactionSignatureBase58 = bs58.encode(signature)

        console.log(`✅ Set unpauser for OFTStore: ${taskArgs.oftStore}!`)
        const isTestnet = taskArgs.eid == EndpointId.SOLANA_V2_TESTNET
        console.log(
            `View Solana transaction here: ${getExplorerTxLink(transactionSignatureBase58.toString(), isTestnet)}`
        )
    })