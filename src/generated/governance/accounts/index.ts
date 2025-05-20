export * from './CpiAuthorityConfig'
export * from './Governance'
export * from './LzReceiveAlt'
export * from './LzReceiveTypesAccounts'
export * from './Remote'

import { CpiAuthorityConfig } from './CpiAuthorityConfig'
import { Governance } from './Governance'
import { LzReceiveAlt } from './LzReceiveAlt'
import { LzReceiveTypesAccounts } from './LzReceiveTypesAccounts'
import { Remote } from './Remote'

export const accountProviders = {
  CpiAuthorityConfig,
  Governance,
  LzReceiveAlt,
  LzReceiveTypesAccounts,
  Remote,
}
