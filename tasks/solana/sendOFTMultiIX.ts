import { fetchToken, findAssociatedTokenPda, fetchAddressLookupTable, setComputeUnitPrice, setComputeUnitLimit } from '@metaplex-foundation/mpl-toolbox'
import { publicKey, transactionBuilder, WrappedInstruction } from '@metaplex-foundation/umi'
import { base64 } from '@metaplex-foundation/umi/serializers'
import { fromWeb3JsPublicKey, toWeb3JsKeypair, toWeb3JsPublicKey, fromWeb3JsInstruction } from '@metaplex-foundation/umi-web3js-adapters'
import { TOKEN_PROGRAM_ID } from '@solana/spl-token'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { types } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { addressToBytes32 } from '@layerzerolabs/lz-v2-utilities'
import { oft } from '@layerzerolabs/oft-v2-solana-sdk'

import {
    deriveConnection,
    getExplorerTxLink,
    getLayerZeroScanLink,
} from './index'

import { Governance } from '../../src/governance'
import { PublicKey } from '@solana/web3.js'

interface Args {
    amount: bigint
    to: string
    fromEid: EndpointId
    toEid: EndpointId
    programId: string
    mint: string
    escrow: string
    tokenProgram: string
    computeUnitPriceScaleFactor: number
}

// Define a Hardhat task for sending OFT from Solana
task('lz:oft:solana:send-multi-ix', 'Send tokens from Solana to a target EVM chain')
    .addParam('amount', 'The amount of tokens to send', undefined, types.bigint)
    .addParam('fromEid', 'The source endpoint ID', undefined, types.eid)
    .addParam('to', 'The recipient address on the destination chain')
    .addParam('toEid', 'The destination endpoint ID', undefined, types.eid)
    .addParam('mint', 'The OFT token mint public key', undefined, types.string)
    .addParam('programId', 'The OFT program ID', undefined, types.string)
    .addParam('escrow', 'The OFT escrow public key', undefined, types.string)
    .addParam('tokenProgram', 'The Token Program public key', TOKEN_PROGRAM_ID.toBase58(), types.string, true)
    .addParam('computeUnitPriceScaleFactor', 'The compute unit price scale factor', 4, types.float, true)
    .setAction(
        async ({
            amount,
            fromEid,
            to,
            toEid,
            mint: mintStr,
            programId: programIdStr,
            escrow: escrowStr,
            tokenProgram: tokenProgramStr,
            computeUnitPriceScaleFactor,
        }: Args) => {
            const { connection, umi, umiWalletSigner } = await deriveConnection(fromEid)

            if (!process.env.GOVERNANCE_PROGRAM_ID) {
                throw new Error('GOVERNANCE_PROGRAM_ID is not defined in the environment variables.')
            }

            const governanceProgramId = new PublicKey(process.env.GOVERNANCE_PROGRAM_ID)
            const governance = new Governance(governanceProgramId, 0)
            const governanceOAppAddress = governance.idPDA()[0];
            const oftProgramId = publicKey(programIdStr)
            const mint = publicKey(mintStr)
            const umiEscrowPublicKey = publicKey(escrowStr)
            const tokenProgramId = tokenProgramStr ? publicKey(tokenProgramStr) : fromWeb3JsPublicKey(TOKEN_PROGRAM_ID)
            const signer = toWeb3JsKeypair(umiWalletSigner)

            const signerATA = findAssociatedTokenPda(umi, {
                mint: publicKey(mintStr),
                owner: umiWalletSigner.publicKey,
                tokenProgramId,
            })
            const signerATAAddress = signerATA[0]

            const governanceATA = findAssociatedTokenPda(umi, {
                mint: publicKey(mintStr),
                owner: publicKey(governanceOAppAddress),
                tokenProgramId,
            });
            const governanceATAAddress = governanceATA[0]

            console.log('destination_token_account', signerATA)
            console.log('governance_ata', governanceATA)

            if (!signerATA) {
                throw new Error(
                    `No token account found for mint ${mintStr} and owner ${umiWalletSigner.publicKey} in program ${tokenProgramId}`
                )
            }

            const governanceTokenAccountData = await fetchToken(umi, governanceATA)
            const governanceBalance = governanceTokenAccountData.amount

            if (amount == BigInt(0) || amount > governanceBalance) {
                throw new Error(
                    `Attempting to send ${amount}, but ${governanceOAppAddress} (Governance) only has balance of ${governanceBalance}`
                )
            }

            const lookupTableAddress = "GvbvNTqJgRKn8diHeY2S3c3xLAGNZW2gUqycwdoKRWqe";
            const lookupTableAccount = await fetchAddressLookupTable(umi, publicKey(lookupTableAddress))
        
            if (!lookupTableAccount) {
                throw new Error("Lookup table account not found");
            }

            const recipientAddressBytes32 = addressToBytes32(to)

            const { nativeFee } = await oft.quote(
                umi.rpc,
                {
                    payer: umiWalletSigner.publicKey,
                    tokenMint: mint,
                    tokenEscrow: umiEscrowPublicKey,
                },
                {
                    payInLzToken: false,
                    to: Buffer.from(recipientAddressBytes32),
                    dstEid: toEid,
                    amountLd: BigInt(amount),
                    minAmountLd: 1n,
                    options: Buffer.from(''),
                    composeMsg: undefined,
                },
                {
                    oft: oftProgramId,
                }
            )

            const governanceOftSendIx = await governance.sendOFT(
                connection,
                signer.publicKey,
                toWeb3JsPublicKey(governanceATAAddress),
                toWeb3JsPublicKey(signerATAAddress),
                toWeb3JsPublicKey(mint),
                new PublicKey('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'),
                Number(amount)
            );

            const oftSendIx = await oft.send(
                umi.rpc,
                {
                    payer: umiWalletSigner,
                    tokenMint: mint,
                    tokenEscrow: umiEscrowPublicKey,
                    tokenSource: signerATA[0],
                },
                {
                    to: Buffer.from(recipientAddressBytes32),
                    dstEid: toEid,
                    amountLd: BigInt(amount),
                    minAmountLd: (BigInt(amount) * BigInt(9)) / BigInt(10),
                    options: Buffer.from(''),
                    composeMsg: undefined,
                    nativeFee,
                },
                {
                    oft: oftProgramId,
                    token: tokenProgramId,
                }
            )

            const governanceOftSendIxUmi = fromWeb3JsInstruction(governanceOftSendIx);
            const wrappedIx = {
                instruction: governanceOftSendIxUmi,
                signers: [],
                bytesCreatedOnChain: 0
            }

            let txBuilder = transactionBuilder().add([
                wrappedIx,
                oftSendIx
            ]);

            // // Serialize the Transaction
            // const serializedCreateAssetTx = umi.transactions.serialize(tx)

            // // Encode Uint8Array to String and Return the Transaction to the Frontend
            // const serializedCreateAssetTxAsString = base64.deserialize(serializedCreateAssetTx)[0];

            // console.log({ serializedCreateAssetTxAsString })
            
            const { signature } = await txBuilder.setAddressLookupTables([lookupTableAccount]).sendAndConfirm(umi)
            const transactionSignatureBase58 = bs58.encode(signature)

            console.log(`✅ Sent ${amount} token(s) to destination EID: ${toEid}!`)
            const isTestnet = fromEid == EndpointId.SOLANA_V2_TESTNET
            console.log(
                `View Solana transaction here: ${getExplorerTxLink(transactionSignatureBase58.toString(), isTestnet)}`
            )
            console.log(
                `Track cross-chain transfer here: ${getLayerZeroScanLink(transactionSignatureBase58, isTestnet)}`
            )
        }
    )
