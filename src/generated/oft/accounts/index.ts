export * from './LzReceiveTypesAccounts'
export * from './OFTStore'
export * from './PeerConfig'
export * from './TwoLegSendPendingMessageStore'

import { LzReceiveTypesAccounts } from './LzReceiveTypesAccounts'
import { OFTStore } from './OFTStore'
import { PeerConfig } from './PeerConfig'
import { TwoLegSendPendingMessageStore } from './TwoLegSendPendingMessageStore'

export const accountProviders = {
  LzReceiveTypesAccounts,
  OFTStore,
  PeerConfig,
  TwoLegSendPendingMessageStore,
}
