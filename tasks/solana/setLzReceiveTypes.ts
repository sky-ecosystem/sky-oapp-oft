import { AccountMeta, publicKey, transactionBuilder } from '@metaplex-foundation/umi'
import bs58 from 'bs58'
import { task } from 'hardhat/config'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'
import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'

import {
    TransactionType,
    addComputeUnitInstructions,
    deriveConnection,
    getExplorerTxLink,
    getLayerZeroScanLink,
    getSolanaDeployment,
} from './index'
import { Governance, types } from '../../src/governance'
import { PublicKey } from '@solana/web3.js'
import { fromWeb3JsInstruction, fromWeb3JsPublicKey, toWeb3JsKeypair } from '@metaplex-foundation/umi-web3js-adapters'

interface Args {
    alts: string
    fromEid: EndpointId
}

task('lz:oapp:solana:setLzReceiveTypes', 'Set the lzReceiveTypes for the OApp')
    .addParam('alts', 'The comma separated list of alts', undefined, devtoolsTypes.string)
    .addParam('fromEid', 'The source endpoint ID', undefined, devtoolsTypes.eid)
    .setAction(async (args: Args) => {
        const { fromEid, alts: altsCommaSeparated } = args
        const { connection, umi, umiWalletSigner } = await deriveConnection(fromEid)
        const signer = toWeb3JsKeypair(umiWalletSigner)
        const alts = altsCommaSeparated.split(',').map(alt => new PublicKey(alt))

        if (!process.env.GOVERNANCE_PROGRAM_ID) {
            throw new Error('GOVERNANCE_PROGRAM_ID is not defined in the environment variables.')
        }

        const governance = new Governance(new PublicKey(process.env.GOVERNANCE_PROGRAM_ID), 0)

        const [version, lzReceiveTypesV2Accounts] = await governance.getLzReceiveTypesInfo(connection)
        console.log('Current accounts:', {
            alts: lzReceiveTypesV2Accounts.alts.map(alt => alt.toBase58()),
            accounts: lzReceiveTypesV2Accounts.accounts.map(account => JSON.stringify(account)),
        })

        const accounts: types.AddressOrAltIndex[] = [
            {
                __kind: 'Address',
                fields: [governance.idPDA()[0]]
            },
            ...alts.map(alt => ({
                __kind: 'Address',
                fields: [alt]
            })) as types.AddressOrAltIndex[]
        ];

        const alreadySet = lzReceiveTypesV2Accounts.alts.map(alt => alt.toBase58()).join(',') === altsCommaSeparated;
        if (alreadySet) {
            console.log('Already set')
            return
        } else {
            console.log('Not set, diff', {
                A: lzReceiveTypesV2Accounts.alts.map(alt => alt.toBase58()).join(','),
                B: altsCommaSeparated,
            })
        }

        const ix = governance.setLzReceiveTypesAccounts(signer.publicKey, accounts, alts)
        const umiInstruction = {
            programId: publicKey(ix.programId.toBase58()),
            keys: ix.keys.map((key) => ({
                pubkey: key.pubkey,
                isSigner: key.isSigner,
                isWritable: key.isWritable,
            })) as unknown as AccountMeta[],
            data: ix.data,
        }
        let txBuilder = transactionBuilder().add({
            instruction: umiInstruction,
            signers: [umiWalletSigner],
            bytesCreatedOnChain: 0,
        })
        
        const tx = await txBuilder.buildWithLatestBlockhash(umi)
        console.log(Buffer.from(tx.serializedMessage).toString("base64"));
       
        const { signature } = await txBuilder.sendAndConfirm(umi)
        
        console.log(
            `Transaction sent: ${getExplorerTxLink(bs58.encode(signature), fromEid == EndpointId.SOLANA_V2_TESTNET)}`
        )
    })
