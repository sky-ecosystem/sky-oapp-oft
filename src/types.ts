import * as web3 from '@solana/web3.js'
import * as beetSolana from '@metaplex-foundation/beet-solana'
import * as beet from '@metaplex-foundation/beet'

export type LzReceiveTypesInfoResult = {
  accounts: web3.PublicKey[]
}

export const lzReceiveTypesInfoResultBeet =
  new beet.FixableBeetArgsStruct<LzReceiveTypesInfoResult>(
    [
      ['accounts', beet.array(beetSolana.publicKey)],
    ],
    'LzReceiveTypesInfoResult'
  )
