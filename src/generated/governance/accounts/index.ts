export * from './Governance'
export * from './LzReceiveTypesV2GovernanceAccounts'
export * from './Remote'

import { Governance } from './Governance'
import { LzReceiveTypesV2GovernanceAccounts } from './LzReceiveTypesV2GovernanceAccounts'
import { Remote } from './Remote'

export const accountProviders = {
  Governance,
  LzReceiveTypesV2GovernanceAccounts,
  Remote,
}
