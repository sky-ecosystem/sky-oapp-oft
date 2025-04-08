import { fetchToken, findAssociatedTokenPda } from '@metaplex-foundation/mpl-toolbox'
import { publicKey, transactionBuilder } from '@metaplex-foundation/umi'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { TOKEN_PROGRAM_ID } from '@solana/spl-token'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { addressToBytes32 } from '@layerzerolabs/lz-v2-utilities'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'

import {
    TransactionType,
    addComputeUnitInstructions,
    deriveConnection,
    getExplorerTxLink,
    getLayerZeroScanLink,
    getSolanaDeployment,
} from './index'

interface Args {
    unpauser: string
    fromEid: EndpointId
    computeUnitPriceScaleFactor: number
}

task('lz:oft:solana:setUnpauser', 'Set the unpauser for the OFT program')
    .addParam('unpauser', 'The unpauser address', undefined, devtoolsTypes.string)
    .addParam('fromEid', 'The source endpoint ID', undefined, devtoolsTypes.eid)
    .setAction(async (args: Args) => {
        const { unpauser, fromEid } = args
        const { connection, umi, umiWalletSigner } = await deriveConnection(fromEid)

        const solanaDeployment = getSolanaDeployment(fromEid)

        const oftProgramId = publicKey(solanaDeployment.programId)
        const oftStore = publicKey(solanaDeployment.oftStore)

        const ix = await oft.setOFTConfig(
            {
                admin: umiWalletSigner,
                oftStore,
            },
            {
                __kind: 'Unpauser',
                unpauser: publicKey(unpauser),
            },
            {
                oft: oftProgramId,
            }
        )

        let txBuilder = transactionBuilder().add([ix])
        const tx = await txBuilder.buildWithLatestBlockhash(umi)
        console.log(Buffer.from(tx.serializedMessage).toString("base64"));
       
        const { signature } = await txBuilder.sendAndConfirm(umi)
        const transactionSignatureBase58 = bs58.encode(signature)

        console.log(`✅ Set unpauser for OFT program to ${unpauser}!`)
        const isTestnet = fromEid == EndpointId.SOLANA_V2_TESTNET
        console.log(
            `View Solana transaction here: ${getExplorerTxLink(transactionSignatureBase58.toString(), isTestnet)}`
        )
    })
