local card = require '@self/card'
local client = require '@lute/net/client'
local io = require '@std/io'
local pokeapi = require '@self/pokeapi'
local search = require '@self/search'
local sprite = require '@self/sprite'
local task = require '@std/task'
local tint = require '@vendor/tint'
local types = require '@self/types'

type Pokemon = types.Pokemon
type SearchError = types.SearchError

local api = pokeapi.new {
	request = function(url)
		return client.request(url, {})
	end,
}

local finder = search.new {
	get = function(name)
		return api.get(name)
	end,
}

local function error_status(error_message: SearchError): string
	if error_message == 'not_found' then return 'Pokémon not found' end
	if error_message == 'request_failed' then return 'Request failed' end
	if error_message == 'invalid_response' then return 'Invalid response' end
	return 'Invalid query'
end

local function lookup(query: string): (Pokemon?, SearchError?)
	local complete = false
	local result: Pokemon? = nil
	local error_message: SearchError? = nil

	finder.query(query, function(next_result, next_error)
		result = next_result
		error_message = next_error
		complete = true
	end)

	while not complete do
		task.wait()
	end

	return result, error_message
end

local function sprite_url_for(pokemon: Pokemon, shiny: boolean): string?
	if shiny and pokemon.shiny_sprite_url then
		return pokemon.shiny_sprite_url
	end
	return pokemon.sprite_url
end

local function parse_search(text: string): (string, boolean)
	local query = text:gsub('^%s+', ''):gsub('%s+$', '')
	local name, matches = query:gsub('^%-%-shiny%s+', '')
	return name, matches > 0
end

local function render(query: string, previous_sprite: string?): string?
	local name, shiny = parse_search(query)
	local pokemon, error_message = lookup(name)
	local sprite_url = if pokemon then sprite_url_for(pokemon, shiny) else nil
	local rendered_sprite = if sprite_url
		then sprite.render(sprite_url)
		else previous_sprite

	io.write '\n'
	io.write(rendered_sprite or sprite.blank())
	io.write '\n'
	io.write(card.render {
		pokemon = pokemon,
		status = if error_message then error_status(error_message) else nil,
		shiny = shiny and pokemon ~= nil,
	})
	io.write '\n'

	if pokemon then return rendered_sprite end
	return previous_sprite
end

local function is_exit(query: string): boolean
	local normalized = query:lower():gsub('^%s+', ''):gsub('%s+$', '')
	return normalized == 'exit'
end

local previous_sprite: string? = nil
while true do
	local query = io.input('\n' .. tint.hex('#EF5350').bold 'Search: ')
	if is_exit(query) then break end
	previous_sprite = render(query, previous_sprite)
end
