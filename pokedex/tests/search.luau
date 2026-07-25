local ok = require '@lib'
local pokeapi = require '../src/pokeapi'
local t = require '@vendor/t'

t.suite('PokéAPI request integration', function()
	t.test('controls the first HTTP request', function()
		local http = {
			request = function() end,
		}
		local intercept = ok.mock.intercept(http, 'request')
		local result
		local error_message

		local call = ok.mock.capture(intercept, function()
			local api = pokeapi.new { request = http.request }
			result, error_message = api.get 'gengar'
		end)

		ok.eq('https://pokeapi.co/api/v2/pokemon/gengar', call.args[1])
		ok.mock.respond(call, {
			ok = true,
			status = 200,
			headers = {},
			body = 'not json',
		})
		ok.mock.restore(intercept)

		ok.isNil(result)
		ok.eq('invalid_response', error_message)
	end)

	t.test('loads a Pokémon through the complete request sequence', function()
		local http = {
			request = function() end,
		}
		local stub = ok.mock.stub(http, 'request')
		local spy = ok.mock.spy(http, 'request')

		ok.mock.returnsOnce(stub, {
			ok = true,
			status = 200,
			body = [[{
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
				"species": { "url": "https://example.test/species/94" }
			}]],
		})

		ok.mock.returnsOnce(stub, {
			ok = true,
			status = 200,
			body = [[{
				"evolution_chain": { "url": "https://example.test/evolution/94" }
			}]],
		})

		ok.mock.returnsOnce(stub, {
			ok = true,
			status = 200,
			body = [[{
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
			}]],
		})

		local api = pokeapi.new { request = http.request }
		local result, error_message = api.get 'gengar'
		local cached_result, cached_error = api.get 'gengar'
		ok.mock.restore(spy)
		ok.mock.restore(stub)

		ok.isNil(error_message)
		ok.isNil(cached_error)
		ok.deepEq(cached_result, result)
		ok.calledTimes(spy, 3)
		ok.deepEq(result and {
			id = result.id,
			name = result.name,
			evolutions = result.evolutions,
		}, {
			id = 94,
			name = 'Gengar',
			evolutions = { { 'gastly', 'haunter', 'gengar' } },
		})
	end)
end)
