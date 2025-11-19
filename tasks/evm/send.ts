import bs58 from 'bs58'
import { BigNumber } from 'ethers'
import { task, types } from 'hardhat/config'
import { ActionType, HardhatRuntimeEnvironment } from 'hardhat/types'

import { makeBytes32 } from '@layerzerolabs/devtools'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import { getLayerZeroScanLink } from '../solana'

interface TaskArguments {
    dstEid: number
    amount: string
    to: string
}

const action: ActionType<TaskArguments> = async (
    { dstEid, amount, to },
    hre: HardhatRuntimeEnvironment
) => {
    if (dstEid !== EndpointId.SOLANA_V2_TESTNET && dstEid !== EndpointId.SOLANA_V2_MAINNET) {
        throw new Error('Only sending to Solana is supported')
    }

    const signer = await hre.ethers.getNamedSigner('deployer')
    const adapter = (await hre.ethers.getContract('SkyOFTAdapter')).connect(signer)
    const tokenAddress = await adapter.token()
    
    const erc20Token = (await hre.ethers.getContractAt('IERC20', tokenAddress)).connect(signer)
    const allowance = await erc20Token.allowance(signer.address, adapter.address)
    if (allowance.lt(amount)) {
        const approvalTxResponse = await erc20Token.approve(adapter.address, amount)
        const approvalTxReceipt = await approvalTxResponse.wait()
        console.log(`approve: ${amount}: ${approvalTxReceipt.transactionHash}`)
    }

    const amountLD = BigNumber.from(amount)

    const [currentAmountInFlight, amountCanBeSent] = await adapter.getAmountCanBeSent(dstEid)

    if (amountLD.gt(amountCanBeSent)) {
        throw new Error('Amount exceeds the Outbound Rate Limit')
    }

    const sendParam = {
        dstEid,
        to: makeBytes32(bs58.decode(to)),
        amountLD: amountLD.toString(),
        minAmountLD: amountLD.toString(),
        extraOptions: '0x',
        composeMsg: '0x',
        oftCmd: '0x',
    }
    const [msgFee] = await adapter.functions.quoteSend(sendParam, false)
    const txResponse = await adapter.functions.send(sendParam, msgFee, signer.address, {
        value: msgFee.nativeFee,
        gasLimit: 500_000,
    })
    const txReceipt = await txResponse.wait()
    console.log(`send: ${amount} to ${to}: ${txReceipt.transactionHash}`)
    console.log(
        `Track cross-chain transfer here: ${getLayerZeroScanLink(txReceipt.transactionHash, dstEid == EndpointId.SOLANA_V2_TESTNET)}`
    )
}

task('send', 'Sends a transaction', action)
    .addParam('dstEid', 'Destination endpoint ID', undefined, types.int, false)
    .addParam('amount', 'Amount to send in wei', undefined, types.string, false)
    .addParam('to', 'Recipient address', undefined, types.string, false)
