local api = { mock = {} }

export type Arguments = {
	n: number,
	[number]: any,
}

export type Call = {
	args: Arguments,
	_call: never,
}

export type SpyCall = {
	args: Arguments,
	returns: Arguments?,
	error: any?,
}

export type Spy = {
	calls: { SpyCall },
	_spy: never,
}

export type Stub = {
	_stub: never,
}

export type Intercept = {
	_intercept: never,
}

export type Mock = Spy | Stub | Intercept

type PackedValues = Arguments

local release_original = {}
local mock_marker = {}
local captured_call_marker = {}

local function pack(...: any): PackedValues
	return { n = select('#', ...), ... }
end

local function unpack_values(values: PackedValues)
	return table.unpack(values, 1, values.n)
end

local function format_value(value: any): string
	if type(value) == 'string' then return `"{value}"` end
	return tostring(value)
end

local function resume_captured_call(call: any, values: any)
	if type(call) ~= 'table' or call._marker ~= captured_call_marker then
		error('Expected a call captured by ok.mock.capture', 3)
	end
	if call._resolved then error('Expected captured call to be pending', 2) end
	call._resolved = true

	local result = pack(coroutine.resume(call._thread, unpack_values(values)))
	local intercept = call._intercept
	if not result[1] then
		intercept._capture_threads[call._thread] = nil
		error(result[2], 0)
	end
	if coroutine.status(call._thread) == 'dead' then
		intercept._capture_threads[call._thread] = nil
		return nil
	end

	local next_call = result[2]
	if
		type(next_call) ~= 'table'
		or next_call._marker ~= captured_call_marker
		or next_call._intercept ~= intercept
	then
		intercept._capture_threads[call._thread] = nil
		error('Expected captured callback to call the same intercept', 2)
	end

	return next_call
end

function api.that(condition: boolean, message: string?)
	if condition then return end
	error(message or `Expected true, got {format_value(condition)}`, 2)
end

function api.eq(expected: any, actual: any, message: string?)
	if expected == actual then return end
	error(
		message
			or `Expected {format_value(expected)}, got {format_value(actual)}`,
		2
	)
end

function api.neq(unexpected: any, actual: any, message: string?)
	if unexpected ~= actual then return end
	error(
		message
			or `Expected {format_value(unexpected)} to differ, got {format_value(
				actual
			)}`,
		2
	)
end

function api.isNil(value: any, message: string?)
	if value == nil then return end
	error(message or `Expected nil, got {format_value(value)}`, 2)
end

function api.isNotNil(value: any, message: string?)
	if value ~= nil then return end
	error(message or 'Expected a non-nil value, got nil', 2)
end

function api.strContains(
	text: string,
	substring: string,
	start_index: number?,
	message: string?
)
	if string.find(text, substring, start_index, true) ~= nil then return end
	error(
		message
			or `Expected text to contain {format_value(substring)}, got {format_value(
				text
			)}`,
		2
	)
end

function api.throws(callback: (...any) -> (), ...: any)
	local succeeded = pcall(callback, ...)
	if not succeeded then return end
	error('Expected callback to throw, but it returned successfully', 2)
end

function api.throwsWith(expected_error: any, callback: (...any) -> (), ...: any)
	local succeeded, actual_error = pcall(callback, ...)
	if not succeeded and actual_error == expected_error then return end

	if succeeded then
		error(
			`Expected callback to throw {format_value(expected_error)}, but it returned successfully`,
			2
		)
	end

	error(
		`Expected callback to throw {format_value(expected_error)}, got {format_value(
			actual_error
		)}`,
		2
	)
end

function api.called(spy: Spy, message: string?)
	if #spy.calls > 0 then return end
	error(message or 'Expected spy to be called, got no calls', 2)
end

function api.calledTimes(spy: Spy, count: number, message: string?)
	local actual_count = #spy.calls
	if actual_count == count then return end
	local call_label = if count == 1 then 'call' else 'calls'
	error(message or `Expected {count} {call_label}, got {actual_count}`, 2)
end

function api.calledWith(spy: Spy, ...: any)
	local expected_args = pack(...)

	for _, call in spy.calls do
		local args = call.args
		if args.n ~= expected_args.n then continue end

		local matches = true
		for index = 1, expected_args.n do
			if args[index] ~= expected_args[index] then
				matches = false
				break
			end
		end

		if matches then return end
	end

	error(
		'Expected spy to be called with the expected arguments, got no matching call',
		2
	)
end

function api.mock.restore(mock: Mock)
	local internal_mock = mock :: any
	if
		type(internal_mock) ~= 'table'
		or internal_mock._marker ~= mock_marker
	then
		error('Expected a mock created by ok.mock', 2)
	end
	if not internal_mock._active then error('Expected mock to be active', 2) end
	if
		internal_mock._pending_calls ~= nil
		and internal_mock._pending_calls > 0
	then
		error('Expected intercept to have no pending calls', 2)
	end
	if
		internal_mock._target[internal_mock._field_name]
		~= internal_mock._replacement
	then
		error('Expected mocks to be restored in reverse creation order', 2)
	end
	internal_mock._target[internal_mock._field_name] = internal_mock._original
	internal_mock._active = false
end

function api.mock.returns(stub: Stub, ...: any)
	local internal_stub = stub :: any
	internal_stub._returns = pack(...)
end

function api.mock.returnsOnce(stub: Stub, ...: any)
	local internal_stub = stub :: any
	table.insert(internal_stub._return_queue, pack(...))
end

function api.mock.stub(target: any, field_name: string): Stub
	local original = target[field_name]
	if type(original) ~= 'function' then
		error(`Expected {field_name} to be a function`, 2)
	end

	local stub = {
		_marker = mock_marker,
		_target = target,
		_field_name = field_name,
		_original = original,
		_replacement = nil :: any,
		_active = true,
		_returns = { n = 0 },
		_return_queue = {} :: { PackedValues },
	}
	local replacement = function()
		local returns = table.remove(stub._return_queue, 1)
		if returns ~= nil then return unpack_values(returns) end
		return unpack_values(stub._returns)
	end
	stub._replacement = replacement
	target[field_name] = replacement

	return stub :: any
end

function api.mock.intercept(target: any, field_name: string): Intercept
	local original = target[field_name]
	if type(original) ~= 'function' then
		error(`Expected {field_name} to be a function`, 2)
	end

	local intercept = {
		_marker = mock_marker,
		_target = target,
		_field_name = field_name,
		_original = original,
		_replacement = nil :: any,
		_active = true,
		_capture_threads = {} :: { [any]: boolean },
		_pending_calls = 0,
	}
	local replacement = function(...: any)
		if not intercept._capture_threads[coroutine.running()] then
			error('Expected intercepted calls to run inside mock.capture', 2)
		end

		local raw_args = pack(...)
		local first_public_index = if raw_args[1] == target then 2 else 1
		local args = { n = raw_args.n - first_public_index + 1 }
		for index = first_public_index, raw_args.n do
			args[index - first_public_index + 1] = raw_args[index]
		end

		local call = {
			_marker = captured_call_marker,
			args = args,
			_intercept = intercept,
			_raw_args = raw_args,
			_thread = coroutine.running(),
			_resolved = false,
		}
		intercept._pending_calls += 1
		local returned = pack(coroutine.yield(call))
		intercept._pending_calls -= 1
		if returned[1] == release_original then
			return (original :: any)(unpack_values(raw_args))
		end
		return unpack_values(returned)
	end
	intercept._replacement = replacement
	target[field_name] = replacement

	return intercept :: any
end

function api.mock.capture(intercept: Intercept, callback: () -> ()): Call
	local internal_intercept = intercept :: any
	local thread = coroutine.create(callback)
	internal_intercept._capture_threads[thread] = true
	local result = pack(coroutine.resume(thread))
	if not result[1] then
		internal_intercept._capture_threads[thread] = nil
		error(result[2], 0)
	end

	local call = result[2]
	if
		type(call) ~= 'table'
		or call._marker ~= captured_call_marker
		or call._intercept ~= internal_intercept
	then
		internal_intercept._capture_threads[thread] = nil
		error('Expected callback to call the intercepted method', 2)
	end

	return call :: any
end

function api.mock.respond(call: Call, ...: any): Call?
	return resume_captured_call(call :: any, pack(...))
end

function api.mock.release(call: Call): Call?
	return resume_captured_call(call :: any, { n = 1, release_original })
end

function api.mock.spy(target: any, field_name: string): Spy
	local original = target[field_name]
	if type(original) ~= 'function' then
		error(`Expected {field_name} to be a function`, 2)
	end

	local spy = {
		_marker = mock_marker,
		calls = {},
		_target = target,
		_field_name = field_name,
		_original = original,
		_replacement = nil :: any,
		_active = true,
	}
	local replacement = function(...: any)
		local raw_args = pack(...)
		local first_public_index = if raw_args[1] == target then 2 else 1
		local args = { n = raw_args.n - first_public_index + 1 }
		for index = first_public_index, raw_args.n do
			args[index - first_public_index + 1] = raw_args[index]
		end

		local call = { args = args }
		table.insert(spy.calls, call)

		local result = pack(pcall(original, ...))
		if result[1] then
			local returns = { n = result.n - 1 }
			for index = 2, result.n do
				returns[index - 1] = result[index]
			end
			call.returns = returns
			return unpack_values(returns)
		end

		call.error = result[2]
		error(result[2], 0)
	end
	spy._replacement = replacement
	target[field_name] = replacement

	return spy :: any
end

function api.near(
	expected: number,
	actual: number,
	tolerance: number?,
	message: string?
)
	local resolved_tolerance = tolerance or 0
	if resolved_tolerance < 0 then
		error(
			`Expected tolerance to be non-negative, got {resolved_tolerance}`,
			2
		)
	end

	if math.abs(expected - actual) <= resolved_tolerance then return end
	error(
		message
			or `Expected {format_value(expected)}, got {format_value(actual)} (tolerance {format_value(
				resolved_tolerance
			)})`,
		2
	)
end

local function append_deep_path(path: string, key: any): string
	if type(key) == 'string' and string.match(key, '^[%a_][%w_]*$') then
		return if path == '' then key else `{path}.{key}`
	end

	return `{path}[{format_value(key)}]`
end

local function find_deep_difference(
	expected: any,
	actual: any,
	path: string,
	seen: any
): string?
	if expected == actual then return nil end
	if type(expected) ~= 'table' or type(actual) ~= 'table' then
		return `Expected {path} to be {format_value(expected)}, got {format_value(
			actual
		)}`
	end

	local expected_pairs = seen[expected]
	if expected_pairs ~= nil and expected_pairs[actual] then return nil end

	if expected_pairs == nil then
		expected_pairs = {}
		seen[expected] = expected_pairs
	end
	expected_pairs[actual] = true

	for key, expected_value in expected do
		local difference = find_deep_difference(
			expected_value,
			actual[key],
			append_deep_path(path, key),
			seen
		)
		if difference ~= nil then return difference end
	end

	for key, actual_value in actual do
		if expected[key] == nil then
			return `Expected {append_deep_path(path, key)} to be absent, got {format_value(
				actual_value
			)}`
		end
	end

	return nil
end

function api.deepEq(expected: any, actual: any, message: string?)
	local difference = find_deep_difference(expected, actual, '', {})
	if difference == nil then return end
	error(message or difference, 2)
end

local function capture_failure(callback: () -> ()): string
	local succeeded, failure = (pcall :: any)(callback)
	if succeeded then error('Expected the callback to fail', 2) end
	return tostring(failure)
end

local t = (function()
	if game then
		local ReplicatedStorage = game:GetService 'ReplicatedStorage'
		local packages = ReplicatedStorage:FindFirstChild 'Packages' :: Folder?
		return packages
			and packages:FindFirstChild 't'
			and require(ReplicatedStorage.Packages.t)
	end

	return require '@vendor/t'
end)()

if not t then return api end

t.suite('ok.that', function()
	t.test('should pass when condition is true', function()
		api.that(true)
	end)

	t.test('should fail when condition is false', function()
		local failure = capture_failure(function()
			api.that(false)
		end)

		if #failure == 0 then error('Expected a failure message', 2) end
	end)

	t.test('should include custom message in failure', function()
		local message = 'The round must have a winner'
		local failure = capture_failure(function()
			api.that(false, message)
		end)

		if not string.find(failure, message, 1, true) then
			error(`Expected failure to include {message}, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.eq', function()
	t.test('should pass when values are equal', function()
		api.eq(3, 3)
	end)

	t.test('should fail when values differ', function()
		local failure = capture_failure(function()
			api.eq(3, 4)
		end)

		if #failure == 0 then error('Expected a failure message', 2) end
	end)

	t.test('should include custom message in failure', function()
		local message = 'The player must have enough coins'
		local failure = capture_failure(function()
			api.eq(100, 75, message)
		end)

		if not string.find(failure, message, 1, true) then
			error(`Expected failure to include {message}, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.neq', function()
	t.test('should pass when values differ', function()
		api.neq(3, 4)
	end)

	t.test('should fail when values are equal', function()
		local failure = capture_failure(function()
			api.neq(3, 3)
		end)

		if #failure == 0 then error('Expected a failure message', 2) end
	end)

	t.test('should include custom message in failure', function()
		local message = 'The player must not already be in the match'
		local failure = capture_failure(function()
			api.neq('queued', 'queued', message)
		end)

		if not string.find(failure, message, 1, true) then
			error(`Expected failure to include {message}, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.deepEq', function()
	t.test('should pass when nested tables are equal', function()
		api.deepEq(
			{ player = { id = 42, coins = 100 } },
			{ player = { id = 42, coins = 100 } }
		)
	end)

	t.test('should pass when cyclic tables are equal', function()
		local expected = { id = 42 }
		expected.self = expected

		local actual = { id = 42 }
		actual.self = actual

		api.deepEq(expected, actual)
	end)

	t.test('should fail when nested values differ', function()
		local failure = capture_failure(function()
			api.deepEq(
				{ player = { id = 42, coins = 100 } },
				{ player = { id = 42, coins = 75 } }
			)
		end)

		if
			not string.find(
				failure,
				'Expected player.coins to be 100, got 75',
				1,
				true
			)
		then
			error(`Expected structural difference, got {failure}`, 2)
		end
	end)

	t.test('should identify a missing nested value', function()
		local failure = capture_failure(function()
			api.deepEq({ player = { coins = 100 } }, { player = {} })
		end)

		if
			not string.find(
				failure,
				'Expected player.coins to be 100, got nil',
				1,
				true
			)
		then
			error(`Expected missing value difference, got {failure}`, 2)
		end
	end)

	t.test(
		'should report cyclic table differences without recursing forever',
		function()
			local expected = { coins = 100 }
			expected.self = expected

			local actual = { coins = 75 }
			actual.self = actual

			local failure = capture_failure(function()
				api.deepEq(expected, actual)
			end)

			if
				not string.find(
					failure,
					'Expected coins to be 100, got 75',
					1,
					true
				)
			then
				error(`Expected cyclic difference, got {failure}`, 2)
			end
		end
	)

	t.test('should include custom message in failure', function()
		local message = 'The loaded profile should match the saved profile'
		local failure = capture_failure(function()
			api.deepEq(
				{ inventory = { 'sword', 'potion' } },
				{ inventory = { 'sword' } },
				message
			)
		end)

		if not string.find(failure, message, 1, true) then
			error(`Expected failure to include {message}, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.near', function()
	t.test('should pass for equal values without a tolerance', function()
		api.near(42, 42)
	end)

	t.test('should pass for values within the tolerance', function()
		api.near(10, 10.2, 0.25)
	end)

	t.test('should pass at the tolerance boundary', function()
		api.near(1.25, 1.5, 0.25)
	end)

	t.test('should fail for values outside the tolerance', function()
		local failure = capture_failure(function()
			api.near(10, 10.26, 0.25)
		end)

		if #failure == 0 then error('Expected a failure message', 2) end
	end)

	t.test('should reject a negative tolerance', function()
		local failure = capture_failure(function()
			api.near(10, 10, -0.25)
		end)

		if not string.find(failure, 'non-negative', 1, true) then
			error(`Expected a tolerance validation failure, got {failure}`, 2)
		end
	end)

	t.test('should include the custom message in a failure', function()
		local message = 'The measured velocity must match the target'
		local failure = capture_failure(function()
			api.near(10, 10.26, 0.25, message)
		end)

		if not string.find(failure, message, 1, true) then
			error(`Expected failure to include {message}, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.isNil', function()
	t.test('should pass for nil', function()
		api.isNil(nil)
	end)

	t.test('should fail for a non-nil value', function()
		local failure = capture_failure(function()
			api.isNil(false)
		end)

		if #failure == 0 then error('Expected a failure message', 2) end
	end)

	t.test('should include the custom message in a failure', function()
		local message = 'The cached profile must not exist'
		local failure = capture_failure(function()
			api.isNil({ id = 42 }, message)
		end)

		if not string.find(failure, message, 1, true) then
			error(`Expected failure to include {message}, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.isNotNil', function()
	t.test('should pass for a non-nil value', function()
		api.isNotNil(false)
	end)

	t.test('should fail for nil', function()
		local failure = capture_failure(function()
			api.isNotNil(nil)
		end)

		if #failure == 0 then error('Expected a failure message', 2) end
	end)

	t.test('should include the custom message in a failure', function()
		local message = 'The active profile must exist'
		local failure = capture_failure(function()
			api.isNotNil(nil, message)
		end)

		if not string.find(failure, message, 1, true) then
			error(`Expected failure to include {message}, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.strContains', function()
	t.test('should pass when the text contains the substring', function()
		api.strContains('The match has started', 'match')
	end)

	t.test('should search from the provided start index', function()
		api.strContains('red blue red', 'red', 5)
	end)

	t.test(
		'should fail when the text does not contain the substring',
		function()
			local failure = capture_failure(function()
				api.strContains('The match has started', 'finished')
			end)

			if #failure == 0 then error('Expected a failure message', 2) end
		end
	)

	t.test('should include the custom message in a failure', function()
		local message = 'The status must mention a winner'
		local failure = capture_failure(function()
			api.strContains('Round complete', 'winner', nil, message)
		end)

		if not string.find(failure, message, 1, true) then
			error(`Expected failure to include {message}, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.throws', function()
	t.test('should pass when the callback throws', function()
		api.throws(function()
			error 'The action failed'
		end)
	end)

	t.test('should forward arguments to the callback', function()
		api.throws(function(player_name, score)
			if player_name == 'Ada' and score == 100 then
				error 'The action failed'
			end
		end, 'Ada', 100)
	end)

	t.test('should fail when the callback does not throw', function()
		local failure = capture_failure(function()
			api.throws(function() end)
		end)

		if not string.find(failure, 'Expected callback to throw', 1, true) then
			error(`Expected a throws assertion failure, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.throwsWith', function()
	t.test('should pass when the callback throws the expected error', function()
		api.throwsWith('The action failed', function()
			error('The action failed', 0)
		end)
	end)

	t.test('should forward arguments to the callback', function()
		api.throwsWith('The action failed', function(player_name, score)
			if player_name == 'Ada' and score == 100 then
				error('The action failed', 0)
			end
		end, 'Ada', 100)
	end)

	t.test('should fail when the callback throws a different error', function()
		local failure = capture_failure(function()
			api.throwsWith('The action failed', function()
				error('The action timed out', 0)
			end)
		end)

		if not string.find(failure, 'The action failed', 1, true) then
			error(
				`Expected an expected-error assertion failure, got {failure}`,
				2
			)
		end
	end)

	t.test('should fail when the callback does not throw', function()
		local failure = capture_failure(function()
			api.throwsWith('The action failed', function() end)
		end)

		if not string.find(failure, 'The action failed', 1, true) then
			error(
				`Expected an expected-error assertion failure, got {failure}`,
				2
			)
		end
	end)
end)

t.suite('assertion diagnostics', function()
	local function expect_diagnostic(expected: string, callback: () -> ())
		local failure = capture_failure(callback)
		if not string.find(failure, expected, 1, true) then
			error(`Expected diagnostic {expected}, got {failure}`, 2)
		end
	end

	t.test('should describe value assertion failures consistently', function()
		expect_diagnostic('Expected true, got false', function()
			api.that(false)
		end)
		expect_diagnostic('Expected "Pikachu", got "Gengar"', function()
			api.eq('Pikachu', 'Gengar')
		end)
		expect_diagnostic('Expected 3 to differ, got 3', function()
			api.neq(3, 3)
		end)
		expect_diagnostic('Expected nil, got "profile"', function()
			api.isNil 'profile'
		end)
		expect_diagnostic('Expected a non-nil value, got nil', function()
			api.isNotNil(nil)
		end)
		expect_diagnostic(
			'Expected text to contain "world", got "hello"',
			function()
				api.strContains('hello', 'world')
			end
		)
		expect_diagnostic('Expected 10, got 10.26 (tolerance 0.25)', function()
			api.near(10, 10.26, 0.25)
		end)
	end)

	t.test(
		'should describe callback assertion failures consistently',
		function()
			expect_diagnostic(
				'Expected callback to throw, but it returned successfully',
				function()
					api.throws(function() end)
				end
			)
			expect_diagnostic(
				'Expected callback to throw "expected", got "actual"',
				function()
					api.throwsWith('expected', function()
						error('actual', 0)
					end)
				end
			)
		end
	)

	t.test('should describe spy assertion failures consistently', function()
		local target = {
			run = function() end,
		}
		local spy = api.mock.spy(target, 'run')

		expect_diagnostic('Expected spy to be called, got no calls', function()
			api.called(spy)
		end)
		expect_diagnostic('Expected 1 call, got 0', function()
			api.calledTimes(spy, 1)
		end)
		expect_diagnostic(
			'Expected spy to be called with the expected arguments, got no matching call',
			function()
				api.calledWith(spy, 'profile')
			end
		)
	end)
end)

t.suite('ok.mock.spy', function()
	t.test(
		'should call the original method and preserve its return value',
		function()
			local target = {
				total = 0,
				add = function(self, amount)
					self.total += amount
					return self.total
				end,
			}
			local spy = api.mock.spy(target, 'add')

			local total = target:add(5)

			if total ~= 5 then error(`Expected 5, got {total}`, 2) end
			if target.total ~= 5 then
				error(`Expected target total to be 5, got {target.total}`, 2)
			end
			if spy == nil then
				error('Expected mock.spy() to return a spy', 2)
			end
		end
	)

	t.test('should record calls without the target self argument', function()
		local target = {
			add = function(_, amount)
				return amount
			end,
		}
		local spy = api.mock.spy(target, 'add')

		target:add(5)

		if #spy.calls ~= 1 then
			error(`Expected 1 call, got {#spy.calls}`, 2)
		end
		local args = spy.calls[1].args
		if #args ~= 1 then
			error(`Expected 1 public argument, got {#args}`, 2)
		end
		if args[1] ~= 5 then error(`Expected 5, got {args[1]}`, 2) end
	end)

	t.test('should record every call in order', function()
		local target = {
			set = function(_, value)
				return value
			end,
		}
		local spy = api.mock.spy(target, 'set')

		target:set 'first'
		target:set 'second'

		if #spy.calls ~= 2 then
			error(`Expected 2 calls, got {#spy.calls}`, 2)
		end
		if spy.calls[1].args[1] ~= 'first' then
			error('Expected first call argument', 2)
		end
		if spy.calls[2].args[1] ~= 'second' then
			error('Expected second call argument', 2)
		end
	end)

	t.test('should record the original return values', function()
		local target = {
			get = function()
				return 'profile', 42
			end,
		}
		local spy = api.mock.spy(target, 'get')

		local name, id = target:get()
		local returns = spy.calls[1].returns

		if name ~= 'profile' then error(`Expected profile, got {name}`, 2) end
		if id ~= 42 then error(`Expected 42, got {id}`, 2) end
		if returns == nil then error('Expected recorded return values', 2) end
		if returns[1] ~= 'profile' then
			error('Expected first return value', 2)
		end
		if returns[2] ~= 42 then error('Expected second return value', 2) end
		if spy.calls[1].error ~= nil then
			error('Expected no recorded error', 2)
		end
	end)

	t.test(
		'should record and rethrow errors from the original method',
		function()
			local target = {
				fail = function()
					error('The action failed', 0)
				end,
			}
			local spy = api.mock.spy(target, 'fail')

			local succeeded, failure = pcall(function()
				target:fail()
			end)

			if succeeded then
				error('Expected the original method to throw', 2)
			end
			if failure ~= 'The action failed' then
				error(`Expected original error, got {failure}`, 2)
			end
			if #spy.calls ~= 1 then
				error(`Expected 1 call, got {#spy.calls}`, 2)
			end
			if spy.calls[1].error ~= 'The action failed' then
				error(`Expected recorded error, got {spy.calls[1].error}`, 2)
			end
		end
	)
end)

t.suite('ok.mock.restore', function()
	t.test('should reject a value that is not a mock', function()
		local failure = capture_failure(function()
			api.mock.restore({} :: any)
		end)

		if
			not string.find(
				failure,
				'Expected a mock created by ok.mock',
				1,
				true
			)
		then
			error(`Expected invalid mock failure, got {failure}`, 2)
		end
	end)

	t.test('should restore the original method', function()
		local target = {
			run = function(_, value)
				return value * 2
			end,
		}
		local original = target.run
		local spy = api.mock.spy(target, 'run')

		api.mock.restore(spy)

		if target.run ~= original then
			error('Expected the original method to be restored', 2)
		end
		if target:run(5) ~= 10 then
			error('Expected restored method return value', 2)
		end
	end)

	t.test('should stop recording calls after restoration', function()
		local target = {
			run = function() end,
		}
		local spy = api.mock.spy(target, 'run')

		target:run()
		api.mock.restore(spy)
		target:run()

		if #spy.calls ~= 1 then
			error(
				`Expected only the call before restoration, got {#spy.calls}`,
				2
			)
		end
	end)

	t.test('should reject restoring an inactive mock', function()
		local target = {
			run = function() end,
		}
		local spy = api.mock.spy(target, 'run')

		api.mock.restore(spy)

		local failure = capture_failure(function()
			api.mock.restore(spy)
		end)

		if not string.find(failure, 'Expected mock to be active', 1, true) then
			error(`Expected inactive mock failure, got {failure}`, 2)
		end
	end)

	t.test('should reject restoring a mock below a newer mock', function()
		local target = {
			run = function() end,
		}
		local stub = api.mock.stub(target, 'run')
		local spy = api.mock.spy(target, 'run')

		local failure = capture_failure(function()
			api.mock.restore(stub)
		end)

		if
			not string.find(
				failure,
				'Expected mocks to be restored in reverse creation order',
				1,
				true
			)
		then
			error(`Expected restoration order failure, got {failure}`, 2)
		end

		api.mock.restore(spy)
		api.mock.restore(stub)
	end)

	t.test('should restore the original method from a stub', function()
		local target = {
			run = function(_, value)
				return value * 2
			end,
		}
		local original = target.run
		local stub = api.mock.stub(target, 'run')

		api.mock.restore(stub)

		if target.run ~= original then
			error('Expected the original method to be restored', 2)
		end
		if target:run(5) ~= 10 then
			error('Expected restored method return value', 2)
		end
	end)

	t.test(
		'should stop returning configured values after stub restoration',
		function()
			local calls = 0
			local target = {
				run = function()
					calls += 1
					return 'original result'
				end,
			}
			local stub = api.mock.stub(target, 'run')

			api.mock.returns(stub, 'stubbed result')
			if target:run() ~= 'stubbed result' then
				error('Expected configured stub result', 2)
			end

			api.mock.restore(stub)

			if target:run() ~= 'original result' then
				error('Expected original result after restoration', 2)
			end
			if calls ~= 1 then
				error(`Expected 1 original call, got {calls}`, 2)
			end
		end
	)

	t.test('should restore the original method from an intercept', function()
		local target = {
			run = function(_, value)
				return value * 2
			end,
		}
		local original = target.run
		local intercept = api.mock.intercept(target, 'run')

		api.mock.restore(intercept)

		if target.run ~= original then
			error('Expected the original method to be restored', 2)
		end
		if target:run(5) ~= 10 then
			error('Expected restored method return value', 2)
		end
	end)

	t.test(
		'should reject restoring an intercept with a pending call',
		function()
			local target = {
				run = function() end,
			}
			local intercept = api.mock.intercept(target, 'run')
			local call = api.mock.capture(intercept, function()
				target:run()
			end)

			local failure = capture_failure(function()
				api.mock.restore(intercept)
			end)

			if
				not string.find(
					failure,
					'Expected intercept to have no pending calls',
					1,
					true
				)
			then
				error(`Expected pending intercept failure, got {failure}`, 2)
			end

			api.mock.respond(call)
			api.mock.restore(intercept)
		end
	)
end)

t.suite('ok.mock.stub', function()
	t.test('should replace the original method and return a stub', function()
		local target = {
			run = function()
				return 'original result'
			end,
		}
		local original = target.run

		local stub = api.mock.stub(target, 'run')

		if stub == nil then
			error('Expected mock.stub() to return a stub', 2)
		end
		if target.run == original then
			error('Expected the original method to be replaced', 2)
		end
	end)

	t.test('should not call the original method by default', function()
		local calls = 0
		local target = {
			run = function()
				calls += 1
				return 'original result'
			end,
		}
		api.mock.stub(target, 'run')

		local result = target:run()

		if calls ~= 0 then
			error(`Expected no original calls, got {calls}`, 2)
		end
		if result ~= nil then
			error(`Expected nil default result, got {result}`, 2)
		end
	end)
end)

t.suite('ok.mock.intercept', function()
	t.test(
		'should replace the original method and return an intercept',
		function()
			local target = {
				load = function()
					return 'original result'
				end,
			}
			local original = target.load

			local intercept = api.mock.intercept(target, 'load')

			if intercept == nil then
				error('Expected mock.intercept() to return an intercept', 2)
			end
			if target.load == original then
				error('Expected the original method to be replaced', 2)
			end
		end
	)

	t.test('should reject a non-function field', function()
		local target = {
			load = 'profile',
		}

		local failure = capture_failure(function()
			api.mock.intercept(target, 'load')
		end)

		if
			not string.find(failure, 'Expected load to be a function', 1, true)
		then
			error(`Expected function validation failure, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.mock.capture', function()
	t.test(
		'should keep separate pending calls on the same intercept',
		function()
			local target = {
				load = function(_, key)
					return key
				end,
			}
			local intercept = api.mock.intercept(target, 'load')
			local profile, settings, inventory

			local profile_call = api.mock.capture(intercept, function()
				profile = target:load 'profile'
				settings = target:load 'settings'
			end)
			local inventory_call = api.mock.capture(intercept, function()
				inventory = target:load 'inventory'
			end)

			api.mock.respond(inventory_call, 'inventory result')

			if inventory ~= 'inventory result' then
				error(`Expected inventory result, got {inventory}`, 2)
			end

			local settings_call =
				api.mock.respond(profile_call, 'profile result')

			if profile ~= 'profile result' then
				error(`Expected profile result, got {profile}`, 2)
			end
			if settings_call == nil or settings_call.args[1] ~= 'settings' then
				error('Expected settings call after the profile response', 2)
			end

			api.mock.respond(settings_call, 'settings result')

			if settings ~= 'settings result' then
				error(`Expected settings result, got {settings}`, 2)
			end

			api.mock.restore(intercept)
		end
	)

	t.test('should capture sequential calls from the same callback', function()
		local target = {
			load = function(_, key)
				return key
			end,
		}
		local intercept = api.mock.intercept(target, 'load')
		local first_result, second_result

		local first_call = api.mock.capture(intercept, function()
			first_result = target:load 'profile'
			second_result = target:load 'inventory'
		end)

		if first_call.args[1] ~= 'profile' then
			error(`Expected profile, got {first_call.args[1]}`, 2)
		end

		local second_call = api.mock.respond(first_call, 'first result')

		if first_result ~= 'first result' then
			error(`Expected first result, got {first_result}`, 2)
		end
		if second_call == nil or second_call.args[1] ~= 'inventory' then
			error('Expected inventory call after the first response', 2)
		end

		local completed_call = api.mock.respond(second_call, 'second result')

		if second_result ~= 'second result' then
			error(`Expected second result, got {second_result}`, 2)
		end
		if completed_call ~= nil then
			error('Expected no call after the callback completed', 2)
		end

		api.mock.restore(intercept)
	end)

	t.test('should clean up after the callback fails before a call', function()
		local target = {
			load = function() end,
		}
		local intercept = api.mock.intercept(target, 'load')

		local failure = capture_failure(function()
			api.mock.capture(intercept, function()
				error('Setup failed', 0)
			end)
		end)

		if not string.find(failure, 'Setup failed', 1, true) then
			error(`Expected callback error, got {failure}`, 2)
		end

		local call = api.mock.capture(intercept, function()
			target:load()
		end)

		api.mock.respond(call)
		api.mock.restore(intercept)
	end)

	t.test(
		'should clean up after the callback fails following a response',
		function()
			local target = {
				load = function() end,
			}
			local intercept = api.mock.intercept(target, 'load')
			local call = api.mock.capture(intercept, function()
				target:load()
				error('Callback failed', 0)
			end)

			local failure = capture_failure(function()
				api.mock.respond(call)
			end)

			if not string.find(failure, 'Callback failed', 1, true) then
				error(`Expected callback error, got {failure}`, 2)
			end

			api.mock.restore(intercept)
		end
	)

	t.test('should reject intercepted calls outside capture', function()
		local target = {
			load = function() end,
		}
		api.mock.intercept(target, 'load')

		local failure = capture_failure(function()
			target:load()
		end)

		if
			not string.find(
				failure,
				'Expected intercepted calls to run inside mock.capture',
				1,
				true
			)
		then
			error(`Expected capture usage failure, got {failure}`, 2)
		end
	end)

	t.test(
		'should expose the same public arguments for dot and colon calls',
		function()
			local target = {
				load = function(_, profile, slot)
					return profile, slot
				end,
			}
			local intercept = api.mock.intercept(target, 'load')

			local dot_call = api.mock.capture(intercept, function()
				target.load('profile', 2)
			end)

			if dot_call.args.n ~= 2 then
				error(`Expected 2 arguments, got {dot_call.args.n}`, 2)
			end
			if dot_call.args[1] ~= 'profile' or dot_call.args[2] ~= 2 then
				error('Expected dot call arguments to be preserved', 2)
			end
			api.mock.respond(dot_call)

			local colon_call = api.mock.capture(intercept, function()
				target:load('profile', 2)
			end)

			if colon_call.args.n ~= 2 then
				error(`Expected 2 arguments, got {colon_call.args.n}`, 2)
			end
			if colon_call.args[1] ~= 'profile' or colon_call.args[2] ~= 2 then
				error('Expected colon call arguments without self', 2)
			end
			api.mock.respond(colon_call)
		end
	)

	t.test(
		'should capture arguments without the target self argument',
		function()
			local target = {
				load = function(_, profile)
					return profile
				end,
			}
			local intercept = api.mock.intercept(target, 'load')

			local call = api.mock.capture(intercept, function()
				target:load 'profile'
			end)

			if call.args[1] ~= 'profile' then
				error(`Expected profile, got {call.args[1]}`, 2)
			end
		end
	)

	t.test(
		'should fail when the callback does not call the intercepted method',
		function()
			local target = {
				load = function() end,
			}
			local intercept = api.mock.intercept(target, 'load')

			local failure = capture_failure(function()
				api.mock.capture(intercept, function() end)
			end)

			if
				not string.find(
					failure,
					'Expected callback to call the intercepted method',
					1,
					true
				)
			then
				error(`Expected capture failure, got {failure}`, 2)
			end
		end
	)
end)

t.suite('ok.mock.respond', function()
	t.test('should reject a value that is not a captured call', function()
		local failure = capture_failure(function()
			api.mock.respond({} :: any)
		end)

		if
			not string.find(
				failure,
				'Expected a call captured by ok.mock.capture',
				1,
				true
			)
		then
			error(`Expected invalid call failure, got {failure}`, 2)
		end
	end)

	t.test(
		'should return the configured values to the captured call',
		function()
			local target = {
				load = function(): (string, nil, number)
					return '', nil, 0
				end,
			}
			local intercept = api.mock.intercept(target, 'load')
			local profile, missing, id

			local call = api.mock.capture(intercept, function()
				profile, missing, id = target:load()
			end)

			api.mock.respond(call, 'profile', nil, 42)

			if profile ~= 'profile' then
				error(`Expected profile, got {profile}`, 2)
			end
			if missing ~= nil then error(`Expected nil, got {missing}`, 2) end
			if id ~= 42 then error(`Expected 42, got {id}`, 2) end
		end
	)

	t.test('should reject resolving a call more than once', function()
		local target = {
			load = function() end,
		}
		local intercept = api.mock.intercept(target, 'load')
		local call = api.mock.capture(intercept, function()
			target:load()
		end)

		api.mock.respond(call)

		local failure = capture_failure(function()
			api.mock.respond(call)
		end)

		if
			not string.find(
				failure,
				'Expected captured call to be pending',
				1,
				true
			)
		then
			error(`Expected pending call failure, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.mock.release', function()
	t.test('should reject a value that is not a captured call', function()
		local failure = capture_failure(function()
			api.mock.release({} :: any)
		end)

		if
			not string.find(
				failure,
				'Expected a call captured by ok.mock.capture',
				1,
				true
			)
		then
			error(`Expected invalid call failure, got {failure}`, 2)
		end
	end)

	t.test(
		'should continue the captured call with the original method',
		function()
			local calls = 0
			local target = {
				load = function(_, profile)
					calls += 1
					return `original {profile}`
				end,
			}
			local intercept = api.mock.intercept(target, 'load')
			local result

			local call = api.mock.capture(intercept, function()
				result = target:load 'profile'
			end)

			api.mock.release(call)

			if result ~= 'original profile' then
				error(`Expected original profile, got {result}`, 2)
			end
			if calls ~= 1 then
				error(`Expected 1 original call, got {calls}`, 2)
			end
		end
	)

	t.test('should preserve errors from the original method', function()
		local target = {
			load = function()
				error('Connection lost', 0)
			end,
		}
		local intercept = api.mock.intercept(target, 'load')
		local call = api.mock.capture(intercept, function()
			target:load()
		end)

		local failure = capture_failure(function()
			api.mock.release(call)
		end)

		if not string.find(failure, 'Connection lost', 1, true) then
			error(`Expected original error, got {failure}`, 2)
		end

		api.mock.restore(intercept)
	end)
end)

t.suite('ok.mock.returns', function()
	t.test('should return the configured value', function()
		local target = {
			load = function() end,
		}
		local stub = api.mock.stub(target, 'load')

		api.mock.returns(stub, 'profile')

		if target:load() ~= 'profile' then
			error('Expected configured return value', 2)
		end
	end)

	t.test('should preserve multiple configured return values', function()
		local target = {
			load = function(): (string, nil, number)
				return '', nil, 0
			end,
		}
		local stub = api.mock.stub(target, 'load')

		api.mock.returns(stub, 'profile', nil, 42)

		local profile, missing, id = target:load()
		if profile ~= 'profile' then
			error(`Expected profile, got {profile}`, 2)
		end
		if missing ~= nil then error(`Expected nil, got {missing}`, 2) end
		if id ~= 42 then error(`Expected 42, got {id}`, 2) end
	end)

	t.test('should replace a previous return configuration', function()
		local target = {
			load = function() end,
		}
		local stub = api.mock.stub(target, 'load')

		api.mock.returns(stub, 'first profile')
		api.mock.returns(stub, 'second profile')

		if target:load() ~= 'second profile' then
			error('Expected latest configured return value', 2)
		end
	end)

	t.test(
		'should return queued values before the configured return',
		function()
			local target = {
				load = function() end,
			}
			local stub = api.mock.stub(target, 'load')

			api.mock.returns(stub, 'default')
			api.mock.returnsOnce(stub, 'pikachu')
			api.mock.returnsOnce(stub, 'greninja')
			api.mock.returnsOnce(stub, 'gengar')

			if target:load() ~= 'pikachu' then error('Expected pikachu', 2) end
			if target:load() ~= 'greninja' then
				error('Expected greninja', 2)
			end
			if target:load() ~= 'gengar' then error('Expected gengar', 2) end
			if target:load() ~= 'default' then error('Expected default', 2) end
		end
	)
end)

t.suite('ok.called', function()
	t.test('should pass when the spy was called', function()
		local target = {
			run = function() end,
		}
		local spy = api.mock.spy(target, 'run')

		target:run()

		api.called(spy)
	end)

	t.test('should fail when the spy was not called', function()
		local target = {
			run = function() end,
		}
		local spy = api.mock.spy(target, 'run')
		local failure = capture_failure(function()
			api.called(spy)
		end)

		if #failure == 0 then error('Expected a failure message', 2) end
	end)

	t.test('should include the custom message in a failure', function()
		local target = {
			run = function() end,
		}
		local spy = api.mock.spy(target, 'run')
		local message = 'The save operation must run'
		local failure = capture_failure(function()
			api.called(spy, message)
		end)

		if not string.find(failure, message, 1, true) then
			error(`Expected failure to include {message}, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.calledTimes', function()
	t.test(
		'should pass when the spy was called the expected number of times',
		function()
			local target = {
				run = function() end,
			}
			local spy = api.mock.spy(target, 'run')

			target:run()
			target:run()

			api.calledTimes(spy, 2)
		end
	)

	t.test(
		'should fail when the spy was called fewer times than expected',
		function()
			local target = {
				run = function() end,
			}
			local spy = api.mock.spy(target, 'run')

			target:run()

			local failure = capture_failure(function()
				api.calledTimes(spy, 2)
			end)

			if #failure == 0 then error('Expected a failure message', 2) end
		end
	)

	t.test(
		'should fail when the spy was called more times than expected',
		function()
			local target = {
				run = function() end,
			}
			local spy = api.mock.spy(target, 'run')

			target:run()
			target:run()

			local failure = capture_failure(function()
				api.calledTimes(spy, 1)
			end)

			if #failure == 0 then error('Expected a failure message', 2) end
		end
	)

	t.test('should include the custom message in a failure', function()
		local target = {
			run = function() end,
		}
		local spy = api.mock.spy(target, 'run')
		local message = 'The save operation must run twice'
		local failure = capture_failure(function()
			api.calledTimes(spy, 2, message)
		end)

		if not string.find(failure, message, 1, true) then
			error(`Expected failure to include {message}, got {failure}`, 2)
		end
	end)
end)

t.suite('ok.calledWith', function()
	t.test('should pass when a call has the expected arguments', function()
		local target = {
			run = function() end,
		}
		local spy = api.mock.spy(target, 'run')

		target:run('Ada', 100)

		api.calledWith(spy, 'Ada', 100)
	end)

	t.test(
		'should pass when a later call has the expected arguments',
		function()
			local target = {
				run = function() end,
			}
			local spy = api.mock.spy(target, 'run')

			target:run('Lin', 50)
			target:run('Ada', 100)

			api.calledWith(spy, 'Ada', 100)
		end
	)

	t.test('should fail when no call has the expected arguments', function()
		local target = {
			run = function() end,
		}
		local spy = api.mock.spy(target, 'run')

		target:run('Lin', 50)

		local failure = capture_failure(function()
			api.calledWith(spy, 'Ada', 100)
		end)

		if
			not string.find(failure, 'Expected spy to be called with', 1, true)
		then
			error(`Expected a called-with assertion failure, got {failure}`, 2)
		end
	end)
end)

return api
