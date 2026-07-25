local client = require '@lute/net/client'
local fs = require '@std/fs'
local ok = require '@lib'
local process = require '@std/process'
local t = require '@vendor/t'

local sprite = {}

local width = 44
local height = 20
local cache_directory = `{tostring(process.cwd())}\\pokedex\\.cache`
local cache_path = `{cache_directory}\\sprite.png`

local function fixed_height(output: string): string
	local lines = output:split '\n'
	if lines[#lines] == '' then table.remove(lines) end

	while #lines < height do
		table.insert(lines, '')
	end

	while #lines > height do
		table.remove(lines)
	end

	return table.concat(lines, '\n')
end

function sprite.render(url: string): string?
	local requested, response = pcall(function()
		return client.request(url, {})
	end)
	if not requested or type(response) ~= 'table' then return nil end
	if response.ok ~= true or type(response.body) ~= 'string' then
		return nil
	end

	fs.createDirectory(cache_directory, { makeParents = true })
	fs.writeStringToFile(cache_path, response.body)

	local ran, result = pcall(function()
		return process.run({
			'chafa',
			'--format=symbols',
			`--size={width}x{height}`,
			'--work=9',
			'--symbols=block+braille',
			'--colors=full',
			cache_path,
		}, {})
	end)
	if not ran or result.ok ~= true then return nil end

	return fixed_height(result.stdout)
end

function sprite.blank(): string
	return ('\n'):rep(height - 1)
end

t.suite('sprite.blank', function()
	t.test('reserves the sprite height', function()
		local lines = sprite.blank():split '\n'
		ok.eq(height, #lines)
	end)
end)

return sprite
