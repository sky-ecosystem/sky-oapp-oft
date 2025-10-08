import { publicKey } from '@metaplex-foundation/umi'
import { utils } from '@noble/secp256k1'
import { SimpleMessageLibProgram, EndpointProgram, UlnProgram, ExecutorProgram, PriceFeedProgram } from '@layerzerolabs/lz-solana-sdk-v2'
import { EndpointProgram as EndpointProgramUMI } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { UlnProgram as UlnProgramUMI } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { ExecutorProgram as ExecutorProgramUMI } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { PriceFeedProgram as PriceFeedProgramUMI } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { SimpleMessageLibProgram as SimpleMessageLibProgramUMI } from '@layerzerolabs/lz-solana-sdk-v2/umi'
import { readFileSync } from 'fs'

export const SRC_EID = 40106
export const DST_EID = 40168

export const GOVERNANCE_PROGRAM_ID = publicKey('EiQujD3MpwhznKZn4jSa9J7j6cHd7W9QA213QrPZgpR3')
export const HELLO_WORLD_PROGRAM_ID = publicKey('3ynNB373Q3VAzKp7m4x238po36hjAGFXFJB4ybN2iTyg')

export const DEPLOYER_SECRET_KEY = readFileSync(`${__dirname}/../../junk-id.json`, {
    encoding: "utf-8",
});
  
export const DEPLOYER = publicKey("JD5ype5b3NTRDddDtoqLXHcJcCoBToxs9ZnsKMkFbguD");

export const DVN_SIGNERS = new Array(4).fill(0).map(() => utils.randomPrivateKey())

export const defaultMultiplierBps = 12500 // 125%

export const simpleMessageLib: SimpleMessageLibProgram.SimpleMessageLib =
    new SimpleMessageLibProgram.SimpleMessageLib(SimpleMessageLibProgram.PROGRAM_ID)

export const endpoint: EndpointProgram.Endpoint = new EndpointProgram.Endpoint(
    EndpointProgram.PROGRAM_ID
)
export const uln: UlnProgram.Uln = new UlnProgram.Uln(UlnProgram.PROGRAM_ID)
export const executor: ExecutorProgram.Executor = new ExecutorProgram.Executor(
    ExecutorProgram.PROGRAM_ID
)
export const priceFeed: PriceFeedProgram.PriceFeed = new PriceFeedProgram.PriceFeed(
    PriceFeedProgram.PROGRAM_ID
)

export const dvns = [publicKey('HtEYV4xB4wvsj5fgTkcfuChYpvGYzgzwvNhgDZQNh7wW')]

export const UMI = {
    endpoint: new EndpointProgramUMI.Endpoint(EndpointProgramUMI.ENDPOINT_PROGRAM_ID),
    uln: new UlnProgramUMI.Uln(UlnProgramUMI.ULN_PROGRAM_ID),
    executor: new ExecutorProgramUMI.Executor(ExecutorProgramUMI.EXECUTOR_PROGRAM_ID),
    priceFeed: new PriceFeedProgramUMI.PriceFeed(PriceFeedProgramUMI.PRICEFEED_PROGRAM_ID),
    simpleMessageLib: new SimpleMessageLibProgramUMI.SimpleMessageLib(SimpleMessageLibProgramUMI.SIMPLE_MESSAGELIB_PROGRAM_ID),
}