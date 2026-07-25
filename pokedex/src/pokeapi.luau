local json = require '@std/json'
local ok = require '@lib'
local pokemon = require './pokemon'
local t = require '@vendor/t'
local types = require './types'

type PokeApi = types.PokeApi
type PokeApiError = types.PokeApiError
type Pokemon = types.Pokemon
type Request = types.Request

local pokeapi = {} :: {
	new: (deps: { request: Request }) -> PokeApi,
}

local parse_evolution_paths: (node: any) -> { { string } }?

local function prepend(name: string, path: { string }): { string }
	local result = { name }
	for _, value in path do
		table.insert(result, value)
	end

	return result
end

local function add_child_paths(
	paths: { { string } },
	name: string,
	child: any
): boolean
	local child_paths = parse_evolution_paths(child)
	if child_paths == nil then return false end

	for _, path in child_paths do
		table.insert(paths, prepend(name, path))
	end

	return true
end

parse_evolution_paths = function(node: any): { { string } }?
	if type(node) ~= 'table' then return nil end
	if type(node.species) ~= 'table' or type(node.species.name) ~= 'string' then
		return nil
	end
	if type(node.evolves_to) ~= 'table' then return nil end

	if #node.evolves_to == 0 then return { { node.species.name } } end

	local paths = {}
	for _, child in node.evolves_to do
		if not add_child_paths(paths, node.species.name, child) then
			return nil
		end
	end

	return paths
end

function pokeapi.new(deps: { request: Request }): PokeApi
	local request = deps.request
	local cache: { [string]: Pokemon } = {}

	local function request_json(url: string): (any?, PokeApiError?)
		local succeeded, response = pcall(request, url)
		if not succeeded or type(response) ~= 'table' then
			return nil, 'request_failed'
		end

		if response.status == 404 then return nil, 'not_found' end
		if response.ok ~= true or type(response.body) ~= 'string' then
			return nil, 'request_failed'
		end

		local decoded_success, decoded = pcall(json.deserialize, response.body)
		if not decoded_success then return nil, 'invalid_response' end

		return decoded, nil
	end

	local function get(name: string): (Pokemon?, PokeApiError?)
		local cached = cache[name]
		if cached ~= nil then return cached, nil end

		local decoded, request_error =
			request_json(`https://pokeapi.co/api/v2/pokemon/{name}`)
		if decoded == nil then return nil, request_error end

		local result = pokemon.parse(decoded)
		if result == nil then return nil, 'invalid_response' end
		if
			type(decoded.species) ~= 'table'
			or type(decoded.species.url) ~= 'string'
		then
			return nil, 'invalid_response'
		end

		local species, species_error = request_json(decoded.species.url)
		if species == nil then return nil, species_error end
		if
			type(species.evolution_chain) ~= 'table'
			or type(species.evolution_chain.url) ~= 'string'
		then
			return nil, 'invalid_response'
		end

		local evolution_chain, chain_error =
			request_json(species.evolution_chain.url)
		if evolution_chain == nil then return nil, chain_error end
		local evolutions = parse_evolution_paths(evolution_chain.chain)
		if evolutions == nil then return nil, 'invalid_response' end

		result.evolutions = evolutions
		cache[name] = result

		return result, nil
	end

	return { get = get }
end

t.suite('pokeapi', function()
	t.test('returns a Pokémon', function()
		local api = pokeapi.new {
			request = function(url)
				local body = if url:find('/pokemon/gengar', 1, true)
					then [[{
				"id": 94,
				"name": "gengar",
				"height": 15,
				"weight": 405,
				"types": [
					{ "slot": 1, "type": { "name": "ghost" } },
					{ "slot": 2, "type": { "name": "poison" } }
				],
				"abilities": [{ "ability": { "name": "cursed-body" } }],
				"stats": [
					{ "base_stat": 60, "stat": { "name": "hp" } },
					{ "base_stat": 65, "stat": { "name": "attack" } },
					{ "base_stat": 60, "stat": { "name": "defense" } },
					{ "base_stat": 130, "stat": { "name": "special-attack" } },
					{ "base_stat": 75, "stat": { "name": "special-defense" } },
					{ "base_stat": 110, "stat": { "name": "speed" } }
				],
				"sprites": {
					"front_default": "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/94.png"
				},
				"species": { "url": "https://example.test/species/94" }
			}]]
					elseif url == 'https://example.test/species/94' then [[{
				"evolution_chain": { "url": "https://example.test/evolution/94" }
			}]]
					else [[{
				"chain": {
					"species": { "name": "gastly" },
					"evolves_to": [{
						"species": { "name": "haunter" },
						"evolves_to": [{
							"species": { "name": "gengar" },
							"evolves_to": []
						}]
					}]
				}
			}]]

				return { ok = true, status = 200, body = body }
			end,
		}

		local result, error_message = api.get 'gengar'

		ok.isNil(error_message)
		ok.deepEq(result, {
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
		})
	end)

	t.test('maps HTTP and response failures to public errors', function()
		local not_found = pokeapi.new {
			request = function()
				return { ok = false, status = 404 }
			end,
		}
		local failed_request = pokeapi.new {
			request = function()
				error 'offline'
			end,
		}
		local invalid_response = pokeapi.new {
			request = function()
				return { ok = true, status = 200, body = 'not json' }
			end,
		}

		local missing, missing_error = not_found.get 'missingno'
		local failed, failed_error = failed_request.get 'gengar'
		local invalid, invalid_error = invalid_response.get 'gengar'

		ok.isNil(missing)
		ok.eq('not_found', missing_error)
		ok.isNil(failed)
		ok.eq('request_failed', failed_error)
		ok.isNil(invalid)
		ok.eq('invalid_response', invalid_error)
	end)

	t.test('returns every evolution path', function()
		local api = pokeapi.new {
			request = function(url)
				local body = if url:find('/pokemon/eevee', 1, true)
					then [[{
					"id": 133,
					"name": "eevee",
					"height": 3,
					"weight": 65,
					"types": [{ "slot": 1, "type": { "name": "normal" } }],
					"abilities": [{ "ability": { "name": "run-away" } }],
					"stats": [
						{ "base_stat": 55, "stat": { "name": "hp" } },
						{ "base_stat": 55, "stat": { "name": "attack" } },
						{ "base_stat": 50, "stat": { "name": "defense" } },
						{ "base_stat": 45, "stat": { "name": "special-attack" } },
						{ "base_stat": 65, "stat": { "name": "special-defense" } },
						{ "base_stat": 55, "stat": { "name": "speed" } }
					],
					"species": { "url": "https://example.test/species/133" }
				}]]
					elseif url == 'https://example.test/species/133' then [[{
					"evolution_chain": { "url": "https://example.test/evolution/133" }
				}]]
					else [[{
					"chain": {
						"species": { "name": "eevee" },
						"evolves_to": [
							{ "species": { "name": "vaporeon" }, "evolves_to": [] },
							{ "species": { "name": "jolteon" }, "evolves_to": [] },
							{ "species": { "name": "flareon" }, "evolves_to": [] }
						]
					}
				}]]

				return { ok = true, status = 200, body = body }
			end,
		}

		local result, error_message = api.get 'eevee'

		ok.isNil(error_message)
		ok.deepEq(result and result.evolutions, {
			{ 'eevee', 'vaporeon' },
			{ 'eevee', 'jolteon' },
			{ 'eevee', 'flareon' },
		})
	end)
end)

return pokeapi
