# Governance

A program that can be used to send arbitrary transactions on connected blockchains. The so-called Omnichain Applications (OApps) deployed on different chains can send Governance Messages to each other. These messages may contain transactions that are used to control programs owned by Governance OApps.

Blockchain messaging protocol used is LayerZero.

## Preparation

```
pnpm i
```

## Deployment

### Devnet

Generate key:
```
solana-keygen new -o target/deploy/governance-keypair.json --force
```

Copy pubkey - it will be your Governance program pubkey (GOVERNANCE_ID).

Build Governance program with your GOVERNANCE_ID:
```
GOVERNANCE_ID=XYZ anchor build
```

Deploy Governance Program to Solana Devnet:

```
solana program deploy target/deploy/governance.so -u devnet
```

Update `GOVERNANCE_PROGRAM_ID` in `.env` file. 

Now you can generate TypeScript types for Governance:
```
pnpm generate:governance
```

Double check generated file: `src/generated/governance/index.ts` - variable `PROGRAM_ADDRESS` - make sure it matches Governance Program ID.

Deploy EVM side, prepare .env variables first (change to your preferred values):
```
EVM_ADD_INITIAL_VALID_TARGET=false
EVM_INITIAL_VALID_TARGET_SRC_EID=0
EVM_INITIAL_VALID_TARGET_ORIGIN_CALLER=0x0000000000000000000000000000000000000000000000000000000000000000
EVM_INITIAL_VALID_TARGET_GOVERNED_CONTRACT=0x0000000000000000000000000000000000000000
```

Run the actual command:
```
pnpm hardhat lz:deploy

✔ Which deploy script tags would you like to use? … GovernanceControllerOApp
```

Take the deployed EVM address and put it as `GOVERNANCE_CONTROLLER_ADDRESS` in .env. Also update `programs/governance/tests/msg_codec.rs`: `FUJI_PEER_ADDRESS`.

Verify EVM contract, eg. using:
```
npx @layerzerolabs/verify-contract@latest -d deployments -n avalanche-testnet
```

Note: if you get error about conflicting NPM dependency, then `cd ..` and change flag: `-d <YOUR_PROJECT_DIR>/deployments`. 

Now run:
```
pnpm config:governance
```

It will create a Governance instance and configure it for you.

Take the: "governancePDA hex" from log of the above command and call `setPeer` on the EVM contract with its value and endpoint id. Eg. `setPeer, dstEid = 40168, peer = 0xa2a4c256938d341b8b41812a0348da0f489ec1bca07fdc7979717fdfb4aa8498`.

Note: If for some reason you modified Governance program and want to re-generate TypeScript SDK types you can run:
```
pnpm generate:governance
```

This is definitely not required if you didn't modify Governance program source code.

## Scenarios

The Governance program includes support for Solana and the current repository heavily focuses on providing example code for testing EVM -> Solana scenarios mainly for controlling OFT.

Tested scenarios include:
1. Hello World | test_hello_world | [demo](https://explorer.solana.com/tx/5n9NJXZ6PUR88kvi4TFYg2MZXimLDS6L4ErEPR6a5W9it5HNKw2HterJ1SvuYtW4s28dw22cGghJLJCZxqTSpVZh?cluster=devnet) | CPI depth = 1
2. Multi ix: Hello World + SPL token transfer | test_hello_world_and_spl_token_transfer | [demo](https://explorer.solana.com/tx/2yEN71oYUJtNiuHBnc2pZsRGKa14jtGo4KFGyP68ASYokfpNwNhnQmE5g6UM8o4c8en4QN9zF5eyyk6u8JTq9JiM?cluster=devnet) | CPI depth = 1

The code used to craft the Governance Message for the scenarios above is located in [programs/governance/tests/msg_codec.rs](./tests/msg_codec.rs).

### Upgrading program via Governance account

Before proceeding make sure your program upgrade authority is set to the OApp, like:
```
solana program set-upgrade-authority E2R6qMMzLBjCwXs66MPEg2zKfpt5AMxWNgSULsLYfPS2 --new-upgrade-authority 3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a --upgrade-authority ~/.config/solana/devnet-w.json --skip-new-upgrade-authority-signer-check
```

1. Generate temporary buffer authority key
```
solana-keygen new -o buffer-keypair.json
```

2. Create buffer account with new program bytecode:
```
solana program write-buffer target/deploy/oft.so --buffer-authority buffer-keypair.json -u devnet
```

Example output:
```
Buffer: Dftwzc6mc1ZUxZQyhM2FpmDttjfNra4mawAQnF4EWZns
```

3. Transfer buffer authority to Governance OApp (according to [this](https://github.com/solana-labs/solana/blob/7700cb3128c1f19820de67b81aa45d18f73d2ac0/sdk/program/src/loader_upgradeable_instruction.rs#L84))
```
solana program set-buffer-authority Dftwzc6mc1ZUxZQyhM2FpmDttjfNra4mawAQnF4EWZns --new-buffer-authority 3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a --buffer-authority buffer-keypair.json -u devnet
```

Example output:
```
solana program set-buffer-authority Dftwzc6mc1ZUxZQyhM2FpmDttjfNra4mawAQnF4EWZns --new-buffer-authority 3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a --buffer-authority buffer-keypair.json -u devnet
Account Type: Buffer
Authority: 3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a
```

4. Prepare BPF loader upgrade instruction encoded governance message using msg_codec, eg.:
```
cargo test --package governance --test msg_codec -- test_msg_codec::test_governance_message_upgrade_program --exact --show-output
```

5. Send the governance message eg using SendRawBytes Foundry script.

## Sending transactions

Before sending: Make sure your address is added as valid caller.

1. Obtain serialized governance message
2. Replace value of: `bytes memory messageBytes = hex"";` in scripts/SendRawBytes.s.sol
3. Run (in case you are sending to 40168 - Solana Devnet):
```
forge script scripts/SendRawBytes.s.sol -s "run(uint32)" 40168 --rpc-url https://api.avax-test.network/ext/bc/C/rpc --broadcast
```

## Configuring ALTs

If you are sending transaction with a lot of accounts you can configure ALTs to be used when lz_receive is called. You can create ALTs eg. `createLookupTable()` from `tasks/solana/clearPayloadV2.ts`.

Then you can set the ALT using following script:
```
pnpm hardhat lz:oapp:solana:setLzReceiveTypes --from-eid 40168 --alts GXR4civq2anMtcHGgApYrQWhpWJeqSybXkC4nVpAwWfg
```

## Delivering transactions

Clearing of transactions is manual because it uses ALT for lzReceive.

Example clear tx:

```
pnpm hardhat lz:oapp:solana:clear-v2 --src-tx-hash 0x41006c361e15153c0b2cae14f92121bd32e8484c2f0a3db54810e571fe8363d7
```

where --src-tx-hash is source transaction hash where the governance message was sent on the source chain.

## License

License is [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0).

See [LICENSE.md](./LICENSE.md) and [NOTICE.md](./NOTICE.md).