import {ExecutorOptionType} from '@layerzerolabs/lz-v2-utilities';
import {OAppEnforcedOption, OmniPointHardhat} from '@layerzerolabs/toolbox-hardhat';
import {EndpointId} from '@layerzerolabs/lz-definitions';
import {generateConnectionsConfig} from '@layerzerolabs/metadata-tools';

import { getOftStoreAddress } from './tasks/solana'

// Note:  Do not use address for EVM OmniPointHardhat contracts.  Contracts are loaded using hardhat-deploy.
// If you do use an address, ensure artifacts exists.
export const avalancheContract: OmniPointHardhat = {
  eid: EndpointId.AVALANCHE_V2_TESTNET,
  contractName: 'MyOFT',
};

export const solanaContract: OmniPointHardhat = {
  eid: EndpointId.SOLANA_V2_TESTNET,
  address: getOftStoreAddress(EndpointId.SOLANA_V2_TESTNET),
};

const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
  {
    msgType: 1,
    optionType: ExecutorOptionType.LZ_RECEIVE,
    gas: 80000,
    value: 0,
  }
];

const SOLANA_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
  {
    msgType: 1,
    optionType: ExecutorOptionType.LZ_RECEIVE,
    gas: 200000,
    value: 2500000,
  }
];

export default async function () {
  // note: pathways declared here are automatically bidirectional
  // if you declare A,B there's no need to declare B,A
  const connections = await generateConnectionsConfig([
    [
      avalancheContract, solanaContract, [['LayerZero Labs'], []], [1, 1], [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
    ],
  ]);

  return {
    contracts: [
        {contract: avalancheContract},
        {
          contract: solanaContract,
          config: {
            delegate: 'EcZWx9kAwApNdd1Kb6omKifkr3ZehHBVqqoRPpmxNjv',
            owner: 'EcZWx9kAwApNdd1Kb6omKifkr3ZehHBVqqoRPpmxNjv'
          }
        }
    ],
    connections,
  };
}