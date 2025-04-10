# Governance

A program that can be used to send arbitrary transactions on connected blockchains. The so-called Omnichain Applications (OApps) deployed on different chains can send Governance Messages to each other. These messages may contain transactions that are used to control programs owned by Governance OApps. 

Messaging protocol used is LayerZero.

## Delivering transactions

Clearing of transactions is manual because it uses ALT for lzReceive.

Example clear tx:

```
pnpm hardhat lz:oapp:solana:clear-with-alt --src-eid 40106 --nonce 32 --sender 0xf941318e00fb58e00701423ba1adc607574bce99 --dst-eid 40168 --receiver 3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a --guid 0xc74ff9d8a8372596bcf054d99afeedd08b64f64c8ea3f14d92f4523ef2579211 --payload 0x000000000000000047656e6572616c507572706f7365476f7665726e616e63650200009ce8cbc3c6fe5a0bdf3ecdc2af991d34d8cc08adddcfa74986b275bf8e9510b06aa602a8f6914e88a1b0e210153ef763ae2b00c2b93d16c124d2c0537a100480000000035d190cf58aa6a0bbb66ffc441791e17f1abeeae5bd7991f5b5f21be5dfd1b6bd00016f776e65720000000000000000000000000000000000000000000000000000000100dd53b0252132362919bc40f483be023cd6967bde983ae2cdc2ddfaad66c06c8d0000000404000000 --compute-units 99999999999 --lamports 9999999999 --with-priority-fee 9900000000
```

## Upgrading program via Governance account

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

## License

License is [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0).

See [LICENSE.md](./LICENSE.md) and [NOTICE.md](./NOTICE.md).