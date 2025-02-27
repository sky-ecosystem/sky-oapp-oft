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
