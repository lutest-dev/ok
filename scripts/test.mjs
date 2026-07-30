import { spawnSync } from 'node:child_process'

const testFiles = [
	'src/init.luau',
	'tests/init.luau',
	'pokedex/src/card.luau',
	'pokedex/src/pokemon.luau',
	'pokedex/src/pokeapi.luau',
	'pokedex/src/search.luau',
	'pokedex/src/sprite.luau',
	'pokedex/tests/search.luau',
]

const command = process.platform === 'win32' ? 'powershell.exe' : 'lutest'
const arguments_ = process.platform === 'win32'
	? ['-NoProfile', '-Command', `& lutest test ${testFiles.join(' ')}`]
	: ['test', ...testFiles]
const result = spawnSync(command, arguments_, { stdio: 'inherit' })

if (result.error) throw result.error
process.exit(result.status ?? 1)
