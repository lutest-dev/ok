import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

const { version } = JSON.parse(readFileSync('package.json', 'utf8'))
mkdirSync('dist', { recursive: true })

function escapeRegex(text) {
	return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function releaseNotes(version) {
	const changelog = readFileSync('CHANGELOG.md', 'utf8')
	const heading = new RegExp(`^## ${escapeRegex(version)}\\s*$`, 'm')
	const match = heading.exec(changelog)
	if (!match) {
		throw new Error(`Could not find version ${version} in CHANGELOG.md`)
	}

	const start = match.index
	const nextVersion = changelog.indexOf('\n## ', start + match[0].length)
	return changelog.slice(start, nextVersion === -1 ? undefined : nextVersion).trim()
}

function run(command, arguments_) {
	const result = spawnSync(command, arguments_, { stdio: 'inherit' })
	if (result.error) throw result.error
	if (result.status !== 0) process.exit(result.status ?? 1)
}

const existingRelease = spawnSync('gh', ['release', 'view', `v${version}`], {
	stdio: 'ignore',
})
if (existingRelease.error) throw existingRelease.error
if (existingRelease.status === 0) {
	console.log(`v${version} is already released`)
	process.exit(0)
}

writeFileSync('dist/release-notes.md', releaseNotes(version))

const token = process.env.WALLY_AUTH_TOKEN
if (!token) throw new Error('WALLY_AUTH_TOKEN is required to publish a release')

run('rojo', ['build', 'default.project.json', '--output', 'dist/ok.rbxm'])
run('wally', ['login', '--token', token])
run('wally', ['publish'])
run('gh', [
	'release',
	'create',
	`v${version}`,
	'dist/ok.rbxm',
	'--title',
	`ok v${version}`,
	'--notes-file',
	'dist/release-notes.md',
])
