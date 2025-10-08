import 'mocha'
import { ChildProcess } from 'child_process'
import fs from 'fs'
import path from 'path'
import { env } from 'process'

import {
    Context,
    createNullContext,
    createSignerFromKeypair,
    generateSigner,
    Program,
    sol,
    Umi,
} from '@metaplex-foundation/umi'
import { createUmi } from '@metaplex-foundation/umi-bundle-defaults'
import { Connection } from '@solana/web3.js'
import axios from 'axios'
import { $, sleep } from 'zx'
import { DEPLOYER, DEPLOYER_SECRET_KEY, GOVERNANCE_PROGRAM_ID } from './constants'
import { createDefaultProgramRepository } from '@metaplex-foundation/umi-program-repository'
import { TestContext } from './types'
import * as anchor from "@coral-xyz/anchor";

const RPC_PORT = '13033'
const FAUCET_PORT = '13133'
const RPC = `http://localhost:${RPC_PORT}`

// Global test environment
let globalContext: TestContext
let globalUmi: Umi | Context
let solanaProcess: ChildProcess

const deployer = anchor.web3.Keypair.fromSecretKey(Uint8Array.from(JSON.parse(DEPLOYER_SECRET_KEY)));
anchor.setProvider(new anchor.AnchorProvider(new Connection(RPC, 'confirmed'), new anchor.Wallet(deployer), {}));

describe('Governance Solana Tests', function () {
    this.timeout(300000) // 5 minutes timeout for environment setup

    before(async function () {
        console.log('🚀 Setting up test environment...')

        // 1. Setup program directory and download dependency programs
        await setupPrograms()

        // 2. Start solana-test-validator
        solanaProcess = await startSolanaValidator()

        // 3. Create global test context
        globalContext = await createGlobalTestContext()
        globalUmi = globalContext.umi

        console.log('✅ Test environment ready!')
    })

    after(async function () {
        console.log('🧹 Cleaning up test environment...')
        globalUmi = createNullContext()
        globalContext.umi = globalUmi
        await sleep(2000)
        solanaProcess.kill('SIGKILL')
        console.log('✅ Cleanup completed!')
    })

    require('./suites/layerzero-infrastructure.test')
    require('./suites/init_governance.test')
})

// Export global context for child tests
export function getGlobalContext(): TestContext {
    return globalContext
}

export function getGlobalUmi(): Umi | Context {
    return globalUmi
}

async function setupPrograms(): Promise<void> {
    const programsDir = path.join(__dirname, '../../target/programs')
    env.RUST_LOG = 'solana_runtime::message_processor=debug'
    await $`mkdir -p ${programsDir}`

    const programs = [
        { name: 'endpoint', id: '76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6' },
        { name: 'simple_messagelib', id: '6GsmxMTHAAiFKfemuM4zBjumTjNSX5CAiw4xSSXM2Toy' },
        { name: 'uln', id: '7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH' },
        { name: 'executor', id: '6doghB248px58JSSwG4qejQ46kFMW4AMj7vzJnWZHNZn' },
        { name: 'dvn', id: 'HtEYV4xB4wvsj5fgTkcfuChYpvGYzgzwvNhgDZQNh7wW' },
        { name: 'pricefeed', id: '8ahPGPjEbpgGaZx2NV1iG5Shj7TDwvsjkEDcGWjt94TP' },
        { name: 'blocked_messagelib', id: '2XrYqmhBMPJgDsb4SVbjV1PnJBprurd5bzRCkHwiFCJB' },
        { name: 'hello_world', id: '3ynNB373Q3VAzKp7m4x238po36hjAGFXFJB4ybN2iTyg' }
    ]

    console.log('📦 Downloading LayerZero programs...')
    for (const program of programs) {
        const programPath = `${programsDir}/${program.name}.so`
        if (!fs.existsSync(programPath)) {
            console.log(`  Downloading ${program.name}...`)
            await $({ verbose: true })`solana program dump ${program.id} ${programPath} -u devnet`
        }
    }
}

async function startSolanaValidator(): Promise<ChildProcess> {
    const programsDir = path.join(__dirname, '../../target/programs')

    const args = [
        '--reset',
        '--rpc-port',
        RPC_PORT,
        '--faucet-port',
        FAUCET_PORT,

        '--bpf-program',
        '76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6',
        `${programsDir}/endpoint.so`,

        '--bpf-program',
        '6GsmxMTHAAiFKfemuM4zBjumTjNSX5CAiw4xSSXM2Toy',
        `${programsDir}/simple_messagelib.so`,

        '--bpf-program',
        '7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH',
        `${programsDir}/uln.so`,

        '--bpf-program',
        '6doghB248px58JSSwG4qejQ46kFMW4AMj7vzJnWZHNZn',
        `${programsDir}/executor.so`,

        '--bpf-program',
        'HtEYV4xB4wvsj5fgTkcfuChYpvGYzgzwvNhgDZQNh7wW',
        `${programsDir}/dvn.so`,

        '--bpf-program',
        '8ahPGPjEbpgGaZx2NV1iG5Shj7TDwvsjkEDcGWjt94TP',
        `${programsDir}/pricefeed.so`,

        '--bpf-program',
        '2XrYqmhBMPJgDsb4SVbjV1PnJBprurd5bzRCkHwiFCJB',
        `${programsDir}/blocked_messagelib.so`,

        '--bpf-program',
        '3ynNB373Q3VAzKp7m4x238po36hjAGFXFJB4ybN2iTyg',
        `${programsDir}/hello_world.so`,

        '--upgradeable-program',
        GOVERNANCE_PROGRAM_ID,
        `${__dirname}/../../target/deploy/governance.so`,
        DEPLOYER
    ]

    // Load inactive features from cached file or retrieve from mainnet
    console.log('🔍 Loading mainnet feature flags...')
    const inactiveFeatures = await loadInactiveFeatures()
    inactiveFeatures.forEach((f) => {
        args.push('--deactivate-feature', f.id)
    })

    console.log('🚀 Starting solana-test-validator...')
    const logFile = path.join(__dirname, '../../target/solana-test-validator.log')
    const process = $.spawn('solana-test-validator', [...args], {
        stdio: ['ignore', fs.openSync(logFile, 'w'), fs.openSync(logFile, 'w')],
    })

    // Wait for Solana to start
    for (let i = 0; i < 60; i++) {
        try {
            await axios.post(RPC, { jsonrpc: '2.0', id: 1, method: 'getVersion' }, { timeout: 5000 })
            console.log('✅ Solana test validator started')
            break
        } catch (e) {
            await sleep(1000)
            console.log('⏳ Waiting for solana to start...')
        }
    }

    return process
}

interface FeatureInfo {
    description: string
    id: string
    status: string
}

interface CachedFeaturesData {
    timestamp: string
    source: string
    totalFeatures: number
    inactiveFeatures: FeatureInfo[]
    inactiveCount: number
}

async function loadInactiveFeatures(): Promise<FeatureInfo[]> {
    const featuresFile = path.join(__dirname, '../../target/programs/features.json')

    if (!fs.existsSync(featuresFile)) {
        console.log('💡 Run: npm run generate-features')
        process.exit(1)
    }

    try {
        const cachedData: CachedFeaturesData = JSON.parse(fs.readFileSync(featuresFile, 'utf-8'))
        console.log(`✅ Loaded ${cachedData.inactiveCount} inactive features from cache`)
        return cachedData.inactiveFeatures
    } catch (error) {
        console.error('❌ Failed to read features cache:', error)
        process.exit(1)
    }
}

async function createGlobalTestContext(): Promise<TestContext> {
    const connection = new Connection(RPC, 'confirmed')
    const umi = createUmi(connection)
    const program = {
        name: 'governance',
        publicKey: GOVERNANCE_PROGRAM_ID,
        getErrorFromCode(code: number, cause?: Error) {
            return {} as any;
        },
        getErrorFromName(name: string, cause?: Error) {
            return {} as any;
        },
        isOnCluster() {
            return true
        },
    } satisfies Program

    const context: TestContext = {
        umi,
        connection,
        executor: createSignerFromKeypair(umi, umi.eddsa.generateKeypair()),
        program,
        programRepo: createDefaultProgramRepository({ rpc: umi.rpc }, [program]),
    }
    umi.payer = generateSigner(umi)

    await umi.rpc.airdrop(umi.payer.publicKey, sol(10000))

    return context
}