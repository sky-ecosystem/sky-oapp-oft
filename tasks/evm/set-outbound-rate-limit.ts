import { task } from 'hardhat/config'

task('lz:oftadapter:set-outbound-rate-limit', '')
    .addParam('dstEid', 'destination endpoint ID')
    .addParam('amount', 'amount in 18 decimals')
    .addParam('window', 'window in seconds')
    .setAction(async (taskArgs, { ethers }) => {
        const dstEid = taskArgs.dstEid

        const signer = await ethers.getNamedSigner('deployer')
        const oft = (await ethers.getContract('SkyOFTAdapter')).connect(signer)

        const maxAmount = ethers.utils.parseUnits(taskArgs.amount, 18).toString()

        const outboundRateLimits = [{
            eid: dstEid,
            limit: maxAmount,
            window: taskArgs.window,
        }]

        const r = await oft.setRateLimits([], outboundRateLimits);

        console.log(`Tx sent, hash: ${r.hash}`)
    })