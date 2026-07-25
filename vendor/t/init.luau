local types = require '@vendor/t/types'
local registry = require '@vendor/t/registry'
local context = require '@vendor/t/context'

export type TestSpec = types.TestSpec
export type TestMode = types.TestMode
export type HookFn = types.HookFn
export type SuiteHooks = types.SuiteHooks
export type TestScope = types.TestScope

local active_scope = nil :: TestScope?

local function is_collecting(): boolean
	return context.get_register() ~= nil or registry.is_active()
end

local function scope_or_error(): TestScope
	local scope = active_scope
	if scope ~= nil then return scope end

	error('Hooks can only be registered inside t.suite().', 2)
end

local function register_spec(spec: TestSpec)
	if not is_collecting() then return end
	if context.register(spec) then return end

	registry.register(spec)
end

local function test(name: string, fn: () -> ()): TestSpec
	local spec = {
		name = name,
		mode = 'run',
		fn = fn,
		scope = active_scope,
	}

	register_spec(spec)
	return spec
end

local function skip(name: string, fn: () -> ()): TestSpec
	local spec = {
		name = name,
		mode = 'skip',
		fn = fn,
		scope = active_scope,
	}

	register_spec(spec)
	return spec
end

local function only(name: string, fn: () -> ()): TestSpec
	local spec = {
		name = name,
		mode = 'only',
		fn = fn,
		scope = active_scope,
	}

	register_spec(spec)
	return spec
end

local function todo(name: string): TestSpec
	local spec = {
		name = name,
		mode = 'todo',
		scope = active_scope,
	}

	register_spec(spec)
	return spec
end

local function suite(name: string, register: () -> ())
	if not is_collecting() then return end
	if active_scope ~= nil then
		error('Nested t.suite() calls are not supported.', 2)
	end

	local scope = {
		name = name,
		hooks = {
			before_all = {},
			before_each = {},
			after_each = {},
			after_all = {},
		},
	} :: TestScope

	active_scope = scope
	local ok, result = pcall(register)
	active_scope = nil
	if not ok then error(result, 0) end
end

local function before_all(hook: HookFn)
	if not is_collecting() then return end
	table.insert(scope_or_error().hooks.before_all, hook)
end

local function before_each(hook: HookFn)
	if not is_collecting() then return end
	table.insert(scope_or_error().hooks.before_each, hook)
end

local function after_each(hook: HookFn)
	if not is_collecting() then return end
	table.insert(scope_or_error().hooks.after_each, hook)
end

local function after_all(hook: HookFn)
	if not is_collecting() then return end
	table.insert(scope_or_error().hooks.after_all, hook)
end

return {
	test = test,
	skip = skip,
	only = only,
	todo = todo,
	suite = suite,
	before_all = before_all,
	before_each = before_each,
	after_each = after_each,
	after_all = after_all,
	is_running = context.is_running,
}
