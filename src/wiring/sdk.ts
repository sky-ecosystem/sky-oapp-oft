import { mplToolbox } from '@metaplex-foundation/mpl-toolbox'
import {
    Signer,
    TransactionBuilder,
    Umi,
    type PublicKey as UmiPublicKey,
    WrappedInstruction,
    createNoopSigner,
    publicKey,
} from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { fromWeb3JsPublicKey, toWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { Connection, PublicKey, Transaction, TransactionInstruction } from '@solana/web3.js'

import { AsyncRetriable, mapError } from '@layerzerolabs/devtools'
import {
    Bytes,
    type OmniAddress,
    OmniPoint,
    type OmniTransaction,
    areBytes32Equal,
    denormalizePeer,
    formatEid,
    fromHex,
    makeBytes32,
    normalizePeer,
} from '@layerzerolabs/devtools'
import { OmniSDK } from '@layerzerolabs/devtools-solana'
import { type Logger, printBoolean, printJson } from '@layerzerolabs/io-devtools'
import { EndpointProgram, MessageLibPDADeriver, UlnProgram } from '@layerzerolabs/lz-solana-sdk-v2'
import { EndpointV2 } from '@layerzerolabs/protocol-devtools-solana'

import { myoapp } from './client'

import type { EndpointId } from '@layerzerolabs/lz-definitions'
import type { IOApp, OAppEnforcedOptionParam } from '@layerzerolabs/ua-devtools'
import { Governance } from '../governance'

export class CustomOAppSDK extends OmniSDK implements IOApp {
    protected readonly umi: Umi
    protected readonly umiUserAccount: UmiPublicKey
    protected readonly umiProgramId: UmiPublicKey
    protected readonly umiPublicKey: UmiPublicKey
    protected readonly umiMyOAppSdk: myoapp.MyOApp
    protected readonly governance: Governance;

    constructor(
        connection: Connection,
        point: OmniPoint,
        userAccount: PublicKey,
        public readonly programId: PublicKey,
        logger?: Logger
    ) {
        super(connection, point, userAccount, logger)
        // cache Umi-specific objects for reuse
        this.umi = createUmi(connection.rpcEndpoint).use(mplToolbox())
        this.umiUserAccount = fromWeb3JsPublicKey(userAccount)
        this.umiProgramId = fromWeb3JsPublicKey(this.programId)
        this.umiPublicKey = fromWeb3JsPublicKey(this.publicKey)
        this.umiMyOAppSdk = new myoapp.MyOApp(fromWeb3JsPublicKey(this.programId))

        const endpointProgram = new EndpointProgram.Endpoint(new PublicKey('76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6'))

        this.governance = new Governance(this.programId, endpointProgram)
    }

    @AsyncRetriable()
    async getOwner(): Promise<OmniAddress> {
        this.logger.debug(`Getting owner`)

        const config = await mapError(
            () => {
                return myoapp.accounts.Governance.fromAccountAddress(this.connection, toWeb3JsPublicKey(this.umiPublicKey))
            },
            (error) => new Error(`Failed to get owner for ${this.label}: ${error}`)
        )

        const owner = config.admin.toBase58()
        return this.logger.debug(`Got owner: ${owner}`), owner
    }

    async hasOwner(address: OmniAddress): Promise<boolean> {
        this.logger.debug(`Checking whether ${address} is an owner`)

        const owner = await this.getOwner()
        const isOwner = areBytes32Equal(normalizePeer(address, this.point.eid), normalizePeer(owner, this.point.eid))

        return this.logger.debug(`Checked whether ${address} is an owner (${owner}): ${printBoolean(isOwner)}`), isOwner
    }

    async setOwner(address: OmniAddress): Promise<OmniTransaction> {
        this.logger.debug(`Setting owner to ${address}`)

        const admin = toWeb3JsPublicKey((await this._getAdmin()).publicKey)
        const setAdminIx = this.governance.setAdmin(admin, new PublicKey(address))
        const web3Transaction = new Transaction()
        web3Transaction.add(setAdminIx)
        
        return {
            ...(await this.createTransaction(web3Transaction)),
            description: `Setting owner to ${address}`,
        }
    }

    @AsyncRetriable()
    async getEndpointSDK(): Promise<EndpointV2> {
        this.logger.debug(`Getting EndpointV2 SDK`)

        return new EndpointV2(
            this.connection,
            { eid: this.point.eid, address: EndpointProgram.PROGRAM_ID.toBase58() },
            this.userAccount
        )
    }

    @AsyncRetriable()
    async getPeer(eid: EndpointId): Promise<OmniAddress | undefined> {
        const eidLabel = `eid ${eid} (${formatEid(eid)})`

        this.logger.debug(`Getting peer for ${eidLabel}`)
        try {
            const peer = await myoapp.getPeer(this.umi.rpc, eid, this.umiProgramId)
            // We run the hex string we got through a normalization/de-normalization process
            // that will ensure that zero addresses will get stripped
            // and any network-specific logic will be applied
            return denormalizePeer(fromHex(peer), eid)
        } catch (error) {
            if (String(error).match(/Unable to find Remote account at/i)) {
                return undefined
            }

            throw new Error(`Failed to get peer for ${eidLabel} for OFT ${this.label}: ${error}`)
        }
    }

    async hasPeer(eid: EndpointId, address: OmniAddress | null | undefined): Promise<boolean> {
        const peer = await this.getPeer(eid)
        return areBytes32Equal(normalizePeer(peer, eid), normalizePeer(address, eid))
    }

    async setPeer(eid: EndpointId, address: OmniAddress | null | undefined): Promise<OmniTransaction> {
        const eidLabel = formatEid(eid)
        // We use the `mapError` and pretend `normalizePeer` is async to avoid having a let and a try/catch block
        const normalizedPeer = await mapError(
            async () => normalizePeer(address, eid),
            (error) =>
                new Error(`Failed to convert peer ${address} for ${eidLabel} for ${this.label} to bytes: ${error}`)
        )
        const peerAsBytes32 = makeBytes32(normalizedPeer)
        const delegate = await this.safeGetDelegate()

        const oapp = this.umiPublicKey

        this.logger.debug(`Setting peer for eid ${eid} (${eidLabel}) to address ${peerAsBytes32}`)
        const admin = toWeb3JsPublicKey((await this._getAdmin()).publicKey)
        const umiTxs = [
            myoapp.initOAppNonce({ admin: delegate, oapp }, eid, normalizedPeer), // delegate
        ]

        const isSendLibraryInitialized = await this.isSendLibraryInitialized(eid)
        const isReceiveLibraryInitialized = await this.isReceiveLibraryInitialized(eid)

        if (!isSendLibraryInitialized) {
            umiTxs.push(myoapp.initSendLibrary({ admin: delegate, oapp }, eid))
        }

        if (!isReceiveLibraryInitialized) {
            umiTxs.push(myoapp.initReceiveLibrary({ admin: delegate, oapp }, eid))
        }

        const web3Transaction = new Transaction()
        web3Transaction.add(this.governance.setRemote(admin, normalizedPeer, eid)); // admin
        this._umiToWeb3Tx(umiTxs).instructions.map((ix) => {
            web3Transaction.add(ix)
        })

        return {
            ...(await this.createTransaction(web3Transaction)),
            description: `Setting peer for eid ${eid} (${eidLabel}) to address ${peerAsBytes32} ${delegate.publicKey} ${(await this._getAdmin()).publicKey}`,
        }
    }

    @AsyncRetriable()
    async getDelegate(): Promise<OmniAddress | undefined> {
        this.logger.debug(`Getting delegate`)

        const endpointSdk = await this.getEndpointSDK()
        const delegate = await endpointSdk.getDelegate(this.point.address)

        return this.logger.verbose(`Got delegate: ${delegate}`), delegate
    }

    @AsyncRetriable()
    async isDelegate(delegate: OmniAddress): Promise<boolean> {
        this.logger.debug(`Checking whether ${delegate} is a delegate`)

        const endpointSdk = await this.getEndpointSDK()
        const isDelegate = await endpointSdk.isDelegate(this.point.address, delegate)

        return this.logger.verbose(`Checked delegate: ${delegate}: ${printBoolean(isDelegate)}`), isDelegate
    }

    async setDelegate(delegate: OmniAddress): Promise<OmniTransaction> {
        this.logger.debug(`Setting delegate to ${delegate}`)

        const admin = toWeb3JsPublicKey((await this._getAdmin()).publicKey)
        const setDelegateIx = this.governance.setDelegate(admin, new PublicKey(delegate))
        const web3Transaction = new Transaction()
        web3Transaction.add(setDelegateIx)
        return {
            ...(await this.createTransaction(web3Transaction)),
            description: `Setting delegate to ${delegate}`,
        }
    }

    @AsyncRetriable()
    async getEnforcedOptions(eid: EndpointId, msgType: number): Promise<Bytes> {
       throw new Error('Governance OApp on Solana does not support getting enforced options')
    }

    async setEnforcedOptions(enforcedOptions: OAppEnforcedOptionParam[]): Promise<OmniTransaction> {
        this.logger.verbose(`Setting enforced options to ${printJson(enforcedOptions)}`)
        throw new Error('Governance OApp on Solana does not support setting enforced options')
    }

    async isSendLibraryInitialized(eid: EndpointId): Promise<boolean> {
        const endpointSdk = await this.getEndpointSDK()
        return endpointSdk.isSendLibraryInitialized(this.point.address, eid)
    }

    async initializeSendLibrary(eid: EndpointId): Promise<[OmniTransaction] | []> {
        this.logger.verbose(`Initializing send library on ${formatEid(eid)}`)

        const endpointSdk = await this.getEndpointSDK()
        return endpointSdk.initializeSendLibrary(this.point.address, eid)
    }

    async isReceiveLibraryInitialized(eid: EndpointId): Promise<boolean> {
        const endpointSdk = await this.getEndpointSDK()
        return endpointSdk.isReceiveLibraryInitialized(this.point.address, eid)
    }

    async initializeReceiveLibrary(eid: EndpointId): Promise<[OmniTransaction] | []> {
        this.logger.verbose(`Initializing receive library on ${formatEid(eid)}`)

        const endpointSdk = await this.getEndpointSDK()
        return endpointSdk.initializeReceiveLibrary(this.point.address, eid)
    }

    async isOAppConfigInitialized(eid: EndpointId): Promise<boolean> {
        const endpointSdk = await this.getEndpointSDK()
        return endpointSdk.isOAppConfigInitialized(this.point.address, eid)
    }

    async initializeOAppConfig(eid: EndpointId, lib: OmniAddress | null | undefined): Promise<[OmniTransaction] | []> {
        this.logger.verbose(`Initializing OApp config for library ${lib} on ${formatEid(eid)}`)

        const endpointSdk = await this.getEndpointSDK()
        return endpointSdk.initializeOAppConfig(this.point.address, eid, lib ?? undefined)
    }

    async setCallerBpsCap(callerBpsCap: bigint): Promise<OmniTransaction | undefined> {
        this.logger.debug(`Setting caller BPS cap to ${callerBpsCap}`)

        throw new TypeError(`setCallerBpsCap() not implemented on Solana OFT SDK`)
    }

    @AsyncRetriable()
    async getCallerBpsCap(): Promise<bigint | undefined> {
        this.logger.debug(`Getting caller BPS cap`)

        throw new TypeError(`getCallerBpsCap() not implemented on Solana OFT SDK`)
    }

    public async sendConfigIsInitialized(_eid: EndpointId): Promise<boolean> {
        const deriver = new MessageLibPDADeriver(UlnProgram.PROGRAM_ID)
        const [sendConfig] = deriver.sendConfig(_eid, new PublicKey(this.point.address))
        const accountInfo = await this.connection.getAccountInfo(sendConfig)
        return accountInfo != null
    }

    public async initConfig(eid: EndpointId): Promise<OmniTransaction | undefined> {
        const delegateAddress = await this.getDelegate()
        // delegate may be undefined if it has not yet been set.  In this case, use admin, which must exist.
        const delegate = delegateAddress ? createNoopSigner(publicKey(delegateAddress)) : await this._getAdmin()
        return {
            ...(await this.createTransaction(
                this._umiToWeb3Tx([
                    myoapp.initConfig(
                        this.umiProgramId,
                        {
                            admin: delegate,
                            payer: delegate,
                        },
                        eid,
                        {
                            msgLib: fromWeb3JsPublicKey(UlnProgram.PROGRAM_ID),
                        }
                    ),
                ])
            )),
            description: `oapp.initConfig(${eid})`,
        }
    }

    // Convert Umi instructions to Web3JS Transaction
    protected _umiToWeb3Tx(ixs: WrappedInstruction[]): Transaction {
        const web3Transaction = new Transaction()
        const txBuilder = new TransactionBuilder(ixs)
        txBuilder.getInstructions().forEach((umiInstruction) => {
            const web3Instruction = new TransactionInstruction({
                programId: new PublicKey(umiInstruction.programId),
                keys: umiInstruction.keys.map((key) => ({
                    pubkey: new PublicKey(key.pubkey),
                    isSigner: key.isSigner,
                    isWritable: key.isWritable,
                })),
                data: Buffer.from(umiInstruction.data),
            })

            // Add the instruction to the Web3.js transaction
            web3Transaction.add(web3Instruction)
        })
        return web3Transaction
    }

    protected async safeGetDelegate() {
        const delegateAddress = await this.getDelegate()
        if (!delegateAddress) {
            throw new Error('No delegate found')
        }
        return createNoopSigner(publicKey(delegateAddress))
    }

    protected async _getAdmin(): Promise<Signer> {
        const owner = await this.getOwner()
        return createNoopSigner(publicKey(owner))
    }
}
