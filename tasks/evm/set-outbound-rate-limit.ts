import { task } from 'hardhat/config'

task('lz:oftadapter:set-outbound-rate-limit', '')
    .addParam('dstEid', 'destination endpoint ID')
    .addParam('amount', 'amount in 18 decimals')
    .addParam('window', 'window in seconds')
    .setAction(async (taskArgs, { ethers }) => {
        const dstEid = taskArgs.dstEid

        const signer = await ethers.getNamedSigner('deployer')
        const oft = (await ethers.getContract('SkyOFTAdapter')).connect(signer)

        const maxAmount = ethers.utils.parseUnits(taskArgs.amount, 18)
        const uint128Max = ethers.BigNumber.from('0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF')

        if (maxAmount.gt(uint128Max)) {
            throw new Error('Amount exceeds the uint128 max')
        }

        const outboundRateLimits = [{
            eid: dstEid,
            limit: maxAmount.toString(),
            window: taskArgs.window,
        }]

        const tx = await oft.setRateLimits([], outboundRateLimits);

        console.log(`Tx sent, hash: ${tx.hash}`)
    })