import { task } from 'hardhat/config'

task('lz:oftadapter:set-inbound-rate-limit', '')
    .addParam('srcEid', 'source endpoint ID')
    .addParam('amount', 'amount in 18 decimals')
    .addParam('window', 'window in seconds')
    .setAction(async (taskArgs, { ethers }) => {
        const srcEid = taskArgs.srcEid

        const signer = await ethers.getNamedSigner('deployer')
        const oft = (await ethers.getContract('SkyOFTAdapter')).connect(signer)

        const maxAmount = ethers.utils.parseUnits(taskArgs.amount, 18)
        const uint128Max = ethers.BigNumber.from('0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF')

        if (maxAmount.gt(uint128Max)) {
            throw new Error('Amount exceeds the uint128 max')
        }

        const inboundRateLimits = [{
            eid: srcEid,
            limit: maxAmount.toString(),
            window: taskArgs.window,
        }]

        const tx = await oft.setRateLimits(inboundRateLimits, []);

        console.log(`Tx sent, hash: ${tx.hash}`)
    })