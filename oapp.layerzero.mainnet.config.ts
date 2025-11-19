import { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat';
import { EndpointId } from '@layerzerolabs/lz-definitions';
import { generateConnectionsConfig } from '@layerzerolabs/metadata-tools';

export const ethereumContract: OmniPointHardhat = {
  eid: EndpointId.ETHEREUM_V2_MAINNET,
  contractName: 'GovernanceOAppSender',
};

export const solanaContract: OmniPointHardhat = {
  eid: EndpointId.SOLANA_V2_MAINNET,
  address: '8vXXGiaXFrKFUDw21H5Z57ex552Lh8WP9rVd2ktzmcCy', // Governance OApp PDA
};

export default async function () {
  // note: pathways declared here are automatically bidirectional
  // if you declare A,B there's no need to declare B,A
  const connections = await generateConnectionsConfig([
    [
      ethereumContract, // Chain A contract
      solanaContract, // Chain B contract
      [[], [['LayerZero Labs', 'Nethermind', 'Canary', 'Deutsche Telekom', 'P2P', 'Horizen', 'Luganodes'], 4]], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
      [15, undefined], // [A to B confirmations, B to A confirmations] undefined means it is one way
      [undefined, undefined], // Chain B enforcedOptions, Chain A enforcedOptions
    ],
  ]);

  return {
    contracts: [
      {
        contract: ethereumContract,
        config: {
          delegate: '0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB',
          owner: '0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB',
        }
      },
      {
        contract: solanaContract,
        config: {
          delegate: 'AYPtjx4Hc8us1ikULUedkmZ3wtiD6tmL7gK3qe4V3oHt',
          owner: 'AYPtjx4Hc8us1ikULUedkmZ3wtiD6tmL7gK3qe4V3oHt',
        }
      }
    ],
    connections,
  };
}