// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'

import * as path from 'path'

import { Solita } from '@metaplex-foundation/solita'

async function generateTypeScriptSDK() {
    if (!process.env.GOVERNANCE_PROGRAM_ID) {
        throw new Error('GOVERNANCE_PROGRAM_ID is not set')
    }
    
    const generatedSDKDir = path.join(__dirname, '..', 'src', 'generated', 'governance')
    const idl = require('../target/idl/governance.json')
    idl.metadata = { ...idl.metadata, address: process.env.GOVERNANCE_PROGRAM_ID }    

    const gen = new Solita(idl, { formatCode: true })
    await gen.renderAndWriteTo(generatedSDKDir)
}

;(async () => {
    await generateTypeScriptSDK()
})()
