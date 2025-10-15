import { describe, it, before } from 'mocha'
import { Context, sol, Umi } from '@metaplex-foundation/umi'
import { fromWeb3JsPublicKey } from '@metaplex-foundation/umi-web3js-adapters'
import { getGlobalContext, getGlobalUmi } from '../index.test'
import { DST_EID, SRC_EID, uln, endpoint, HELLO_WORLD_PROGRAM_ID, GOVERNANCE_PROGRAM_ID } from '../constants'
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
const dummyOriginCaller = '0000000000000000000000000804a6e2798F42C7F3c97215DdF958d5500f8ec8'
const dummyRemote = '000000000000000000000000c4116303c13512dd1ff416d3a48ebec2f091a5e6';
const dummyRemoteBytes: Uint8Array = Uint8Array.from(Buffer.from(dummyRemote, 'hex'));

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

const cpiAuthority = deriver.cpiAuthority(SRC_EID, dummyOriginCaller)[0]

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
    
        const transaction = new Transaction().add(
            await governance.methods.initGovernance({
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
            .instruction()
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

        const transaction =
            await governance.methods.initGovernance({
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
            .transaction()

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
            endpoint.initOAppNonce(deployer.publicKey, SRC_EID, oapp, dummyRemoteBytes),
            endpoint.initOAppNonce(deployer.publicKey, DST_EID, oapp, dummyRemoteBytes),
        );
        
        await sendAndConfirmTransaction(context.connection, transaction, [deployer])
    })

    it("configures remote", async () => {
        const transaction = new Transaction().add(
            await governance.methods.setRemote({
                remoteEid: dummyEid,
                remote: Array.from(dummyRemoteBytes),
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
        assert.strictEqual(Buffer.from(remoteAccount.address).toString('hex'), dummyRemote);
    });

    it('configures delegate', async () => {
        const ixAccounts = EndpointProgram.instructions.createSetDelegateInstructionAccounts({
            oapp: governancePDA[0],
            oappRegistry: oAppRegistry,
            eventAuthority,
            program: ENDPOINT_PROGRAM_ID,
        }, ENDPOINT_PROGRAM_ID)
    
        ixAccounts[0].isSigner = false
    
        const transaction = 
            await governance.methods.setOappConfig({
                delegate: [cpiAuthority],
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
            .transaction()
            
        await sendAndConfirmTransaction(context.connection, transaction, [deployer])
    });

    it('configures admin', async () => {
        const ixAccounts = EndpointProgram.instructions.createSetDelegateInstructionAccounts({
            oapp: governancePDA[0],
            oappRegistry: oAppRegistry,
            eventAuthority,
            program: ENDPOINT_PROGRAM_ID,
        }, ENDPOINT_PROGRAM_ID)
    
        ixAccounts[0].isSigner = false
    
        const transaction =
            await governance.methods.setOappConfig({
                admin: [cpiAuthority],
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
            .transaction()
            
        await sendAndConfirmTransaction(context.connection, transaction, [deployer])

        const governanceAccount = await governance.account.governance.fetch(governancePDA[0]);
        assert.notEqual(governanceAccount, null);
        assert.strictEqual(governanceAccount.admin.toBase58(), cpiAuthority.toBase58());
    });

    it('executes hello world governance message', async () => {
        const dstTarget = new PublicKey(HELLO_WORLD_PROGRAM_ID).toBuffer().toString('hex')
        // Anchor example hello world "Initialize" instruction data that logs "Greetings"
        const dstCallData = '0000afaf6d1f0d989bed'
        const packet: Packet = {
            version: 1,
            nonce: '1',
            guid: '0xa9767b00b96f4eaa338a6a103ca9fd0b3281cfc6de6ec4a74756f3c7aba16f42',
            srcEid: SRC_EID,
            sender: `0x${dummyRemote}`,
            dstEid: DST_EID,
            receiver: fromWeb3JsPublicKey(governancePDA[0]),
            payload: '',
            message: `0x${dummyOriginCaller}${dstTarget}${dstCallData}`,
        }
        const encodedPacket = PacketSerializer.serializeBytes(packet);
        const packetSentEvent: PacketSentEvent = {
            encodedPacket,
            options: new Uint8Array(32).fill(0),
            sendLibrary: fromWeb3JsPublicKey(uln.program),
        };
        const signature = await verifyAndReceive(context, dummyRemoteBytes, fromWeb3JsPublicKey(governancePDA[0]), packetSentEvent);

        const logs = await getLogs(context.connection, signature);

        assert.ok(logs.some(l => l.includes(`Greetings from: ${HELLO_WORLD_PROGRAM_ID}`)));
    });

    it('executes change delegate governance message', async () => {
        const dstTarget = new PublicKey(GOVERNANCE_PROGRAM_ID).toBuffer().toString('hex')
        // set_oapp_config(Delegate(22222222222222222222222222222222222222222222))
        const dstCallData = '00086370695f617574686f726974790000000000000000000000000000000000000001002b673d364647ddcda8f24d646cd7d942102ad99a8e0ce907fa99109df9d08ecb00010c0e81235abd0ab11a34cbfda557654a5bcd35807e41c3c9ee4eb1aa9a410ecf00015aad76da514b6e1dcf11037e904dac3d375f525c9fbafcb19507b78907d8c18b00002b673d364647ddcda8f24d646cd7d942102ad99a8e0ce907fa99109df9d08ecb0001808d5a8ae34838381514989506632a2a9302ba6e0d9d8528e49be7eccaf536450001d1dd86ac361b6252c406c281f3912ab13b924126c011b587278e8af0b08ef09b00005aad76da514b6e1dcf11037e904dac3d375f525c9fbafcb19507b78907d8c18b0000d71a5d7ae10d39d6010f1e6b1421c04a070431265c19c5bbee1992bae8afd1cd078ef8af7047dc11f7'
        const packet: Packet = {
            version: 1,
            nonce: '2',
            guid: '0x22267b00b96f4eaa338a6a103ca9fd0b3281cfc6de6ec4a74756f3c7aba16f43',
            srcEid: SRC_EID,
            sender: `0x${dummyRemote}`,
            dstEid: DST_EID,
            receiver: fromWeb3JsPublicKey(governancePDA[0]),
            payload: '',
            message: `0x${dummyOriginCaller}${dstTarget}${dstCallData}`,
        }
        const encodedPacket = PacketSerializer.serializeBytes(packet);
        const packetSentEvent: PacketSentEvent = {
            encodedPacket,
            options: new Uint8Array(32).fill(0),
            sendLibrary: fromWeb3JsPublicKey(uln.program),
        };
        await verifyAndReceive(context, dummyRemoteBytes, fromWeb3JsPublicKey(governancePDA[0]), packetSentEvent);

        const oAppRegistryInfo = await EndpointProgram.accounts.OAppRegistry.fromAccountAddress(
            context.connection,
            oAppRegistry
        )

        assert.strictEqual(oAppRegistryInfo.delegate.toBase58(), '22222222222222222222222222222222222222222222');
    });
})