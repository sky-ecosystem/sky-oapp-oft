# External Multicall OFT Chain Expansion

Build:
```
EXTERNAL_MULTICALL_ID=7Ackc8DwwpRvEAZsR12Ru27swgk1ifWuEmHQ3g3Q6tbj anchor build -p external_multicall -- --features "custom-heap"
```

Deploy:
```
solana program deploy target/deploy/external_multicall.so -u devnet --program-id 7Ackc8DwwpRvEAZsR12Ru27swgk1ifWuEmHQ3g3Q6tbj
```