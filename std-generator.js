const fs = require('fs')
const path = require('path')
const glob = require('glob')

const outputDir = 'standard-input-jsons'
if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir)
    console.log(`Created output directory: ${outputDir}`)
}

const buildInfoDir = 'artifacts/build-info'
const buildFile = fs
    .readdirSync(buildInfoDir)
    .sort(
        (a, b) =>
            fs.statSync(path.join(buildInfoDir, b)).mtime.getTime() -
            fs.statSync(path.join(buildInfoDir, a)).mtime.getTime()
    )[0]

const buildInfo = require('./' + path.join(buildInfoDir, buildFile))
const { input, output } = buildInfo

const sourceFiles = glob.sync('contracts/**/*.sol')

for (const sourcePath of sourceFiles) {
    const compiledContracts = output.contracts[sourcePath]
    if (!compiledContracts) {
        console.warn(`No compiled contracts found for ${sourcePath}. Please run 'npx hardhat compile' first.`)
        continue
    }

    const usedSources = new Set()

    for (const contractName of Object.keys(compiledContracts)) {
        const metadata = JSON.parse(compiledContracts[contractName].metadata)
        for (const sourceFile of Object.keys(metadata.sources)) {
            usedSources.add(sourceFile)
        }
    }

    const minimalInput = {
        ...input,
        sources: Object.fromEntries(Object.entries(input.sources).filter(([fileName]) => usedSources.has(fileName))),
    }

    const baseName = path.basename(sourcePath, '.sol')
    const outPath = path.join(outputDir, `standard-input-${baseName}.json`)

    fs.writeFileSync(outPath, JSON.stringify(minimalInput, null, 2))
    console.log(`${outPath} written for ${sourcePath}`)
}