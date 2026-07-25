local ok = require '@lib'
local t = require '@vendor/t'
local task = require '@std/task'
local types = require './types'

type Get = types.Get
type Pokemon = types.Pokemon
type Search = types.Search
type Callback = types.Callback

local search = {} :: {
	new: (deps: { get: Get }) -> Search,
}

local function normalize(text: string): string
	return (text:lower():gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', '-'))
end

function search.new(deps: { get: Get }): Search
	local get = deps.get
	local latest = 0

	local function query(text: string, callback: Callback)
		latest += 1
		local version = latest
		local name = normalize(text)

		if #name == 0 then
			callback(nil, 'invalid_query')
			return
		end

		task.spawn(function()
			local result, error_message = get(name)
			if version ~= latest then return end

			callback(result, error_message)
		end)
	end

	return { query = query }
end

t.suite('search.query', function()
	t.test('returns a Pokémon to the callback', function()
		local expected: Pokemon = {
			id = 94,
			name = 'Gengar',
			types = { 'ghost', 'poison' },
			height = 1.5,
			weight = 40.5,
			abilities = { 'Cursed body' },
			stats = {
				hp = 60,
				attack = 65,
				defense = 60,
				special_attack = 130,
				special_defense = 75,
				speed = 110,
			},
			evolutions = { { 'gastly', 'haunter', 'gengar' } },
			sprite_url = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/94.png',
		}
		local received: any = nil
		local received_error: any = nil

		local finder = search.new {
			get = function()
				return expected, nil
			end,
		}

		finder.query('gengar', function(result, error_message)
			received = result
			received_error = error_message
		end)

		task.wait()

		ok.isNil(received_error)
		ok.deepEq(received, expected)
	end)

	t.test('normalizes a query and rejects an empty one', function()
		local requested_name: string? = nil
		local empty_error: any = nil
		local finder = search.new {
			get = function(name)
				requested_name = name
				return nil, 'not_found'
			end,
		}

		finder.query('  Gengar Mega  ', function() end)
		task.wait()
		finder.query('   ', function(_, error_message)
			empty_error = error_message
		end)

		ok.eq('gengar-mega', requested_name)
		ok.eq('invalid_query', empty_error)
	end)

	t.test('returns a search error to the callback', function()
		local received: Pokemon? = nil
		local received_error: any = nil
		local finder = search.new {
			get = function()
				return nil, 'not_found'
			end,
		}

		finder.query('missingno', function(result, error_message)
			received = result
			received_error = error_message
		end)
		task.wait()

		ok.isNil(received)
		ok.eq('not_found', received_error)
	end)

	t.test('ignores an older result', function()
		local received: { string } = {}
		local finder = search.new {
			get = function(name)
				if name == 'gengar' then task.wait(0.01) end
				return {
					id = 94,
					name = name,
					types = { 'ghost' },
					height = 1.5,
					weight = 40.5,
					abilities = { 'Cursed body' },
					stats = {
						hp = 60,
						attack = 65,
						defense = 60,
						special_attack = 130,
						special_defense = 75,
						speed = 110,
					},
					evolutions = {},
				},
					nil
			end,
		}

		finder.query('gengar', function(result)
			if result then table.insert(received, result.name) end
		end)
		finder.query('pikachu', function(result)
			if result then table.insert(received, result.name) end
		end)
		task.wait(0.02)

		ok.deepEq(received, { 'pikachu' })
	end)
end)

return search
