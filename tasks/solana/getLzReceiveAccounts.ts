import { toWeb3JsKeypair } from '@metaplex-foundation/umi-web3js-adapters'
import { PublicKey } from '@solana/web3.js'
import { task } from 'hardhat/config'

import { makeBytes32 } from '@layerzerolabs/devtools'
import { types } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { getLzReceiveAccounts } from '@layerzerolabs/lz-solana-sdk-v2'

import { deriveConnection } from './index'
import { addressToBytes32 } from '@layerzerolabs/lz-v2-utilities'
import { arrayify } from '@ethersproject/bytes'

interface Args {
    srcEid: EndpointId
    nonce: bigint
    sender: string
    dstEid: EndpointId
    receiver: string
    guid: string
    payload: string
}

task('lz:oapp:solana:get-lz-receive-accounts', 'Get the accounts for a lzReceive instruction on Solana')
    .addParam('srcEid', 'The source EndpointId', undefined, types.eid)
    .addParam('nonce', 'The nonce of the payload', undefined, types.bigint)
    .addParam('sender', 'The source OApp address (hex)', undefined, types.string)
    .addParam('dstEid', 'The destination EndpointId (Solana chain)', undefined, types.eid)
    .addParam('receiver', 'The receiver address on the destination Solana chain (bytes58)', undefined, types.string)
    .addParam('guid', 'The GUID of the message (hex)', undefined, types.string)
    .addParam('payload', 'The message payload (hex)', undefined, types.string)
    .setAction(
        async ({
            srcEid,
            nonce,
            sender,
            dstEid,
            receiver,
            guid,
            payload,
        }: Args) => {
            if (!process.env.SOLANA_PRIVATE_KEY) {
                throw new Error('SOLANA_PRIVATE_KEY is not defined in the environment variables.')
            }

            const { connection, umiWalletKeyPair } = await deriveConnection(dstEid)
            const signer = toWeb3JsKeypair(umiWalletKeyPair)

            const packet = {
                nonce: nonce.toString(),
                srcEid,
                sender: makeBytes32(sender),
                dstEid,
                receiver,
                payload: '', // unused;  just added to satisfy typing
                guid,
                message: payload, // referred to as "payload" in scan-api
                version: 1, // unused;  just added to satisfy typing
            }
            const callerParams = Uint8Array.from([0, 0]);

            const commitmentOrConfig = "confirmed";
            const payer = signer.publicKey;
            const { message: message_, sender: sender_, srcEid: srcEid_, guid: guid_, receiver: receiver_ } = packet;
            const receiverPubKey = new PublicKey(addressToBytes32(receiver_));
            const receiverInfo = await connection.getParsedAccountInfo(receiverPubKey, commitmentOrConfig);
            if (receiverInfo.value == null) {
                throw new Error(`Receiver account not found: ${receiverPubKey.toBase58()}`);
            }
            const receiverProgram = new PublicKey(receiverInfo.value.owner);
            const message = arrayify(message_);
            const params = {
                srcEid: srcEid_,
                sender: Array.from(arrayify(sender_)),
                guid: Array.from(arrayify(guid_)),
                message,
                callerParams,
                nonce: parseInt(packet.nonce)
              };
            const accounts = await getLzReceiveAccounts(
                connection,
                payer,
                receiverPubKey,
                receiverProgram,
                params,
                commitmentOrConfig
            );

            console.log('lz_receive_types accounts')
            console.log(accounts)
        }
    )
