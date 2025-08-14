import { task } from 'hardhat/config'
import { makeBytes32 } from '@layerzerolabs/devtools'
import { types as hardhatTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { deriveConnection } from './index'
import { arrayify } from '@ethersproject/bytes'
import { buildLzReceiveExecutionPlan, LzReceiveParams } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { publicKey } from '@metaplex-foundation/umi'
import { AddressLookupTableProgram, Connection, Keypair, PublicKey, TransactionMessage, VersionedTransaction } from '@solana/web3.js'
import { toWeb3JsKeypair, toWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'

interface Args {
    srcTxHash: string
}

const EXECUTOR_PROGRAM_ID = '6doghB248px58JSSwG4qejQ46kFMW4AMj7vzJnWZHNZn'

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

        const lzReceiveParams: LzReceiveParams = {
            srcEid: packet.srcEid,
            sender: arrayify(packet.sender),
            nonce: BigInt(packet.nonce),
            guid: arrayify(packet.guid),
            message: arrayify(packet.message),
            callerParams: arrayify("0x"),
        }

        // const lzReceiveExecutionPlan = await buildLzReceiveExecutionPlan(umi.rpc, publicKey(EXECUTOR_PROGRAM_ID), umiWalletKeyPair.publicKey, packet.receiver, publicKey(process.env.GOVERNANCE_PROGRAM_ID), lzReceiveParams)

        let accountsNotInALT: PublicKey[] = [
            new PublicKey("8yccRDV1DShiVK6qauQew15nyMSDPCA4gZ8SSgzfZSja"),
            new PublicKey("Hfet6nReAywVVhYLQGJNKUnZvcBvjTrTunHuJNSBHTUy"),
            new PublicKey("Fty7h4FYAN7z8yjqaJExMHXbUoJYMcRjWYmggSxLbHp8"),
            new PublicKey("9NrM3fqZT5kuzjHZLTZqFnd7V61d4nk6jn5CaGnLDyJX"),
            new PublicKey("7hd6FKSUgXkzGvbH98tWu8EokQRBwpNgG3gnTwcfXdM5"),
            new PublicKey("6v4JpMKBYCPSDwxptR3gqJNXrJRUDNxr1S6X3T1p7DaX"),
            new PublicKey("7Ackc8DwwpRvEAZsR12Ru27swgk1ifWuEmHQ3g3Q6tbj"),
            new PublicKey("76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6"),
            new PublicKey("DvBDM669Dvg9d54fUFvPVkbuLxxMg5UFH3p5koFUxUd3"),
            new PublicKey("Hh2qaTZnqm4Lwg5tyiAWNts8tEQaNsCmXTQjN9NHs6Xw"),
            new PublicKey("2esa8p2hacesKX1kxR8kdqwYRo3cSjBhpoMNnVgE8eD6"),
            new PublicKey("2uk9pQh3tB5ErV7LGQJcbWjb4KeJ2UJki5qJZ8QG56G3"),
            new PublicKey("F8E8QGhKmHEx2esh5LpVizzcP4cHYhzXdXTwg9w3YYY2"),
            new PublicKey("BzmHSAsoCnGTKFpSMgMQAWYg3oyENLEQjHZJkMGuPDw7"),
            new PublicKey("526PeNZfw8kSnDU4nmzJFVJzJWNhwmZykEyJr5XWz5Fv"),
            new PublicKey("2XgGZG4oP29U3w5h4nTk1V2LFHL23zKDPJjs3psGzLKQ"),
            new PublicKey("11111111111111111111111111111111"),
            new PublicKey("2F9Dhf5d5RaV4bi2ynBnyucAcQ3Rrjewu73TVtN3t6AY"),
            new PublicKey("4ysbi97LSvvr92YQMYJ5mRF17z1srABTPFYiYjmonFqV"),
            new PublicKey("7RgGz7K1un4XzYV33MqYSzZB8qP3RybivGV45yF6T193"),
            new PublicKey("7m9NB2tq16F7wKrJVmuaNt54RhhC5F2iTiX4qgkAyBKQ"),
            new PublicKey("82NZTZoAs5YzT3tdwW2BxgC4d1KnpwyauEB9sScJRA23"),
            new PublicKey("9agtUU8Fv4i1Frq1VUp7GjtzB3Zhu2peTMVmGviFu8jC"),
            new PublicKey("Dbn1xDUs5yRSSgWWreMnVyznBfmvcMLdhwJdCx51RLoD"),
            new PublicKey("GWe6TfHAhNSCwmBZQez3xzehntgGmtn5KeqEoeisscdc"),
            new PublicKey("7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH"),
            new PublicKey("7n1YeBMVEUCJ4DscKAcpVQd6KXU7VpcEcc15ZuMcL4U3"),
            new PublicKey("Ab2kzdakDhFpjNueG5QcUodkgQ8B1RjSZ7jdxH2igzPZ"),
            new PublicKey("Dt42AqkaCyiXY9srP4mCUaBe4QB8LSj5dQmpDJ3RuqHq"),
            new PublicKey("24h8GbHpT2VPLY2LhMC7i5KHVEUhk9zLn2szNYDreqXC"),
            new PublicKey("ComputeBudget111111111111111111111111111111"),
        ];
        
        // if (lzReceiveExecutionPlan.addressLookupTables.length === 0) {
        //     accountsNotInALT = lzReceiveExecutionPlan.instructions[0].keys.map(key => toWeb3JsPublicKey(key.pubkey));
        // }

        // const accountsInAlt = lzReceiveExecutionPlan.instructions[0].keys.length - accountsNotInALT.length;
        // console.log('--------------- ACCOUNTS ---------------')
        // console.log('Total accounts  : ', lzReceiveExecutionPlan.instructions[0].keys.length);
        // console.log('Accounts in ALT : ', accountsInAlt);
        // console.log('Accounts not-ALT: ', accountsNotInALT.length);
        // console.log('Accounts not in ALT:');
        accountsNotInALT.forEach((acc, index) => {
            console.log(`${index}: ${acc.toBase58()}`);
        });
        console.log('--------------------------------------')

        if (accountsNotInALT.length > 0) {
            const lookupTableAddress = await createLookupTable(connection, signer, accountsNotInALT.slice(0, 20))
            await new Promise(resolve => setTimeout(resolve, 60000))
            await extendLookupTable(connection, signer, lookupTableAddress, accountsNotInALT.slice(20))
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

    return lookupTableAddress;
};

async function extendLookupTable(connection: Connection, signer: Keypair, lookupTableAddress: PublicKey, addresses: PublicKey[]) {
    console.log('lookupTableAddress', lookupTableAddress.toBase58())
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
    const txHash = await connection.sendTransaction(tx);
    console.log('extend lookup table', {
        txHash,
        lookupTableAddress,
    })
}