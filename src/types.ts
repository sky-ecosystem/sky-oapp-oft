import * as web3 from '@solana/web3.js'
import * as beetSolana from '@metaplex-foundation/beet-solana'
import * as beet from '@metaplex-foundation/beet'

import { AddressOrAltIndex, addressOrAltIndexBeet } from './generated/governance/types'

export type LzReceiveTypesInfoResult = {
  accounts: AddressOrAltIndex[]
  alts: web3.PublicKey[]
}

export const lzReceiveTypesInfoResultBeet =
  new beet.FixableBeetArgsStruct<LzReceiveTypesInfoResult>(
    [
      ['alts', beet.array(beetSolana.publicKey)],
      ['accounts', beet.array(addressOrAltIndexBeet)],
    ],
    'LzReceiveTypesInfoResult'
  )
