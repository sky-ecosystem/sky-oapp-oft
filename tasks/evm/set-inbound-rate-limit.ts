import { task } from 'hardhat/config'

task('lz:oftadapter:set-inbound-rate-limit', '')
    .addParam('srcEid', 'source endpoint ID')
    .addParam('amount', 'amount in 18 decimals')
    .addParam('window', 'window in seconds')
    .setAction(async (taskArgs, { ethers }) => {
        const srcEid = taskArgs.srcEid

        const signer = await ethers.getNamedSigner('deployer')
        const oft = (await ethers.getContract('SkyOFTAdapter')).connect(signer)

        const maxAmount = ethers.utils.parseUnits(taskArgs.amount, 18).toString()

        const inboundRateLimits = [{
            eid: srcEid,
            limit: maxAmount,
            window: taskArgs.window,
        }]

        const r = await oft.setRateLimits(inboundRateLimits, []);

        console.log(`Tx sent, hash: ${r.hash}`)
    })