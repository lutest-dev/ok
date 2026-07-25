local ok = require '@lib'
local t = require '@vendor/t'
local types = require './types'

type Pokemon = types.Pokemon
type Stats = types.Stats

local pokemon = {} :: {
	parse: (data: any) -> Pokemon?,
}

local function format_name(name: string): string
	return name:sub(1, 1):upper() .. name:sub(2)
end

function pokemon.parse(data: any): Pokemon?
	if type(data) ~= 'table' then return nil end

	local id = data.id
	local name = data.name
	local height = data.height
	local weight = data.weight
	local raw_types = data.types
	local raw_abilities = data.abilities
	local raw_stats = data.stats

	if type(id) ~= 'number' then return nil end
	if type(name) ~= 'string' or #name == 0 then return nil end
	if type(height) ~= 'number' then return nil end
	if type(weight) ~= 'number' then return nil end
	if type(raw_types) ~= 'table' then return nil end
	if type(raw_abilities) ~= 'table' then return nil end
	if type(raw_stats) ~= 'table' then return nil end

	local parsed_types: { string } = {}
	for _, slot in raw_types do
		if type(slot) ~= 'table' then return nil end
		if type(slot.type) ~= 'table' or type(slot.type.name) ~= 'string' then
			return nil
		end

		table.insert(parsed_types, slot.type.name)
	end

	if #parsed_types == 0 then return nil end

	local abilities: { string } = {}
	for _, slot in raw_abilities do
		if type(slot) ~= 'table' then return nil end
		if
			type(slot.ability) ~= 'table'
			or type(slot.ability.name) ~= 'string'
		then
			return nil
		end

		table.insert(abilities, format_name(slot.ability.name:gsub('-', ' ')))
	end
	if #abilities == 0 then return nil end

	local stats: Stats = {
		hp = 0,
		attack = 0,
		defense = 0,
		special_attack = 0,
		special_defense = 0,
		speed = 0,
	}
	for _, slot in raw_stats do
		if type(slot) ~= 'table' or type(slot.base_stat) ~= 'number' then
			return nil
		end
		if type(slot.stat) ~= 'table' or type(slot.stat.name) ~= 'string' then
			return nil
		end

		local stat_name = slot.stat.name:gsub('-', '_')
		if stat_name == 'hp' then
			stats.hp = slot.base_stat
		elseif stat_name == 'attack' then
			stats.attack = slot.base_stat
		elseif stat_name == 'defense' then
			stats.defense = slot.base_stat
		elseif stat_name == 'special_attack' then
			stats.special_attack = slot.base_stat
		elseif stat_name == 'special_defense' then
			stats.special_defense = slot.base_stat
		elseif stat_name == 'speed' then
			stats.speed = slot.base_stat
		else
			return nil
		end
	end
	if
		stats.hp == 0
		or stats.attack == 0
		or stats.defense == 0
		or stats.special_attack == 0
		or stats.special_defense == 0
		or stats.speed == 0
	then
		return nil
	end

	local sprite_url: string? = nil
	local shiny_sprite_url: string? = nil
	if
		type(data.sprites) == 'table'
		and type(data.sprites.front_default) == 'string'
	then
		sprite_url = data.sprites.front_default
	end
	if
		type(data.sprites) == 'table'
		and type(data.sprites.front_shiny) == 'string'
	then
		shiny_sprite_url = data.sprites.front_shiny
	end

	local result: Pokemon = {
		id = id,
		name = format_name(name),
		types = parsed_types,
		height = height / 10,
		weight = weight / 10,
		abilities = abilities,
		stats = stats,
		evolutions = {},
		sprite_url = sprite_url,
		shiny_sprite_url = shiny_sprite_url,
	}

	return result
end

t.suite('pokemon.parse', function()
	t.test('converts a PokéAPI response into a Pokémon', function()
		local result = pokemon.parse {
			id = 94,
			name = 'gengar',
			height = 15,
			weight = 405,
			types = {
				{ slot = 1, type = { name = 'ghost' } },
				{ slot = 2, type = { name = 'poison' } },
			},
			abilities = {
				{ ability = { name = 'cursed-body' } },
			},
			stats = {
				{ base_stat = 60, stat = { name = 'hp' } },
				{ base_stat = 65, stat = { name = 'attack' } },
				{ base_stat = 60, stat = { name = 'defense' } },
				{ base_stat = 130, stat = { name = 'special-attack' } },
				{ base_stat = 75, stat = { name = 'special-defense' } },
				{ base_stat = 110, stat = { name = 'speed' } },
			},
			sprites = {
				front_default = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/94.png',
				front_shiny = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/94.png',
			},
		}

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
			evolutions = {},
			sprite_url = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/94.png',
			shiny_sprite_url = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/94.png',
		})
	end)
end)

return pokemon
