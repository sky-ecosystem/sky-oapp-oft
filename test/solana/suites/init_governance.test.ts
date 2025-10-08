import { describe, it, before } from 'mocha'
import { Context, sol, Umi } from '@metaplex-foundation/umi'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { getGlobalContext, getGlobalUmi } from '../index.test'
import { DST_EID, SRC_EID, uln, endpoint } from '../constants'
import { PacketSentEvent, TestContext } from '../types'
import assert from 'assert'
import fs from "fs";
import * as anchor from "@coral-xyz/anchor";
import {
  Connection,
  PublicKey,
  sendAndConfirmTransaction,
  SendTransactionError,
  SystemProgram,
  Transaction,
} from "@solana/web3.js";
import { Governance } from "../../../target/types/governance";
import { GovernancePDADeriver } from "../../../src/governance-pda-deriver";
import { EndpointProgram, EventPDADeriver } from "@layerzerolabs/lz-solana-sdk-v2";
import { verifyAndReceive } from '../utils'
import { Packet, PacketSerializer } from '@layerzerolabs/lz-v2-utilities'
import { getLogs } from '@solana-developers/helpers'

const deployerSecretKey = fs.readFileSync(`${__dirname}/../../../junk-id.json`, {
  encoding: "utf-8",
});

const deployer = anchor.web3.Keypair.fromSecretKey(Uint8Array.from(JSON.parse(deployerSecretKey)));
const notDeployer = anchor.web3.Keypair.generate();

const ENDPOINT_PROGRAM_ID = EndpointProgram.PROGRAM_ID

const governance = anchor.workspace
  .Governance as anchor.Program<Governance>;

const endpointSDK = new EndpointProgram.Endpoint(ENDPOINT_PROGRAM_ID);

const dummyEid = 40106;
const dummyRemote: Uint8Array = Uint8Array.from(Buffer.from('000000000000000000000000c4116303c13512dd1ff416d3a48ebec2f091a5e6', 'hex'));

const deriver = new GovernancePDADeriver(governance.programId);
const governancePDA = deriver.governance();
const lzReceiveTypesV2AccountsPDA = deriver.lzReceiveTypesInfoAccounts();
const remotePDA = deriver.remote(dummyEid);

const bpfProgramAddress = new PublicKey("BPFLoaderUpgradeab1e11111111111111111111111");
const seeds = [Buffer.from(governance.programId.toBytes())];
const [governanceProgramData,] = PublicKey.findProgramAddressSync(
    seeds,
    bpfProgramAddress
);
const [oAppRegistry] = endpointSDK.deriver.oappRegistry(governancePDA[0])
const [eventAuthority] = new EventPDADeriver(ENDPOINT_PROGRAM_ID).eventAuthority()

async function getProgramAuthority(c: Connection, programId: PublicKey): Promise<PublicKey> {
  const info = await c.getAccountInfo(programId)
  if (!info) {
    throw new Error('Program not found')
  }
  const dataAddress = new PublicKey(info.data.subarray(4))

  const dataAcc = await c.getAccountInfo(dataAddress)
  if (!dataAcc) {
    throw new Error('Data account not found')
  }
  return new PublicKey(dataAcc.data.subarray(13, 45))
}

describe('🏗️ Governance', function () {
    this.timeout(300000) // 5 minutes timeout

    let context: TestContext
    let umi: Umi | Context

    before(async function () {
        context = getGlobalContext()
        umi = getGlobalUmi()
        await umi.rpc.airdrop(fromWeb3JsPublicKey(notDeployer.publicKey), sol(30))
    })

    it("not a program upgrade authority can't initialize governance", async () => {
        const programAuthority = await getProgramAuthority(context.connection, governance.programId);
        assert.notEqual(programAuthority.toBase58(), notDeployer.publicKey.toBase58());
    
        const initializeGovernanceIx = await governance.methods
            .initGovernance({
                id: new anchor.BN(0),
                admin: notDeployer.publicKey,
                lzReceiveAlts: [],
            })
            .accountsStrict({
                payer: notDeployer.publicKey,
                governance: governancePDA[0],
                lzReceiveTypesV2Accounts: lzReceiveTypesV2AccountsPDA[0],
                governanceProgram: governance.programId,
                governanceProgramData,
                systemProgram: SystemProgram.programId,
            })
            .instruction();
    
        const transaction = new Transaction().add(
            initializeGovernanceIx
        );
        
        try {
            await sendAndConfirmTransaction(context.connection, transaction, [notDeployer])
            assert.ok(false);
        } catch (err: unknown) {
            assert.ok(err instanceof SendTransactionError, "error is not a SendTransactionError");
            const anchorError = anchor.AnchorError.parse((err as SendTransactionError).logs || [])
            assert.notEqual(anchorError, null, "anchor error is null");
            assert.strictEqual(anchorError?.error.errorMessage, 'NotUpgradeAuthority', "anchor error message is not 'NotUpgradeAuthority'");
        }
        });

    it("program upgrade authority can initialize governance", async () => {
        const programAuthority = await getProgramAuthority(context.connection, governance.programId);
        assert.equal(programAuthority.toBase58(), deployer.publicKey.toBase58(), "program upgrade authority is not the deployer");

        await umi.rpc.airdrop(fromWeb3JsPublicKey(deployer.publicKey), sol(10000))
    
        const ixAccounts = EndpointProgram.instructions.createRegisterOappInstructionAccounts(
            {
                payer: deployer.publicKey,
                oapp: governancePDA[0],
                oappRegistry: oAppRegistry,
                eventAuthority,
                program: ENDPOINT_PROGRAM_ID,
            },
            ENDPOINT_PROGRAM_ID
        )
        const registerOAppAccounts = [
            {
                pubkey: ENDPOINT_PROGRAM_ID,
                isSigner: false,
                isWritable: false,
            },
            ...ixAccounts,
        ];
    
        // the first two accounts are both signers, so we need to set them to false, Solana will set them to signer internally
        registerOAppAccounts[1].isSigner = false
        registerOAppAccounts[2].isSigner = false
    
        const initializeGovernanceIx = await governance.methods
            .initGovernance({
                id: new anchor.BN(0),
                admin: deployer.publicKey,
                lzReceiveAlts: [],
            })
            .accountsStrict({
                payer: deployer.publicKey,
                governance: governancePDA[0],
                lzReceiveTypesV2Accounts: lzReceiveTypesV2AccountsPDA[0],
                governanceProgram: governance.programId,
                governanceProgramData,
                systemProgram: SystemProgram.programId,
            })
            .remainingAccounts(registerOAppAccounts)
            .instruction();
    
        const transaction = new Transaction().add(
            initializeGovernanceIx
        );
    
        await sendAndConfirmTransaction(context.connection, transaction, [deployer])
    
        const governanceAccount = await governance.account.governance.fetch(governancePDA[0]);
        assert.notEqual(governanceAccount, null);
        assert.strictEqual(governanceAccount.id.toNumber(), 0);
        assert.strictEqual(governanceAccount.admin.toBase58(), deployer.publicKey.toBase58());
        });

        it("configures oapp", async () => {
        const oapp = governancePDA[0]
        const transaction = new Transaction().add(
            endpoint.initSendLibrary(deployer.publicKey, oapp, DST_EID),
            endpoint.setSendLibrary(deployer.publicKey, oapp, uln.program, DST_EID),
            endpoint.initReceiveLibrary(deployer.publicKey, oapp, SRC_EID),
            endpoint.setReceiveLibrary(deployer.publicKey, oapp, uln.program, SRC_EID),
            endpoint.initOAppNonce(deployer.publicKey, SRC_EID, oapp, dummyRemote),
            endpoint.initOAppNonce(deployer.publicKey, DST_EID, oapp, dummyRemote),
            );
        
            await sendAndConfirmTransaction(context.connection, transaction, [deployer])
        })

        it("configures remote", async () => {
        const transaction = new Transaction().add(
            await governance.methods.setRemote({
                remoteEid: dummyEid,
                remote: Array.from(dummyRemote),
            })
            .accountsStrict({
                admin: deployer.publicKey,
                remote: remotePDA[0],
                governance: governancePDA[0],
                systemProgram: SystemProgram.programId,
            })
            .instruction()
        );
        
        await sendAndConfirmTransaction(context.connection, transaction, [deployer])
    
        const remoteAccount = await governance.account.remote.fetch(remotePDA[0]);
        assert.notEqual(remoteAccount, null);
        assert.strictEqual(remoteAccount.address.toString(), dummyRemote.toString());
    });

    it('configures delegate', async () => {
        const ixAccounts = EndpointProgram.instructions.createSetDelegateInstructionAccounts({
            oapp: governancePDA[0],
            oappRegistry: oAppRegistry,
            eventAuthority,
            program: ENDPOINT_PROGRAM_ID,
            }, ENDPOINT_PROGRAM_ID)
    
            ixAccounts[0].isSigner = false
    
        const ix = await governance.methods
            .setOappConfig({
                delegate: [notDeployer.publicKey],
            })
            .accountsStrict({
                admin: deployer.publicKey,
                governance: governancePDA[0],
                lzReceiveTypesAccounts: lzReceiveTypesV2AccountsPDA[0],
            })
            .remainingAccounts([
                {
                pubkey: ENDPOINT_PROGRAM_ID,
                isSigner: false,
                isWritable: false,
                },
                ...ixAccounts
            ])
            .instruction();
    
        const transaction = new Transaction().add(
            ix
        );
            
        await sendAndConfirmTransaction(context.connection, transaction, [deployer])
    });

    it('executes hello world governance message', async () => {
        const packet: Packet = {
            version: 1,
            nonce: '1',
            guid: '0xa9767b00b96f4eaa338a6a103ca9fd0b3281cfc6de6ec4a74756f3c7aba16f42',
            srcEid: SRC_EID,
            sender: '0x000000000000000000000000c4116303c13512dd1ff416d3a48ebec2f091a5e6',
            dstEid: DST_EID,
            receiver: fromWeb3JsPublicKey(governancePDA[0]),
            payload: '0x0000000000000000000000000804a6e2798f42c7f3c97215ddf958d5500f8ec82c43318f0f99dfd8c0ebc65b0b23cc661fcd1df64af6aef33b7b83eca8e581970000afaf6d1f0d989bed',
            message: '0x0000000000000000000000000804a6e2798f42c7f3c97215ddf958d5500f8ec82c43318f0f99dfd8c0ebc65b0b23cc661fcd1df64af6aef33b7b83eca8e581970000afaf6d1f0d989bed',
        }
        const encodedPacket = PacketSerializer.serializeBytes(packet);
        const packetSentEvent: PacketSentEvent = {
            encodedPacket,
            options: new Uint8Array(32).fill(0),
            sendLibrary: fromWeb3JsPublicKey(uln.program),
        };
        const signature = await verifyAndReceive(context, dummyRemote, fromWeb3JsPublicKey(governancePDA[0]), packetSentEvent);

        const logs = await getLogs(context.connection, signature);

        assert.ok(logs.some(l => l.includes('Greetings from: 3ynNB373Q3VAzKp7m4x238po36hjAGFXFJB4ybN2iTyg')));
    });
})