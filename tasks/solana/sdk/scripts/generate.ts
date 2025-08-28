import { readFileSync } from 'node:fs'
import path from 'path'

import { rootNodeFromAnchor } from '@kinobi-so/nodes-from-anchor'
import { renderVisitor } from '@kinobi-so/renderers-js-umi'
import { createFromRoot } from 'kinobi'

async function generateTypeScriptSDK(): Promise<void> {
    // 302
    {
        // Instantiate Kinobi.
        const anchorIdlPath = path.join(__dirname, '../../../../target/idl', 'oft.json')
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const anchorIdl = JSON.parse(readFileSync(anchorIdlPath, 'utf-8'))

        // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
        const kinobi = createFromRoot(rootNodeFromAnchor(anchorIdl))
        const jsDir = path.join(__dirname, '../generated/oft302')
        // eslint-disable-next-line @typescript-eslint/no-unsafe-argument, @typescript-eslint/no-unsafe-call
        void kinobi.accept(renderVisitor(jsDir))
    }

    return Promise.resolve()
}

;(async (): Promise<void> => {
    await generateTypeScriptSDK()
})().catch((err: unknown) => {
    console.error(err)
    process.exit(1)
})
