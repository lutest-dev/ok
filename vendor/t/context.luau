local types = require '@vendor/t/types'

export type TestSpec = types.TestSpec
export type RuntimeRegister = (TestSpec) -> ()

local runtime_register = nil :: RuntimeRegister?
local session_depth = 0

local function begin_session()
	session_depth += 1
end

local function end_session()
	assert(session_depth > 0, 'Cannot end an inactive Lutest session.')
	session_depth -= 1
end

local function is_running(): boolean
	return session_depth > 0
end

local function get_register(): RuntimeRegister?
	return runtime_register
end

local function set_register(register_fn: RuntimeRegister?)
	runtime_register = register_fn
end

local function clear_register()
	runtime_register = nil
end

local function register(spec: TestSpec): boolean
	local register_fn = runtime_register
	if register_fn == nil then return false end

	register_fn(spec)
	return true
end

return {
	begin_session = begin_session,
	clear_register = clear_register,
	end_session = end_session,
	get_register = get_register,
	is_running = is_running,
	register = register,
	set_register = set_register,
}
