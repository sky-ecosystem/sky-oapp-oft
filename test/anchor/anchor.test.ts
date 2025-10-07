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
import { Governance } from "../../target/types/governance";
import { GovernancePDADeriver } from "../../src/governance-pda-deriver";
import { assert } from "chai";
import { Endpoint } from "../../target/types/endpoint";
import { EndpointProgram, EventPDADeriver } from "@layerzerolabs/lz-solana-sdk-v2";

const deployerSecretKey = fs.readFileSync(`${__dirname}/../../junk-id.json`, {
  encoding: "utf-8",
});

const deployer = anchor.web3.Keypair.fromSecretKey(Uint8Array.from(JSON.parse(deployerSecretKey)));
const notDeployer = anchor.web3.Keypair.generate();

const connection = new anchor.web3.Connection(
  "http://localhost:8899",
  "confirmed"
);

const governance = anchor.workspace
  .Governance as anchor.Program<Governance>;

const endpoint = anchor.workspace
  .Endpoint as anchor.Program<Endpoint>;

const endpointSDK = new EndpointProgram.Endpoint(endpoint.programId);

const dummyEid = 40106;
const dummyRemote = new Array(32).fill(1);

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
const [eventAuthority] = new EventPDADeriver(endpoint.programId).eventAuthority()

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

describe("Governance", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  async function fundWallet(account: anchor.web3.PublicKey, amount: number) {
    return provider.connection.confirmTransaction(
      await provider.connection.requestAirdrop(account, amount),
      "confirmed"
    );
  }

  beforeAll(async () => {
    await fundWallet(notDeployer.publicKey, 30 * anchor.web3.LAMPORTS_PER_SOL);
  });

  it("not a program upgrade authority can't initialize governance", async () => {
    const programAuthority = await getProgramAuthority(connection, governance.programId);
    assert.notOk(programAuthority.equals(notDeployer.publicKey));

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
    transaction.feePayer = notDeployer.publicKey;
    const { blockhash } = await connection.getLatestBlockhash();
    transaction.recentBlockhash = blockhash;

    transaction.sign(notDeployer);
   
    try {
      await sendAndConfirmTransaction(connection, transaction, [notDeployer], {
        commitment: "confirmed",
      })
      assert.ok(false);
    } catch (err: unknown) {
      assert.isTrue(err instanceof SendTransactionError);
      const anchorError = anchor.AnchorError.parse((err as SendTransactionError).logs || [])
      assert.isNotNull(anchorError);
      assert.strictEqual(anchorError.error.errorMessage, 'NotUpgradeAuthority');
    }
  });

  it("program upgrade authority can initialize governance", async () => {
    const programAuthority = await getProgramAuthority(connection, governance.programId);
    assert.ok(programAuthority.equals(deployer.publicKey));

    const ixAccounts = EndpointProgram.instructions.createRegisterOappInstructionAccounts(
        {
            payer: deployer.publicKey,
            oapp: governancePDA[0],
            oappRegistry: oAppRegistry,
            eventAuthority,
            program: endpoint.programId,
        },
        endpoint.programId
    )
    const registerOAppAccounts = [
      {
          pubkey: endpoint.programId,
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
    transaction.feePayer = deployer.publicKey;
    const { blockhash } = await connection.getLatestBlockhash();
    transaction.recentBlockhash = blockhash;

    transaction.sign(deployer);
   
    await sendAndConfirmTransaction(connection, transaction, [deployer], {
      commitment: "confirmed",
    })

    const governanceAccount = await governance.account.governance.fetch(governancePDA[0]);
    assert.isNotNull(governanceAccount);
    assert.strictEqual(governanceAccount.id.toNumber(), 0);
    assert.strictEqual(governanceAccount.admin.toBase58(), deployer.publicKey.toBase58());
  });

  it("configures remote", async () => {
    const ix = await governance.methods
        .setRemote({
          remoteEid: dummyEid,
          remote: dummyRemote,
        })
        .accountsStrict({
          admin: deployer.publicKey,
          remote: remotePDA[0],
          governance: governancePDA[0],
          systemProgram: SystemProgram.programId,
        })
        .instruction();

    const transaction = new Transaction().add(
      ix
    );
    transaction.feePayer = deployer.publicKey;
    const { blockhash } = await connection.getLatestBlockhash();
    transaction.recentBlockhash = blockhash;

    transaction.sign(deployer);
   
    await sendAndConfirmTransaction(connection, transaction, [deployer], {
      commitment: "confirmed",
    })

    const remoteAccount = await governance.account.remote.fetch(remotePDA[0]);
    assert.isNotNull(remoteAccount);
    assert.strictEqual(remoteAccount.address.toString(), dummyRemote.toString());
  });

  it('configures delegate', async () => {
    const ixAccounts = EndpointProgram.instructions.createSetDelegateInstructionAccounts({
        oapp: governancePDA[0],
        oappRegistry: oAppRegistry,
        eventAuthority,
        program: endpoint.programId,
      }, endpoint.programId)

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
            pubkey: endpoint.programId,
            isSigner: false,
            isWritable: false,
          },
          ...ixAccounts
        ])
        .instruction();

    const transaction = new Transaction().add(
      ix
    );
      
    transaction.feePayer = deployer.publicKey;
    const { blockhash } = await connection.getLatestBlockhash();
    transaction.recentBlockhash = blockhash;
    transaction.sign(deployer);
    await sendAndConfirmTransaction(connection, transaction, [deployer], {
      commitment: "confirmed",
    })
  });
});