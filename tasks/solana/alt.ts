import { task } from 'hardhat/config'
import { makeBytes32 } from '@layerzerolabs/devtools'
import { types as hardhatTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { deriveConnection } from './index'
import { arrayify } from '@ethersproject/bytes'
import { buildLzReceiveExecutionPlan, LzReceiveParams } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { publicKey } from '@metaplex-foundation/umi'
import { AddressLookupTableAccount, AddressLookupTableProgram, Connection, Keypair, PublicKey, TransactionMessage, VersionedTransaction } from '@solana/web3.js'
import { EndpointProgram } from '@layerzerolabs/lz-solana-sdk-v2'
import { Governance } from '../../src/governance'
import { toWeb3JsKeypair, toWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'

interface Args {
    srcTxHash: string
}

task('lz:oapp:solana:alt-prepare', 'Prepare the ALT for the message')
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
        const signer = toWeb3JsKeypair(umiWalletKeyPair)
        
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

        const endpointProgram = new EndpointProgram.Endpoint(new PublicKey('76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6')) // endpoint program id, mainnet and testnet are the same
        const governance = new Governance(new PublicKey(process.env.GOVERNANCE_PROGRAM_ID), endpointProgram)
        const lzReceiveTypesV2Accounts = await governance.getLzReceiveTypesAccounts(connection)

        const altsKeys = lzReceiveTypesV2Accounts?.alts || [];
        console.log('Current accounts:', {
            alts: altsKeys.map(alt => alt.toBase58()),
        })

        const alts: AddressLookupTableAccount[] = [];
        for (const alt of altsKeys) {
            const lookupTableAccount = (
                await connection.getAddressLookupTable(alt)
            ).value;

            if (!lookupTableAccount) {
                throw new Error("ALT not found");
            }

            alts.push(lookupTableAccount);
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

        let accountsNotInALT: PublicKey[] = [];
        
        if (alts.length === 0) {
            accountsNotInALT = lzReceiveExecutionPlan.instructions[0].keys.map(key => toWeb3JsPublicKey(key.pubkey));
        }

        const accountsInAlt = lzReceiveExecutionPlan.instructions[0].keys.length - accountsNotInALT.length;
        console.log('--------------- ACCOUNTS ---------------')
        console.log('Total accounts  : ', lzReceiveExecutionPlan.instructions[0].keys.length);
        console.log('Accounts in ALT : ', accountsInAlt);
        console.log('Accounts not-ALT: ', accountsNotInALT.length);
        console.log('Accounts not in ALT:');
        accountsNotInALT.forEach((acc, index) => {
            console.log(`${index}: ${acc.toBase58()}`);
        });
        console.log('--------------------------------------')

        if (accountsNotInALT.length > 0) {
            await createLookupTable(connection, signer, accountsNotInALT)
        }
    }
)

async function createLookupTable(connection: Connection, signer: Keypair, addresses: PublicKey[]) {
    const [createInstruction, lookupTableAddress] = AddressLookupTableProgram.createLookupTable({
        payer: signer.publicKey,
        authority: signer.publicKey,
        recentSlot: await connection.getSlot(),
    });
    const extendInstruction = AddressLookupTableProgram.extendLookupTable({
        payer: signer.publicKey,
        authority: signer.publicKey,
        lookupTable: lookupTableAddress,
        addresses: addresses,
    });

    const blockhash = await connection.getLatestBlockhash();
    const message = new TransactionMessage({
        payerKey: signer.publicKey,
        recentBlockhash: blockhash.blockhash,
        instructions: [createInstruction, extendInstruction],
    }).compileToV0Message();
    const tx = new VersionedTransaction(message);
    tx.sign([signer]);
    const txHash = await connection.sendTransaction(tx);
    console.log('create lookup table', {
        txHash,
        lookupTableAddress,
    })
};
