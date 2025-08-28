import { AccountMeta, publicKey, transactionBuilder } from '@metaplex-foundation/umi'
import bs58 from 'bs58'
import { task } from 'hardhat/config'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import {
    deriveConnection,
    getExplorerTxLink,
} from './index'
import { Governance } from '../../src/governance'
import { PublicKey } from '@solana/web3.js'
import { toWeb3JsKeypair } from '@metaplex-foundation/umi-web3js-adapters'
import { EndpointProgram } from '@layerzerolabs/lz-solana-sdk-v2'

interface Args {
    alts: string
    eid: EndpointId
}

task('lz:oapp:solana:set-alts', 'Set the alts for the OApp')
    .addParam('alts', 'The comma separated list of alts', undefined, devtoolsTypes.string)
    .addParam('eid', 'The endpoint ID', undefined, devtoolsTypes.eid)
    .setAction(async (args: Args) => {
        const { eid, alts: altsCommaSeparated } = args
        const { connection, umi, umiWalletSigner } = await deriveConnection(eid)
        const signer = toWeb3JsKeypair(umiWalletSigner)
        const alts = altsCommaSeparated.split(',').map(alt => new PublicKey(alt))

        if (!process.env.GOVERNANCE_PROGRAM_ID) {
            throw new Error('GOVERNANCE_PROGRAM_ID is not defined in the environment variables.')
        }

        const endpointProgram = new EndpointProgram.Endpoint(new PublicKey('76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6')) // endpoint program id, mainnet and testnet are the same
        const governance = new Governance(new PublicKey(process.env.GOVERNANCE_PROGRAM_ID), endpointProgram)
        const lzReceiveTypesV2Accounts = await governance.getLzReceiveTypesAccounts(connection)
        console.log('Current accounts:', {
            alts: lzReceiveTypesV2Accounts?.alts.map(alt => alt.toBase58()),
        })

        const alreadySet = lzReceiveTypesV2Accounts?.alts.map(alt => alt.toBase58()).join(',') === altsCommaSeparated;
        if (alreadySet) {
            console.log('Already set')
            return
        } else {
            console.log('Not set, diff', {
                A: lzReceiveTypesV2Accounts?.alts.map(alt => alt.toBase58()).join(','),
                B: altsCommaSeparated,
            })
        }

        const ix = governance.setLzReceiveTypesAccounts(signer.publicKey, alts);
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
            `Transaction sent: ${getExplorerTxLink(bs58.encode(signature), eid == EndpointId.SOLANA_V2_TESTNET)}`
        )
    })
