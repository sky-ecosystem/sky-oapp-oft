import { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat';
import { EndpointId } from '@layerzerolabs/lz-definitions';
import { generateConnectionsConfig } from '@layerzerolabs/metadata-tools';

export const avalancheContract: OmniPointHardhat = {
  eid: EndpointId.AVALANCHE_V2_TESTNET,
  contractName: 'GovernanceOAppSender',
};

export const solanaContract: OmniPointHardhat = {
  eid: EndpointId.SOLANA_V2_TESTNET,
  address: '8vXXGiaXFrKFUDw21H5Z57ex552Lh8WP9rVd2ktzmcCy', // Governance OApp PDA
};

export default async function () {
  // note: pathways declared here are automatically bidirectional
  // if you declare A,B there's no need to declare B,A
  const connections = await generateConnectionsConfig([
    [
      avalancheContract, // Chain A contract
      solanaContract, // Chain B contract
      [[], [['LayerZero Labs', 'P2P'], 1]], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
      [15, undefined], // [A to B confirmations, B to A confirmations] undefined means it is one way
      [undefined, undefined], // Chain B enforcedOptions, Chain A enforcedOptions
    ],
  ]);

  return {
    contracts: [
      {
        contract: avalancheContract,
      },
      {
        contract: solanaContract,
      }
    ],
    connections,
  };
}