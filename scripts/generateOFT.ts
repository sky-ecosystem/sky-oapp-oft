import { writeFile } from 'fs/promises'
import * as path from 'path'

import { Solita } from '@metaplex-foundation/solita'

async function generateTypeScriptSDK() {
    const generatedIdlDir = path.join(__dirname, '../target/', 'idl')
    const address = process.env.OFT_PROGRAM_ID
    const generatedSDKDir = path.join(__dirname, '..', 'src', 'generated', 'oft')
    const idl = require('../target/idl/oft.json')
    if (idl.metadata?.address == null) {
        idl.metadata = { ...idl.metadata, address }
        await writeFile(generatedIdlDir + '/oft.json', JSON.stringify(idl, null, 2))
    }
    const gen = new Solita(idl, { formatCode: true })
    await gen.renderAndWriteTo(generatedSDKDir)
}

;(async () => {
    await generateTypeScriptSDK()
})()