export * from './Governance'
export * from './LzReceiveTypesAccounts'
export * from './Remote'

import { Governance } from './Governance'
import { LzReceiveTypesAccounts } from './LzReceiveTypesAccounts'
import { Remote } from './Remote'

export const accountProviders = { Governance, LzReceiveTypesAccounts, Remote }
