import {
    AccountMeta,
    Commitment,
    Connection,
    GetAccountInfoConfig,
    PublicKey,
    TransactionInstruction,
} from '@solana/web3.js'

import { buildVersionedTransaction, EndpointProgram, EventPDADeriver, SimpleMessageLibProgram, UlnProgram } from '@layerzerolabs/lz-solana-sdk-v2'

import * as accounts from './generated/governance/accounts'
import * as instructions from './generated/governance/instructions'
import * as types from './generated/governance/types'
import { GovernancePDADeriver } from './governance-pda-deriver'
import { LzReceiveTypesInfoResult, lzReceiveTypesInfoResultBeet } from './types'

export { accounts, instructions, types }

export class Governance {
    governanceDeriver: GovernancePDADeriver
    endpoint: EndpointProgram.Endpoint | undefined

    constructor(
        public readonly program: PublicKey,
        public governanceId = 0
    ) {
        this.governanceDeriver = new GovernancePDADeriver(program, governanceId)
    }

    idPDA(): [PublicKey, number] {
        return this.governanceDeriver.governance()
    }

    async initGovernance(
        connection: Connection,
        payer: PublicKey,
        admin: PublicKey,
        endpoint: EndpointProgram.Endpoint,
        lzReceiveAlts: PublicKey[] = [],
        commitmentOrConfig: Commitment | GetAccountInfoConfig = 'confirmed'
    ): Promise<TransactionInstruction | null> {
        const [id] = this.idPDA()
        const [oAppRegistry] = endpoint.deriver.oappRegistry(id)
        const info = await connection.getAccountInfo(id, commitmentOrConfig)
        if (info) {
            return null
        }

        const [eventAuthority] = new EventPDADeriver(endpoint.program).eventAuthority()
        const ixAccounts = EndpointProgram.instructions.createRegisterOappInstructionAccounts(
            {
                payer: payer,
                oapp: this.idPDA()[0],
                oappRegistry: oAppRegistry,
                eventAuthority,
                program: endpoint.program,
            },
            endpoint.program
        )
        // these accounts are used for the CPI, so we need to set them to false
        const registerOAppAccounts = [
            {
                pubkey: endpoint.program,
                isSigner: false,
                isWritable: false,
            },
            ...ixAccounts,
        ]
        // the first two accounts are both signers, so we need to set them to false, solana will set them to signer internally
        registerOAppAccounts[1].isSigner = false
        registerOAppAccounts[2].isSigner = false
        return instructions.createInitGovernanceInstruction(
            {
                payer,
                governance: id,
                lzReceiveTypesV2Accounts: this.governanceDeriver.lzReceiveTypesInfoAccounts()[0],
                anchorRemainingAccounts: registerOAppAccounts,
            } satisfies instructions.InitGovernanceInstructionAccounts,
            {
                params: {
                    id: this.governanceId,
                    admin,
                    endpoint: endpoint.program,
                    lzReceiveAlts,
                } satisfies types.InitGovernanceParams,
            } satisfies instructions.InitGovernanceInstructionArgs,
            this.program
        )
    }

    async getRemote(
        connection: Connection,
        dstEid: number,
        commitmentOrConfig?: Commitment | GetAccountInfoConfig
    ): Promise<Uint8Array | null> {
        const [remotePDA] = this.governanceDeriver.remote(dstEid)
        const info = await connection.getAccountInfo(remotePDA, commitmentOrConfig)
        if (info) {
            const remote = await accounts.Remote.fromAccountAddress(connection, remotePDA, commitmentOrConfig)
            return Uint8Array.from(remote.address)
        }
        return null
    }

    setRemote(admin: PublicKey, dstAddress: Uint8Array, dstEid: number): TransactionInstruction {
        const [remotePDA] = this.governanceDeriver.remote(dstEid)
        return instructions.createSetRemoteInstruction(
            {
                admin,
                governance: this.idPDA()[0],
                remote: remotePDA,
            } satisfies instructions.SetRemoteInstructionAccounts,
            {
                params: {
                    dstEid,
                    remote: Array.from(dstAddress),
                } satisfies types.SetRemoteParams,
            },
            this.program
        )
    }

    setLzReceiveTypesAccounts(admin: PublicKey, lzReceiveAlts: PublicKey[]): TransactionInstruction {
        const [lzReceiveTypesInfoAccountsPDA] = this.governanceDeriver.lzReceiveTypesInfoAccounts()
        return instructions.createSetOappConfigInstruction(
            {
                admin,
                governance: this.idPDA()[0],
                lzReceiveTypesAccount: lzReceiveTypesInfoAccountsPDA,
            } satisfies instructions.SetOappConfigInstructionAccounts,
            {
                params: {
                    __kind: 'LzReceiveAlts',
                    fields: [lzReceiveAlts],
                } satisfies types.SetOAppConfigParams,
            },
            this.program
        )
    }

    async getLzReceiveTypesInfo(connection: Connection, commitmentOrConfig: Commitment | GetAccountInfoConfig = 'confirmed'): Promise<[number, LzReceiveTypesInfoResult]> {
        const [lzReceiveTypesInfoAccountsPDA] = this.governanceDeriver.lzReceiveTypesInfoAccounts()
        const ix = instructions.createLzReceiveTypesInfoInstruction(
            {
                governance: this.idPDA()[0],
                lzReceiveTypesAccount: lzReceiveTypesInfoAccountsPDA,
            } satisfies instructions.LzReceiveTypesInfoInstructionAccounts,
            this.program
        )

        const { blockhash } = await connection.getLatestBlockhash();
        const dummyPayer = new PublicKey('Fty7h4FYAN7z8yjqaJExMHXbUoJYMcRjWYmggSxLbHp8');
        const tx = await buildVersionedTransaction(connection, dummyPayer, [ix], commitmentOrConfig, blockhash)

        const simulation = await connection.simulateTransaction(tx, {
            sigVerify: false
        })

        const dataRaw = simulation.value.returnData?.data[0];
        if (!dataRaw) {
            throw new Error('No data returned')
        }
        const data = Buffer.from(dataRaw, 'base64');
        const version = data.readUInt8(0);

        return [version, lzReceiveTypesInfoResultBeet.deserialize(data, 1)[0]];
    }

    async getLzReceiveTypesV2(connection: Connection, params: types.LzReceiveParams, accounts: PublicKey[], commitmentOrConfig: Commitment | GetAccountInfoConfig = 'confirmed'): Promise<types.LzReceiveTypesV2Result> {
        const keys: AccountMeta[] = accounts.map(account => ({
            pubkey: account,
            isSigner: false,
            isWritable: false,
        }))

        const ix = instructions.createLzReceiveTypesV2Instruction(
            {
                governance: keys[0].pubkey,
                anchorRemainingAccounts: keys.slice(1),
            } satisfies instructions.LzReceiveTypesV2InstructionAccounts,
            {
                params,
            } satisfies instructions.LzReceiveTypesV2InstructionArgs,
            this.program
        )

        const { blockhash } = await connection.getLatestBlockhash();
        const dummyPayer = new PublicKey('Fty7h4FYAN7z8yjqaJExMHXbUoJYMcRjWYmggSxLbHp8');
        const tx = await buildVersionedTransaction(connection, dummyPayer, [ix], commitmentOrConfig, blockhash)

        const simulation = await connection.simulateTransaction(tx, {
            sigVerify: false
        })

        const dataRaw = simulation.value.returnData?.data[0];
        if (!dataRaw) {
            throw new Error('No data returned')
        }

        const data = Buffer.from(dataRaw, 'base64');

        return types.lzReceiveTypesV2ResultBeet.deserialize(data, 0)[0];
    }

    async getEndpoint(connection: Connection): Promise<EndpointProgram.Endpoint> {
        if (this.endpoint) {
            return this.endpoint
        }
        const [id] = this.governanceDeriver.governance()
        const info = await accounts.Governance.fromAccountAddress(connection, id)
        const programAddr = info.endpointProgram
        const endpoint = new EndpointProgram.Endpoint(programAddr)
        this.endpoint = endpoint
        return endpoint
    }

    async getSendLibraryProgram(
        connection: Connection,
        payer: PublicKey,
        dstEid: number,
        endpoint?: EndpointProgram.Endpoint
    ): Promise<SimpleMessageLibProgram.SimpleMessageLib | UlnProgram.Uln> {
        if (!endpoint) {
            endpoint = await this.getEndpoint(connection)
        }
        const [id] = this.idPDA()
        const sendLibInfo = await endpoint.getSendLibrary(connection, id, dstEid)
        if (!sendLibInfo?.programId) {
            throw new Error('Send library not initialized or blocked message library')
        }
        const { programId: msgLibProgram } = sendLibInfo
        const msgLibVersion = await endpoint.getMessageLibVersion(connection, payer, msgLibProgram)
        if (msgLibVersion?.major.toString() === '0' && msgLibVersion.minor == 0 && msgLibVersion.endpointVersion == 2) {
            return new SimpleMessageLibProgram.SimpleMessageLib(msgLibProgram)
        } else if (
            msgLibVersion?.major.toString() === '3' &&
            msgLibVersion.minor == 0 &&
            msgLibVersion.endpointVersion == 2
        ) {
            return new UlnProgram.Uln(msgLibProgram)
        }

        throw new Error(`Unsupported message library version: ${JSON.stringify(msgLibVersion, null, 2)}`)
    }
}
