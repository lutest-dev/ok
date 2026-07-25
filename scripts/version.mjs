import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'

const changeset = process.platform === 'win32' ? 'changeset.cmd' : 'changeset'
execFileSync(changeset, ['version'], { stdio: 'inherit' })

const { version } = JSON.parse(readFileSync('package.json', 'utf8'))

for (const path of ['wally.toml', 'pesde.toml']) {
	const contents = readFileSync(path, 'utf8')
	const updated = contents.replace(
		/^version = "[^"]+"$/m,
		`version = "${version}"`,
	)

	if (updated === contents) {
		throw new Error(`Could not update the version in ${path}`)
	}

	writeFileSync(path, updated)
}
