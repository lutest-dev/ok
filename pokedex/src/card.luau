local ok = require '@lib'
local t = require '@vendor/t'
local tint = require '@vendor/tint'
local types = require './types'

type Pokemon = types.Pokemon

local width = 36

type Paint = (string) -> string

local function paint(style: any): Paint
	return function(value)
		return style(value)
	end
end

local border = paint(tint.hex '#5C5C5C')
local surface = paint(tint.bg_hex '#262626')
local text = paint(tint.hex '#F8F7FF')
local muted = paint(tint.hex '#B8ADC9')
local highlight = paint(tint.hex '#FFD166')
local error_text = paint(tint.hex '#FF7A90')
local hp_text = paint(tint.hex '#FF8FA3')
local attack_text = paint(tint.hex '#FFAE8A')
local defense_text = paint(tint.hex '#9DC3FF')
local special_attack_text = paint(tint.hex '#F4A7E8')
local special_defense_text = paint(tint.hex '#99E7F5')
local speed_text = paint(tint.hex '#FFE08A')

type Segment = {
	text: string,
	paint: Paint,
}

local type_colors: { [string]: { foreground: Paint, background: Paint } } = {
	normal = {
		foreground = paint(tint.hex '#E5E7EB'),
		background = paint(tint.bg_hex '#34313D'),
	},
	fighting = {
		foreground = paint(tint.hex '#FF9A8E'),
		background = paint(tint.bg_hex '#542A2A'),
	},
	flying = {
		foreground = paint(tint.hex '#B8C7FF'),
		background = paint(tint.bg_hex '#303752'),
	},
	ghost = {
		foreground = paint(tint.hex '#C4B5FD'),
		background = paint(tint.bg_hex '#3A2D55'),
	},
	poison = {
		foreground = paint(tint.hex '#E9A8F5'),
		background = paint(tint.bg_hex '#4B2856'),
	},
	ground = {
		foreground = paint(tint.hex '#E8C38D'),
		background = paint(tint.bg_hex '#4A3820'),
	},
	rock = {
		foreground = paint(tint.hex '#E7CD90'),
		background = paint(tint.bg_hex '#4B3F20'),
	},
	bug = {
		foreground = paint(tint.hex '#C8E88C'),
		background = paint(tint.bg_hex '#354622'),
	},
	steel = {
		foreground = paint(tint.hex '#C5D0E0'),
		background = paint(tint.bg_hex '#313B4A'),
	},
	electric = {
		foreground = paint(tint.hex '#FFE08A'),
		background = paint(tint.bg_hex '#4D3D16'),
	},
	fire = {
		foreground = paint(tint.hex '#FFAE8A'),
		background = paint(tint.bg_hex '#512A24'),
	},
	water = {
		foreground = paint(tint.hex '#9DC3FF'),
		background = paint(tint.bg_hex '#24385A'),
	},
	grass = {
		foreground = paint(tint.hex '#A7E89B'),
		background = paint(tint.bg_hex '#284A31'),
	},
	psychic = {
		foreground = paint(tint.hex '#FF9FB8'),
		background = paint(tint.bg_hex '#552839'),
	},
	ice = {
		foreground = paint(tint.hex '#99E7F5'),
		background = paint(tint.bg_hex '#254653'),
	},
	dragon = {
		foreground = paint(tint.hex '#B8A3FF'),
		background = paint(tint.bg_hex '#3D2D65'),
	},
	dark = {
		foreground = paint(tint.hex '#C8B5A2'),
		background = paint(tint.bg_hex '#39322E'),
	},
	fairy = {
		foreground = paint(tint.hex '#F4B3E5'),
		background = paint(tint.bg_hex '#513049'),
	},
}

local card = {} :: {
	render: (
		state: {
			pokemon: Pokemon?,
			status: string?,
			shiny: boolean?,
		}
	) -> string,
}

local function title_case(text_value: string): string
	return text_value:sub(1, 1):upper() .. text_value:sub(2)
end

local function type_text(types: { string }): string
	local labels: { string } = {}
	for _, type_name in types do
		table.insert(labels, ` {title_case(type_name)} `)
	end

	return table.concat(labels, ' ')
end

local function evolution_text(path: { string }): string
	local names: { string } = {}
	for _, name in path do
		table.insert(names, title_case(name:gsub('-', ' ')))
	end

	return table.concat(names, ' → ')
end

local function stats_texts(pokemon: Pokemon): (string, string)
	return `HP {pokemon.stats.hp}  ATK {pokemon.stats.attack}  DEF {pokemon.stats.defense}`,
		`SpA {pokemon.stats.special_attack}  SpD {pokemon.stats.special_defense}  SPE {pokemon.stats.speed}`
end

local function card_inner_width(
	pokemon: Pokemon?,
	status: string?,
	shiny: boolean?
): number
	local inner_width = width - 2
	local function fit(text_value: string)
		inner_width = math.max(inner_width, utf8.len(text_value) or 0)
	end

	if pokemon == nil then
		fit 'Pokédex'
		fit 'Search for a Pokémon'
		if status then fit(status) end
		return inner_width
	end

	fit(
		('#%03d %s%s'):format(
			pokemon.id,
			pokemon.name,
			if shiny then ' Shiny' else ''
		)
	)
	fit(type_text(pokemon.types))
	fit(`Height: {pokemon.height} m`)
	fit(`Weight: {pokemon.weight} kg`)
	fit(`Abilities: {table.concat(pokemon.abilities, ', ')}`)
	fit 'Evolution'
	for _, path in pokemon.evolutions do
		fit(evolution_text(path))
	end
	local first_stats, second_stats = stats_texts(pokemon)
	fit(first_stats)
	fit(second_stats)

	return inner_width
end

local function row(
	segments: { Segment },
	inner_width: number,
	centered: boolean?
): string
	local visible = 0
	local styled: { string } = {}

	for _, segment in segments do
		visible += utf8.len(segment.text) or 0
		table.insert(styled, surface(segment.paint(segment.text)))
	end

	local padding = math.max(0, inner_width - visible)
	local left_padding = if centered then math.floor(padding / 2) else 0
	local right_padding = padding - left_padding
	return border '│'
		.. surface((' '):rep(left_padding))
		.. table.concat(styled)
		.. surface((' '):rep(right_padding))
		.. border '│'
end

local function type_chip(type_name: string): Segment
	local colors = type_colors[type_name]
	local label = ` {title_case(type_name)} `

	if colors == nil then return {
		text = label,
		paint = muted,
	} end

	return {
		text = label,
		paint = function(value)
			return colors.background(colors.foreground(value))
		end,
	}
end

local function stat_segment(label: string, value: number, color: Paint): Segment
	return {
		text = `{label} {value}`,
		paint = color,
	}
end

local function header_segments(
	pokemon: Pokemon?,
	shiny: boolean?
): ({ Segment }, { Segment })
	if pokemon == nil then
		return {
			{ text = 'Pokédex', paint = paint(tint.hex('#F8F7FF').bold) },
		}, {
			{ text = 'Search for a Pokémon', paint = muted },
		}
	end

	local type_segments: { Segment } = {}
	for index, type_name in pokemon.types do
		if index > 1 then
			table.insert(type_segments, { text = ' ', paint = text })
		end
		table.insert(type_segments, type_chip(type_name))
	end

	local title_segments: { Segment } = {
		{ text = ('#%03d '):format(pokemon.id), paint = highlight },
		{
			text = pokemon.name,
			paint = paint(tint.hex('#F8F7FF').bold),
		},
	}
	if shiny then
		table.insert(title_segments, { text = ' Shiny', paint = highlight })
	end

	return title_segments, type_segments
end

local function status_paint(status: string): Paint
	if status:find('not found', 1, true) then return error_text end
	if status == 'Request failed' or status == 'Invalid response' then
		return error_text
	end

	return muted
end

local function add_evolutions(
	lines: { string },
	evolutions: { { string } },
	inner_width: number
)
	if #evolutions == 0 then return end

	table.insert(lines, row({}, inner_width))
	table.insert(
		lines,
		row({ { text = 'Evolution', paint = highlight } }, inner_width)
	)
	for _, path in evolutions do
		table.insert(
			lines,
			row({
				{
					text = evolution_text(path),
					paint = muted,
				},
			}, inner_width)
		)
	end
end

local function add_stats(
	lines: { string },
	pokemon: Pokemon,
	inner_width: number
)
	table.insert(lines, row({}, inner_width))
	table.insert(
		lines,
		row({
			stat_segment('HP', pokemon.stats.hp, hp_text),
			{ text = '  ', paint = muted },
			stat_segment('ATK', pokemon.stats.attack, attack_text),
			{ text = '  ', paint = muted },
			stat_segment('DEF', pokemon.stats.defense, defense_text),
		}, inner_width, true)
	)
	table.insert(
		lines,
		row({
			stat_segment(
				'SpA',
				pokemon.stats.special_attack,
				special_attack_text
			),
			{ text = '  ', paint = muted },
			stat_segment(
				'SpD',
				pokemon.stats.special_defense,
				special_defense_text
			),
			{ text = '  ', paint = muted },
			stat_segment('SPE', pokemon.stats.speed, speed_text),
		}, inner_width, true)
	)
end

local function add_pokemon_details(
	lines: { string },
	pokemon: Pokemon,
	inner_width: number
)
	table.insert(
		lines,
		row({
			{ text = `Height: {pokemon.height} m`, paint = muted },
		}, inner_width)
	)
	table.insert(
		lines,
		row({
			{ text = `Weight: {pokemon.weight} kg`, paint = muted },
		}, inner_width)
	)
	table.insert(
		lines,
		row({
			{
				text = `Abilities: {table.concat(pokemon.abilities, ', ')}`,
				paint = muted,
			},
		}, inner_width)
	)
	add_evolutions(lines, pokemon.evolutions, inner_width)
	add_stats(lines, pokemon, inner_width)
end

function card.render(state): string
	local inner_width =
		card_inner_width(state.pokemon, state.status, state.shiny)
	local title_segments, type_segments =
		header_segments(state.pokemon, state.shiny)

	local lines = {
		border('┌' .. ('─'):rep(inner_width) .. '┐'),
		row(title_segments, inner_width),
		row(type_segments, inner_width),
	}

	if state.pokemon == nil then
		local status = state.status
		local footer = if status
			then {
				text = status,
				paint = status_paint(status),
			}
			else { text = 'Search for a Pokémon', paint = muted }
		table.insert(lines, row({}, inner_width))
		table.insert(lines, row({ footer }, inner_width))
	else
		add_pokemon_details(lines, state.pokemon, inner_width)
	end

	table.insert(lines, border('└' .. ('─'):rep(inner_width) .. '┘'))
	return table.concat(lines, '\n')
end

local function strip_ansi(value: string): string
	local plain = value:gsub('\27%[[%d;]*m', '')
	return plain
end

t.suite('card.render', function()
	t.test('renders a fixed card', function()
		local rendered = strip_ansi(card.render {
			pokemon = {
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
			},
			shiny = true,
		})

		ok.strContains(rendered, '#094 Gengar')
		ok.strContains(rendered, 'Shiny')
		ok.strContains(rendered, 'Ghost')
		ok.strContains(rendered, 'Poison')
		ok.strContains(rendered, 'Height: 1.5 m')
		ok.strContains(rendered, 'Weight: 40.5 kg')
		ok.strContains(rendered, 'Abilities: Cursed body')
		ok.strContains(rendered, 'HP 60  ATK 65  DEF 60')
		ok.strContains(rendered, 'Gastly → Haunter → Gengar')

		for line in rendered:gmatch '[^\n]+' do
			ok.eq(utf8.len(line), width)
		end
	end)

	t.test('renders a fixed error card', function()
		local rendered = strip_ansi(card.render {
			pokemon = nil,
			status = 'Pokémon not found',
		})

		ok.strContains(rendered, 'Pokémon not found')
		for line in rendered:gmatch '[^\n]+' do
			ok.eq(utf8.len(line), width)
		end
	end)

	t.test('expands to fit an evolution path', function()
		local rendered = strip_ansi(card.render {
			pokemon = {
				id = 10034,
				name = 'Charizard-mega-x',
				types = { 'fire', 'dragon' },
				height = 1.7,
				weight = 110.5,
				abilities = { 'Tough claws' },
				stats = {
					hp = 78,
					attack = 130,
					defense = 111,
					special_attack = 130,
					special_defense = 85,
					speed = 100,
				},
				evolutions = { { 'charmander', 'charmeleon', 'charizard' } },
			},
		})

		ok.strContains(rendered, 'Charmander → Charmeleon → Charizard')
		local card_width: number? = nil
		for line in rendered:gmatch '[^\n]+' do
			card_width = card_width or utf8.len(line)
			ok.eq(card_width, (utf8.len(line)))
		end
		ok.that((card_width or 0) > width)
	end)

	t.test('expands to fit every ability', function()
		local rendered = strip_ansi(card.render {
			pokemon = {
				id = 133,
				name = 'Eevee',
				types = { 'normal' },
				height = 0.3,
				weight = 6.5,
				abilities = { 'Run away', 'Adaptability', 'Anticipation' },
				stats = {
					hp = 55,
					attack = 55,
					defense = 50,
					special_attack = 45,
					special_defense = 65,
					speed = 55,
				},
				evolutions = { { 'eevee', 'vaporeon' } },
			},
		})

		ok.strContains(
			rendered,
			'Abilities: Run away, Adaptability, Anticipation'
		)
	end)
end)

return card
