export * from './CpiAuthorityConfig'
export * from './Governance'
export * from './LzReceiveTypesV2Accounts'
export * from './Remote'

import { CpiAuthorityConfig } from './CpiAuthorityConfig'
import { Governance } from './Governance'
import { LzReceiveTypesV2Accounts } from './LzReceiveTypesV2Accounts'
import { Remote } from './Remote'

export const accountProviders = {
  CpiAuthorityConfig,
  Governance,
  LzReceiveTypesV2Accounts,
  Remote,
}
