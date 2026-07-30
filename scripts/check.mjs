import { readdirSync } from 'node:fs'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'

const roots = ['src', 'tests', 'pokedex']

function collectLuauFiles(directory) {
	return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
		const path = join(directory, entry.name)
		if (entry.isDirectory()) return collectLuauFiles(path)
		return entry.name.endsWith('.luau') ? [path] : []
	})
}

const files = roots.flatMap(collectLuauFiles)
const command = process.argv[2]
const argumentsByCommand = {
	format: ['--check', ...files],
	typecheck: files,
}
const arguments_ = argumentsByCommand[command]

if (!arguments_) {
	throw new Error(
		`Expected "format" or "typecheck", got ${command ?? 'nothing'}`,
	)
}

const executable = {
	format: 'stylua',
	typecheck: 'lute',
}[command]
const result = spawnSync(executable, arguments_, { stdio: 'inherit' })

if (result.error) throw result.error
process.exit(result.status ?? 1)
