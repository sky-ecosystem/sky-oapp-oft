import { BN } from '@coral-xyz/anchor'
import { toWeb3JsKeypair } from '@metaplex-foundation/umi-web3js-adapters'
import { AccountMeta, AddressLookupTableAccount, Connection, Keypair, PublicKey, TransactionMessage, VersionedTransaction } from '@solana/web3.js'
import bs58 from 'bs58'
import { task } from 'hardhat/config'
import { makeBytes32 } from '@layerzerolabs/devtools'
import { types } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { lzReceive, buildVersionedTransaction } from '@layerzerolabs/lz-solana-sdk-v2'
import { deriveConnection } from './index'
import { arrayify } from '@ethersproject/bytes'
import { Governance } from '../../src/governance'
import { GovernanceProgram } from '../../src'
import * as beet from '@metaplex-foundation/beet'

interface Args {
    srcTxHash: string
    computeUnits: number
    lamports: number
    withPriorityFee: number
}

task('lz:oapp:solana:clear-with-alt', 'Clear a stored payload on Solana')
    .addParam('srcTxHash', 'The source transaction hash', undefined, types.string)
    .addParam('computeUnits', 'The CU for the lzReceive instruction', undefined, types.int)
    .addParam('lamports', 'The lamports for the lzReceive instruction', undefined, types.int)
    .addParam('withPriorityFee', 'The priority fee in microLamports', undefined, types.int)
    .setAction(
        async ({
            srcTxHash,
            computeUnits,
            lamports,
            withPriorityFee,
        }: Args) => {
            if (!process.env.SOLANA_PRIVATE_KEY) {
                throw new Error('SOLANA_PRIVATE_KEY is not defined in the environment variables.')
            }

            const response = await fetch(`https://scan-testnet.layerzero-api.com/v1/messages/tx/${srcTxHash}`)
            const data = await response.json()
            const message = data.data[0];

            if (message.destination.status === 'SUCCEEDED') {
                console.log('--------------------------------')
                console.log('\nTransaction already delivered: \n')
                console.log(`https://explorer.solana.com/tx/${message.destination.tx.txHash}?cluster=devnet`)
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
            const callerParams = Uint8Array.from([computeUnits, lamports]);

            const lzReceiveInstruction = await lzReceive(
                connection,
                signer.publicKey,
                packet,
                callerParams,
                'confirmed'
            )

        const signerKeypair = Keypair.fromSecretKey(bs58.decode(process.env.SOLANA_PRIVATE_KEY))

        if (!process.env.GOVERNANCE_PROGRAM_ID) {
            throw new Error('GOVERNANCE_PROGRAM_ID is not defined in the environment variables.')
        }

        const governance = new Governance(new PublicKey(process.env.GOVERNANCE_PROGRAM_ID), 0)
        const lookupTableAddress = await governance.getLzReceiveAltUnderlyingAddress(connection)

        const lookupTableAccount = (
            await connection.getAddressLookupTable(new PublicKey(lookupTableAddress))
        ).value;
    
        if (!lookupTableAccount) {
            throw new Error("Lookup table account not found");
        }

        const lzReceiveParams = {
            srcEid: packet.srcEid,
            sender: Array.from(arrayify(packet.sender)),
            nonce: new BN(packet.nonce),
            guid: Array.from(arrayify(packet.guid)),
            message: arrayify(packet.message),
            extraData: arrayify("0x"),
        }

        const lzReceiveAccountsFromLzReceiveTypesWithAlt = await getLzReceiveAccountsFromLzReceiveTypesWithAlt(connection, signer, governance, lookupTableAccount, lzReceiveParams)

        lzReceiveInstruction.keys = lzReceiveAccountsFromLzReceiveTypesWithAlt;

        const blockhash = await connection.getLatestBlockhash();
        const lzReceiveMessage = new TransactionMessage({
            payerKey: signer.publicKey,
            recentBlockhash: blockhash.blockhash,
            instructions: [lzReceiveInstruction],
        }).compileToV0Message([lookupTableAccount]);

        const lzReceiveTx = new VersionedTransaction(lzReceiveMessage);
        
        lzReceiveTx.sign([signerKeypair]);

        console.log(Buffer.from(lzReceiveTx.serialize()).toString('base64'));

        const simulation = (await connection.simulateTransaction(lzReceiveTx, { sigVerify: true }));

        console.log('simulation', simulation)

        const lzReceiveTxSignature = await connection.sendTransaction(lzReceiveTx);

        console.log("lzReceive tx signature", lzReceiveTxSignature)
    }
)

async function getLzReceiveAccountsFromLzReceiveTypesWithAlt(connection: Connection, signer: Keypair, governance: Governance, lookupTableAccount: AddressLookupTableAccount, lzReceiveParams: GovernanceProgram.types.LzReceiveParams): Promise<AccountMeta[]> {
    const altAddresses = lookupTableAccount.state.addresses;

    const ix = await governance.getLzReceiveTypesWithAlt(connection, lzReceiveParams)

    const blockhash = await connection.getLatestBlockhash();
    const tx = await buildVersionedTransaction(connection, signer.publicKey, [ix], 'confirmed', blockhash.blockhash)

    const simulation = (await connection.simulateTransaction(tx, { sigVerify: false })).value

    const lzAccountAltBeet = GovernanceProgram.types.lzAccountAltBeet

    if (!simulation.returnData?.data) {
        throw new Error('No return data available')
    }

    const buffer = Buffer.from(simulation.returnData.data[0], 'base64');

    const resultArray = beet.array(lzAccountAltBeet)
    const fixedBeet = resultArray.toFixedFromData(buffer, 0)

    const accounts = fixedBeet.read(buffer, 0)

    const lzReceiveAccountsFromLzReceiveTypesWithAlt: AccountMeta[] = accounts.map((acc) => {
        const key = acc.isAltIndex ? altAddresses[acc.indexOrPubkey[0]] : new PublicKey(acc.indexOrPubkey)
        const account = {
            pubkey: key,
            isWritable: acc.isWritable,
            isSigner: acc.isSigner,
        };

        // replace payer placeholder with actual address
        if (acc.isSigner && key.toBase58() === PublicKey.default.toBase58()) {
            account.pubkey = signer.publicKey
        }

        return account
    })
    
    return lzReceiveAccountsFromLzReceiveTypesWithAlt
}