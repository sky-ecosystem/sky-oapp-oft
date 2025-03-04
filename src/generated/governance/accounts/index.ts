export * from './Governance'
export * from './LzReceiveAlt'
export * from './LzReceiveTypesAccounts'
export * from './Remote'

import { Governance } from './Governance'
import { LzReceiveAlt } from './LzReceiveAlt'
import { LzReceiveTypesAccounts } from './LzReceiveTypesAccounts'
import { Remote } from './Remote'

export const accountProviders = {
  Governance,
  LzReceiveAlt,
  LzReceiveTypesAccounts,
  Remote,
}
