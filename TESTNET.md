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
