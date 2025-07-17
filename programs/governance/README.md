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
EVM_WHITELIST_INITIAL_PAIR=false
EVM_INITIAL_WHITELISTED_SRC_EID=0
EVM_INITIAL_WHITELISTED_ORIGIN_CALLER=0x0000000000000000000000000000000000000000000000000000000000000000
EVM_INITIAL_WHITELISTED_GOVERNED_CONTRACT=0x0000000000000000000000000000000000000000
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
1. Hello World | test_hello_world | [demo](https://explorer.solana.com/tx/2ANEd8VWqqCe3jm4KWGNFUY93Q8JeNTCcS2E4PY6DBjtQgXJQ5MFLACX115vz1iKP7ePikhugbbfYQJyKTmFTuWp?cluster=devnet)
2. SPL token transfer | test_spl_token_transfer | [demo](https://explorer.solana.com/tx/2B8hxAJkc2fRP4ckZVNw8Uz4FyaDqk9ZDd3sShy8AwJ4ZHtoMmjPCHMSbiAcVDgpe2fmePDBuiLcwLVAn2zxZUBm?cluster=devnet)
3. Transfer Program Upgrade Authority | test_transfer_upgrade_authority | [demo](https://explorer.solana.com/tx/54M3cD2KqBZrs7sG2Cr3wwiMwSVNYSyEUfbLXho3U11EcPffCyi4VtfnxFrjCGiuqokd1ABfBoxQRncvrZEDeEgu?cluster=devnet)
4. Upgrade Program | test_governance_message_upgrade_program | [demo](https://explorer.solana.com/tx/5We9jE5C2FqeEJscwWvB7ncwc2RmsjxucdkFcyaQfRPBVyJVZfNYK82xp1LMroSxcWLsXeNYjfLA6proJ6ZGy13j?cluster=devnet)
5. OFT pause | test_governance_message_pause_oft | [demo](https://explorer.solana.com/tx/GZsXYNiUkC8JC7z82x5iiqPVD11BqACJfEn6cBGF5jKGB8Nayb7AvLdyunFC8uimFZFjMbrct2VcLs42LZBobF3?cluster=devnet)
6. OFT unpause | test_governance_message_unpause_oft | [demo](https://explorer.solana.com/tx/4koxbrtyEexG9DaHHxjKDGrw4mebPrasaXFfqPqMzKfC9roaQ2bpbGxxn4pXyaVAmPSDsQQgrqyax8CL26T9dJiz?cluster=devnet)
7. OFT.setOFTConfig - setDelegate | test_governance_message_set_delegate | [demo](https://explorer.solana.com/tx/2q8YcQ7V1iJWJBfXo8uEhNV16Z3XnVssXzniBhhurgzxF9Hue668sborVRY6hmAqVxXSZQcBuFAPFAcHaUySCauN?cluster=devnet)
8. OFT.setOFTConfig - setAdmin | test_governance_message_set_admin | [demo](https://explorer.solana.com/tx/5WUAgnhckabp67RQ6BMnc3Q7qNjgEbpqLpsoh6TFY9XVFEHGrwadYqCSqPsp3tVmswDotcL8PQ7c8LDobQHMKKat?cluster=devnet)
9. OFT.setPeerConfig - setPeerAddress | test_set_peer_address | [demo](https://explorer.solana.com/tx/4b1pUMmpANDQFZuoJb56B4SnMmbPvtuc5jP3TvecatCTWTsqYmnjpdVZPzdbD3GwAQzd4DjiwJKCSyHeijNro51J?cluster=devnet)
10. Endpoint.initSendLibrary | test_init_send_library | [demo](https://explorer.solana.com/tx/5rz9LrS5gzFvgZHjUUdaXjq3NrXUHceKSHvWz4mRHE6E83uxTX2TGGVMyYoaM3y2cthoVsCVSkb7W7pjDwLAEoCa?cluster=devnet)
11. Endpoint.setSendLibrary | test_governance_message_set_send_library | [demo](https://explorer.solana.com/tx/4syvFDSawatbkbTqGpAmB4Zohqv1hrgJYpnvPggoZv1kwfvh9EJYMLebbyq3jQcxZ1sbTiEmDEbxeFrHYNgGhtRX?cluster=devnet)
12. Endpoint.initReceiveLibrary | test_init_receive_library | [demo](https://explorer.solana.com/tx/3WUPcxgmszKRrU4i1jPqcjdnTVqeCpHqt5fSzotjdFmH8tut43rY3VL7FCdSXd7ezsuw9eGwrLH8n8QUfHu5cReM?cluster=devnet)
13. Endpoint.setReceiveLibrary | test_set_receive_library | [demo](https://explorer.solana.com/tx/3H52Uxht5pV6Yuj8W5Ai6ZnVYJhwrqjxc8xSpFdEvYp758nWueAdtqXbneTR6vhpSFAeB89Q7uPUP9WVfAE2wB8n?cluster=devnet)
14. OFT.setPeerConfig - setEnforcedOptions | test_governance_message_set_enforced_options | [demo](https://explorer.solana.com/tx/5ZQtDktmHRvjcvM2K9GohqsMLyXxDH8hRLxtYNPfyeceD9UBHC4dHGfirc3wZ92xhm4GMKxrfSLeMaFsTThJ7Sgj?cluster=devnet)
15. Endpoint.setConfig - setSendConfig | test_governance_message_set_send_config | [demo](https://explorer.solana.com/tx/5eeTsEU75UnM8VAjf9PxXLHUKiM1qkJD1rKBWAdTYVW4A4oCFobMSdr9QY47wr7N9fWv7F52J55RhvfSt6vkKGj6?cluster=devnet)
16. Endpoint.setConfig - setExecutorConfig | test_governance_message_set_executor_config | [demo](https://explorer.solana.com/tx/qminCQth3s7kvdC3P3BBLgr6qNckFnbuDv7EaUrhzUJX1HRAR7isLBAHSydQTavzNnBsSyZGexE7Ph3wh2XsBnd?cluster=devnet)
17. Endpoint.setConfig - setReceiveConfig | test_governance_message_set_receive_config | [demo](https://explorer.solana.com/tx/2T3aoUewbrU5Xwf9kF1ZQPXzYXx1wWoCce1PAHigUcHFqUm8LCEFjA7CS8Zvq7n6jT2mR2Wbm9mF2mZtRz3Tf8E8?cluster=devnet)
18. Endpoint.initNonce | test_governance_message_init_nonce | [demo](https://explorer.solana.com/tx/5ncNRyEwPUVwPb8mi5beLayDKXcwo38vauBVbCiTGmvs83g3hMQPnqcqCwJD6vW8memMgixVg2Ku4n8uRChzuYYx?cluster=devnet)
19. Squads.execute | test_squads_execute | [demo](https://explorer.solana.com/tx/5RgthGPgxUZLMswvWPtnwtZVB6oG4dAAKVjLaxtP5gFMG7PerZdP31togw8HFANBnB3QpBowCcj2XrAbaVzCt39c?cluster=devnet)
20. Endpoint.initConfig | test_endpoint_init_config | [demo](https://explorer.solana.com/tx/3T2EmnNU3zzrDgYXFiETFGgGnA259fQ3FuiNMXsfWMs36oNqscckPxXfK57uV8o1ESb4FtXqek9QLBCS3o8ESqfD?cluster=devnet)

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

1. Obtain serialized governance message
2. Replace value of: `bytes memory messageBytes = hex"";` in scripts/SendRawBytes.s.sol
3. Run:
```
forge script scripts/SendRawBytes.s.sol --rpc-url https://api.avax-test.network/ext/bc/C/rpc --broadcast --force
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