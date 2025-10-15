import fs from 'fs'
import path from 'path'
import { $ } from 'zx'

interface FeatureInfo {
    description: string
    id: string
    status: string
}

interface FeaturesResponse {
    features: FeatureInfo[]
}

async function generateFeatures() {
    console.log('🔍 Retrieving mainnet feature flags...')

    try {
        // Retrieve the list of inactive features from the mainnet-beta cluster
        // Try multiple RPC endpoints for reliability
        const rpcEndpoints = [
            'https://api.mainnet-beta.solana.com',
            'https://solana-rpc.publicnode.com',
            'https://rpc.ankr.com/solana',
        ]

        let features: FeaturesResponse | null = null
        let lastError: any = null

        for (const rpc of rpcEndpoints) {
            try {
                console.log(`  Trying ${rpc}...`)
                features = (await $`solana feature status -u ${rpc} --display-all --output json-compact`).json()
                break
            } catch (error) {
                lastError = error
                console.log(`  Failed with ${rpc}, trying next...`)
            }
        }

        if (!features) {
            throw lastError || new Error('All RPC endpoints failed')
        }

        // Filter only inactive features (these are the ones we need to deactivate in test validator)
        const inactiveFeatures = features.features.filter((f) => f.status === 'inactive')

        console.log(`📊 Found ${inactiveFeatures.length} inactive features`)

        // Save to target/programs/features.json
        const targetDir = path.join(__dirname, '../target/programs')
        const featuresFile = path.join(targetDir, 'features.json')

        // Ensure directory exists
        if (!fs.existsSync(targetDir)) {
            fs.mkdirSync(targetDir, { recursive: true })
        }

        // Write features data with metadata
        const featuresData = {
            timestamp: new Date().toISOString(),
            source: 'https://solana-rpc.publicnode.com',
            totalFeatures: features.features.length,
            inactiveFeatures: inactiveFeatures,
            inactiveCount: inactiveFeatures.length,
        }

        fs.writeFileSync(featuresFile, JSON.stringify(featuresData, null, 2))

        console.log(`✅ Features data saved to ${featuresFile}`)
        console.log(`📝 Cached ${inactiveFeatures.length} inactive features for faster test startup`)
    } catch (error) {
        console.error('❌ Failed to retrieve features:', error)
        process.exit(1)
    }
}

;(async (): Promise<void> => {
    await generateFeatures()
})().catch((err: unknown) => {
    console.error(err)
    process.exit(1)
})