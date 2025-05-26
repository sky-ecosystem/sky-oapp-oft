import { BN } from '@coral-xyz/anchor'
import { toWeb3JsKeypair } from '@metaplex-foundation/umi-web3js-adapters'
import { AccountMeta, AddressLookupTableAccount, Connection, Keypair, PublicKey, TransactionMessage, VersionedTransaction, AddressLookupTableProgram } from '@solana/web3.js'
import bs58 from 'bs58'
import { task } from 'hardhat/config'
import { makeBytes32 } from '@layerzerolabs/devtools'
import { types as hardhatTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { deriveConnection } from './index'
import { arrayify } from '@ethersproject/bytes'
import { Governance, instructions, types } from '../../src/governance'
import { isAddressOrAltIndexAltIndex } from '../../src/generated/governance'

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

        const { connection, umiWalletKeyPair } = await deriveConnection(message.pathway.dstEid)
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

        const signerKeypair = Keypair.fromSecretKey(bs58.decode(process.env.SOLANA_PRIVATE_KEY))

        if (!process.env.GOVERNANCE_PROGRAM_ID) {
            throw new Error('GOVERNANCE_PROGRAM_ID is not defined in the environment variables.')
        }

        const governance = new Governance(new PublicKey(process.env.GOVERNANCE_PROGRAM_ID), 0)
        const [version, lzReceiveTypesV2Accounts] = await governance.getLzReceiveTypesInfo(connection)
        console.log('lzReceiveTypesInfo', lzReceiveTypesV2Accounts)

        if (version !== 2) {
            throw new Error(`Invalid lz_receive version ${version}. Expected version 2.`)
        }

        const lzReceiveParams: types.LzReceiveParams = {
            srcEid: packet.srcEid,
            sender: Array.from(arrayify(packet.sender)),
            nonce: new BN(packet.nonce),
            guid: Array.from(arrayify(packet.guid)),
            message: arrayify(packet.message),
            extraData: arrayify("0x"),
        }

        const lzReceiveTypesResult = await governance.getLzReceiveTypesV2(connection, lzReceiveParams, lzReceiveTypesV2Accounts.accounts, lzReceiveTypesV2Accounts.alts)

        const lzReceiveInstruction = instructions.createLzReceiveInstruction(
            {} as any,
            {
                params: lzReceiveParams,
            },
            governance.program
        );

        const alts: AddressLookupTableAccount[] = [];
        for (const alt of lzReceiveTypesV2Accounts.alts) {
            const lookupTableAccount = (
                await connection.getAddressLookupTable(alt)
            ).value;

            if (!lookupTableAccount) {
                throw new Error("ALT not found");
            }

            alts.push(lookupTableAccount);
        }

        const keys: AccountMeta[] = [];
        const accountsNotInALT: PublicKey[] = [];
        let index = 0;
        for (const account of lzReceiveTypesResult.instructions[0].accounts) {
            let pubkey: PublicKey;
            if (isAddressOrAltIndexAltIndex(account.pubkey)) {
                pubkey = alts[account.pubkey.fields[0]].state.addresses[account.pubkey.fields[1]];
            } else {
                pubkey = account.pubkey.fields[0];
                accountsNotInALT.push(pubkey);
            }

            const isSigner = index === 0;
            if (isSigner && pubkey.toBase58() === PublicKey.default.toBase58()) {
                pubkey = signer.publicKey;
            }

            keys.push({
                pubkey,
                isSigner,
                isWritable: account.isWritable,
            });

            index++;
        }

        const accountsInAlt = keys.length - accountsNotInALT.length;
        console.log('--------------- ACCOUNTS ---------------')
        console.log('Total accounts  : ', keys.length);
        console.log('Accounts in ALT : ', accountsInAlt);
        console.log('Accounts not-ALT: ', accountsNotInALT.length);
        console.log('Accounts not in ALT:');
        accountsNotInALT.forEach((acc, index) => {
            console.log(`${index}: ${acc.toBase58()}`);
        });
        console.log('--------------------------------------')

        // if (accountsNotInALT.length > 0) {
        //     await createLookupTable(connection, signer, accountsNotInALT)
        //     await extendLookupTable(connection, signer, alts[0].key, accountsNotInALT)
        // }

        lzReceiveInstruction.keys = keys;

        const blockhash = await connection.getLatestBlockhash();
        const lzReceiveMessage = new TransactionMessage({
            payerKey: signer.publicKey,
            recentBlockhash: blockhash.blockhash,
            instructions: [lzReceiveInstruction],
        }).compileToV0Message(alts);

        const lzReceiveTx = new VersionedTransaction(lzReceiveMessage);
        
        lzReceiveTx.sign([signerKeypair]);

        console.log(Buffer.from(lzReceiveTx.serialize()).toString('base64'));

        const simulation = (await connection.simulateTransaction(lzReceiveTx, { sigVerify: true }));

        console.log('simulation', simulation)

        const lzReceiveTxSignature = await connection.sendTransaction(lzReceiveTx);

        console.log("lzReceive tx signature", lzReceiveTxSignature)
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

async function extendLookupTable(connection: Connection, signer: Keypair, lookupTableAddress: PublicKey, addresses: PublicKey[]) {
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
        instructions: [extendInstruction],
    }).compileToV0Message();
    const tx = new VersionedTransaction(message);
    tx.sign([signer]);
    const signature = await connection.sendTransaction(tx);
    console.log('extend instruction', signature)
};