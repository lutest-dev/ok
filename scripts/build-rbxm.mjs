import { mkdirSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

mkdirSync('dist', { recursive: true })

const result = spawnSync(
	'rojo',
	['build', 'default.project.json', '--output', 'dist/ok.rbxm'],
	{ stdio: 'inherit' },
)

if (result.error) throw result.error
process.exit(result.status ?? 1)
