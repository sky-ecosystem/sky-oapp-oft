import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

const contractName = 'GovernanceControllerOApp'

const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre

    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    assert(deployer, 'Missing named deployer account')

    console.log(`Network: ${hre.network.name}`)
    console.log(`Deployer: ${deployer}`)

    // This is an external deployment pulled in from @layerzerolabs/lz-evm-sdk-v2
    //
    // @layerzerolabs/toolbox-hardhat takes care of plugging in the external deployments
    // from @layerzerolabs packages based on the configuration in your hardhat config
    //
    // For this to work correctly, your network config must define an eid property
    // set to `EndpointId` as defined in @layerzerolabs/lz-definitions
    //
    // For example:
    //
    // networks: {
    //   fuji: {
    //     ...
    //     eid: EndpointId.AVALANCHE_V2_TESTNET
    //   }
    // }
    const endpointV2Deployment = await hre.deployments.get('EndpointV2')

    const whitelistInitialPair = readEnv('EVM_WHITELIST_INITIAL_PAIR') === 'true'
    const initialWhitelistedSrcEid = readEnv('EVM_INITIAL_WHITELISTED_SRC_EID')
    const initialWhitelistedOriginCaller = readEnv('EVM_INITIAL_WHITELISTED_ORIGIN_CALLER')
    const initialWhitelistedGovernedContract = readEnv('EVM_INITIAL_WHITELISTED_GOVERNED_CONTRACT')

    console.log(`Whitelist initial pair: ${whitelistInitialPair}`)
    console.log(`Initial whitelisted src EID: ${initialWhitelistedSrcEid}`)
    console.log(`Initial whitelisted origin caller: ${initialWhitelistedOriginCaller}`)
    console.log(`Initial whitelisted governed contract: ${initialWhitelistedGovernedContract}`)

    const { address } = await deploy(contractName, {
        from: deployer,
        args: [
            endpointV2Deployment.address, // LayerZero's EndpointV2 address
            deployer, // owner & delegate
            whitelistInitialPair, // whitelistInitialPair
            initialWhitelistedSrcEid, // initialWhitelistedSrcEid
            initialWhitelistedOriginCaller, // initialWhitelistedOriginCaller
            initialWhitelistedGovernedContract // initialWhitelistedGovernedContract
        ],
        log: true,
        skipIfAlreadyDeployed: false,
    })

    console.log(`Deployed contract: ${contractName}, network: ${hre.network.name}, address: ${address}`)
}

function readEnv(name: string) {
    const value = process.env[name]
    if (!value) {
        throw new Error(`Environment variable ${name} is not set`)
    }
    return value
}

deploy.tags = [contractName]

export default deploy
