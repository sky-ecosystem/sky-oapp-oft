# Governance

## Call Hello World on Solana from Fuji

Hello World is Anchor test program deployed on Solana Devnet. It logs a "Greetings from: <program_id>" message when "Initialize" instruction is called.

LZ scan: https://testnet.layerzeroscan.com/tx/0xea06f1c33bc6fe518584903f533de96cab3b8b149794e19f7dcd5fbcf3b137a7
Destination tx on Solana: https://explorer.solana.com/tx/4cBpcd2hmHax8iBVSxUEC92BX2dS2f1fLVBx8gpikeiSUYeSUAQo47Ad1X62VFQGRF8Ldk3upDJKT5X7EBnBxjyM?cluster=devnet

Log (from Solana explorer):
```
> Program logged: "Greetings from: 3ynNB373Q3VAzKp7m4x238po36hjAGFXFJB4ybN2iTyg"
```

## Transfer SPL

LZ scan: https://testnet.layerzeroscan.com/tx/0xe011c459761ec9f319f89bdb2f25bf7a2254721c5c0ee43791a4d7ef9ee4a84d
Destination tx on Solana: https://explorer.solana.com/tx/nLRtTDRQd6vJX5axWWh2JjpTUjNHfLQv34pTB37zRFHkeFEG7fe6ZwYhxStcDzQJ7Y3GvPyJPQ78gqRRLHTfmoT?cluster=devnet

Log (from Solana explorer):
```
Program invoked: Token Program
    > Program logged: "Instruction: TransferChecked"
```

## OFT Init Two Leg Send

LZ scan: https://testnet.layerzeroscan.com/tx/0x2024fb534e409fb11f8285c71e651ca9e358ed2a8dc2cff91d97a0d15ed977a8
Destination tx on Solana: https://explorer.solana.com/tx/4TMTzynY9GJvPi4F7j3GnDtNigAF7e3gKNN6qFj6ns7tQwHVpdFbaKQoiNDFasKSnWXDr7Dz3osQ3JPcApPDvKd?cluster=devnet

Log (from Solana explorer):
```
[
  "Program EiQujD3MpwhznKZn4jSa9J7j6cHd7W9QA213QrPZgpR3 invoke [1]",
  "Program log: Instruction: LzReceive",
  "Program 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6 invoke [2]",
  "Program log: Instruction: Clear",
  "Program 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6 invoke [3]",
  "Program 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6 consumed 2127 of 165901 compute units",
  "Program 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6 success",
  "Program 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6 consumed 20144 of 182659 compute units",
  "Program return: 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6 Pe7kuTGiwFVpvMBIEd67Muux0UiLfwztCpX/FB35RLo=",
  "Program 76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6 success",
  "Program E2R6qMMzLBjCwXs66MPEg2zKfpt5AMxWNgSULsLYfPS2 invoke [2]",
  "Program log: Instruction: InitTwoLegSend",
  "Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA invoke [3]",
  "Program log: Instruction: Burn",
  "Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA consumed 4753 of 134177 compute units",
  "Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA success",
  "Program log: InitTwoLegSend: TODO: store the message for permissionless execution",
  "Program E2R6qMMzLBjCwXs66MPEg2zKfpt5AMxWNgSULsLYfPS2 consumed 24956 of 152018 compute units",
  "Program E2R6qMMzLBjCwXs66MPEg2zKfpt5AMxWNgSULsLYfPS2 success",
  "Program EiQujD3MpwhznKZn4jSa9J7j6cHd7W9QA213QrPZgpR3 consumed 74377 of 200000 compute units",
  "Program EiQujD3MpwhznKZn4jSa9J7j6cHd7W9QA213QrPZgpR3 success"
]
```

--- NEW ---

LZ scan: https://testnet.layerzeroscan.com/tx/0x73f6ec6386b008fd2658a23baf533d4e5de2b6f0044c930c789d7469dbe97f1b
LZ scan API: https://scan-testnet.layerzero-api.com/v1/messages/tx/0x73f6ec6386b008fd2658a23baf533d4e5de2b6f0044c930c789d7469dbe97f1b

```
pnpm hardhat lz:oapp:solana:clear-with-alt --src-eid 40106 --nonce 29 --sender 0xf941318e00fb58e00701423ba1adc607574bce99 --dst-eid 40168 --receiver 3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a --guid 0x70e68e564b2370f06c771d78e1489200ca1508a7889689159d975c9c0548b057 --payload 0x000000000000000047656e6572616c507572706f7365476f7665726e616e63650200009ce8cbc3c6fe5a0bdf3ecdc2af991d34d8cc08adddcfa74986b275bf8e9510b06aa6c184c2ef53612c46c1dc9b552712be77c0225cd93b1bfe0e3016274171af318300086f776e65720000000000000000000000000000000000000000000000000000000100c95eb417a3787eac4572559972db007169f417c7849db8babff900fc206ed11c0001f4bf1dcc335237f362af562f830bc06fd686567001afce44fb8e865e81dc8b740001a8628a7c7d95047036683ad0dce93a058586423f90c5278e8fc3b1b8f08867350001fbc69e44452491af1fbfab48f29050e95f82f2f418c5c411f3a5c211b6fcc4fe000192db6c10a58bab95316c39ae35a2493a86ab87473e3ae00c6b30f41e41da0b75000106ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a90000585c0593a2656f63d4019a63580b9482e15fabdc5793bf57d1b1c413926cb9840001006712dbd3b85bf4127baa9c00000000000000000000000000000804a6e2798f42c7f3c97215ddf958d5500f8ec8e803000000000000e8030000000000001600000000030100110100000000000000000000000000030d400000000000000000000000000000000000 --compute-units 99999999999 --lamports 9999999999 --with-priority-fee 9900000000
```

## Multi ix OFT.send

```
➜ pnpm hardhat lz:oft:solana:send-multi-ix --amount 1000 --from-eid 40168 --to Fty7h4FYAN7z8yjqaJExMHXbUoJYMcRjWYmggSxLbHp8 --to-eid 40106 --mint AtGakZsHVY1BkinHEFMEJxZYhwA9KnuLD8QRmGjSAZEC --program-id E2R6qMMzLBjCwXs66MPEg2zKfpt5AMxWNgSULsLYfPS2 --escrow HwpzV5qt9QzYRuWkHqTRuhbqtaMhapSNuriS5oMynkny

✅ Sent 1000 token(s) to destination EID: 40106!
View Solana transaction here: https://solscan.io/tx/24SkyzHaGtTMgjBkUYyHaJA95GrDPZcq2NJZYMepY2evhrjEeYJvP4MqeacmQ6Lrs641oW9FbtuXmtjJa3nf72La?cluster=devnet
Track cross-chain transfer here: https://testnet.layerzeroscan.com/tx/24SkyzHaGtTMgjBkUYyHaJA95GrDPZcq2NJZYMepY2evhrjEeYJvP4MqeacmQ6Lrs641oW9FbtuXmtjJa3nf72La
```