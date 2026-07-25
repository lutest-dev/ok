local color_convert = require '@vendor/tint/color_convert'
local runtime = require '@vendor/tint/runtime'

local environment: { [string]: string } = runtime.env
local color_term = string.lower(environment.COLORTERM or '')
local term = string.lower(environment.TERM or '')
local disabled = environment.NO_COLOR ~= nil

local has_16m = not disabled and (
	color_term:find('truecolor', 1, true) ~= nil
	or color_term:find('24bit', 1, true) ~= nil
	or term:find('truecolor', 1, true) ~= nil
	or term:find('direct', 1, true) ~= nil
)

local has_256 = not disabled and not has_16m and term:find('256color', 1, true) ~= nil

if not disabled and not has_16m and not has_256 and runtime.is_tty then
	has_16m = true
end

local level = if disabled then 0 elseif has_16m then 3 elseif has_256 then 2 else 1

return table.freeze {
	level = level,
	has_16m = has_16m,
	has_256 = has_256,
	to_ansi256 = color_convert.to_ansi256,
	to_ansi16 = color_convert.to_ansi16,
}
