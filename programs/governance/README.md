# Governance

A program that can be used to send arbitrary transactions on connected blockchains. The so-called Omnichain Applications (OApps) deployed on different chains can send Governance Messages to each other. These messages may contain transactions that are used to control programs owned by Governance OApps.

Blockchain messaging protocol used is LayerZero.

## Scenarios

The Governance program includes support for Solana and the current repository heavily focuses on providing example code for testing EVM -> Solana scenarios mainly for controlling OFT.

Tested scenarios include:
1. Hello World | test_governance_message_hello_world | [demo](https://explorer.solana.com/tx/4cBpcd2hmHax8iBVSxUEC92BX2dS2f1fLVBx8gpikeiSUYeSUAQo47Ad1X62VFQGRF8Ldk3upDJKT5X7EBnBxjyM?cluster=devnet)
2. SPL token transfer | test_governance_message_transfer_token | [demo](https://explorer.solana.com/tx/nLRtTDRQd6vJX5axWWh2JjpTUjNHfLQv34pTB37zRFHkeFEG7fe6ZwYhxStcDzQJ7Y3GvPyJPQ78gqRRLHTfmoT?cluster=devnet)
3. Transfer Program Upgrade Authority | test_governance_message_transfer_upgrade_authority | [demo](https://explorer.solana.com/tx/46NooMsMmBASL335wFuk4rd7uJdAHi75UA1Ap5ba3NSqPb7xrf7y7qe2G2Txntvrak2bXRDyihphXqgQBKW54GRY?cluster=devnet)
4. Upgrade Program | test_governance_message_upgrade_program | [demo](https://explorer.solana.com/tx/5We9jE5C2FqeEJscwWvB7ncwc2RmsjxucdkFcyaQfRPBVyJVZfNYK82xp1LMroSxcWLsXeNYjfLA6proJ6ZGy13j?cluster=devnet)
5. OFT pause | test_governance_message_pause_oft | [demo](https://explorer.solana.com/tx/GZsXYNiUkC8JC7z82x5iiqPVD11BqACJfEn6cBGF5jKGB8Nayb7AvLdyunFC8uimFZFjMbrct2VcLs42LZBobF3?cluster=devnet)
6. OFT unpause | test_governance_message_unpause_oft | [demo](https://explorer.solana.com/tx/4koxbrtyEexG9DaHHxjKDGrw4mebPrasaXFfqPqMzKfC9roaQ2bpbGxxn4pXyaVAmPSDsQQgrqyax8CL26T9dJiz?cluster=devnet)
7. OFT.setOFTConfig - setDelegate | test_governance_message_set_delegate | [demo](https://explorer.solana.com/tx/2q8YcQ7V1iJWJBfXo8uEhNV16Z3XnVssXzniBhhurgzxF9Hue668sborVRY6hmAqVxXSZQcBuFAPFAcHaUySCauN?cluster=devnet)
8. OFT.setOFTConfig - setAdmin | test_governance_message_set_admin | [demo](https://explorer.solana.com/tx/5WUAgnhckabp67RQ6BMnc3Q7qNjgEbpqLpsoh6TFY9XVFEHGrwadYqCSqPsp3tVmswDotcL8PQ7c8LDobQHMKKat?cluster=devnet)
9. OFT.setPeerConfig - setPeerAddress | test_governance_message_set_peer_address | [demo](https://explorer.solana.com/tx/5mBi5r5zcfrcDHxsNrPAHS4HrkP2kS3zgJ6YRe6vGLN18N9GPvMXBD9AfAYbEhWQSTHMLEjLAFR3MNV185xacP7f?cluster=devnet)
10. Endpoint.initSendLibrary | test_governance_message_init_send_library | [demo](https://explorer.solana.com/tx/SBUGAFrgWcpLJkuaq8W6YfeKakW2zvYe56HmG6pB7EdiozmCTTTaVXWADVUVqUZRNLU1qoP4BeQbdVrPqLXpH8X?cluster=devnet)

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

## Delivering transactions

Clearing of transactions is manual because it uses ALT for lzReceive.

Example clear tx:

```
pnpm hardhat lz:oapp:solana:clear-with-alt --compute-units 99999999999 --lamports 9999999999 --with-priority-fee 9900000000 --src-tx-hash 0x17d992d34e821bd4b962c22910127624ef62e02f49f7013e453369f258c29c70
```

where --src-tx-hash is source transaction hash where the governance message was sent on the source chain.

## License

License is [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0).

See [LICENSE.md](./LICENSE.md) and [NOTICE.md](./NOTICE.md).