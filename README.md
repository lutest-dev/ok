# ok [![CI](https://github.com/lutest-dev/ok/actions/workflows/ci.yml/badge.svg)](https://github.com/lutest-dev/ok/actions/workflows/ci.yml) [![Luau](https://img.shields.io/badge/Luau-00A2FF?logo=roblox&logoColor=white)](https://luau.org/) [![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`ok` is a compact assertion and mocking library for Luau and Roblox.

It is runner-agnostic: use it with [Lutest](https://github.com/lutest-dev/lutest), TestEZ, Jest-Roblox, or your own test runner. `ok` only provides assertions and test doubles; your runner decides how tests are discovered and reported.

## Install

With Wally:

```toml
[dependencies]
ok = "cayasde/ok@0.1.0"
```

Then install dependencies and require the package from your test:

```luau
local ReplicatedStorage = game:GetService 'ReplicatedStorage'
local ok = require(ReplicatedStorage.Packages.ok)
```

## Assertions

Assertions are direct functions. They do not use fluent chains and work in any test function.
Their default failures use an `Expected ..., got ...` diagnostic whenever a
received value is available; a custom message replaces that diagnostic.

```luau
local ok = require '@lib'

ok.eq(100, player.health)
ok.neq('guest', player.role)
ok.isNil(player.target)
ok.isNotNil(player.character)
ok.strContains(player.name, 'cayasde')
ok.near(10, player.position.X, 0.1)
```

### `ok.eq(expected, actual, message?)`

Passes when two values are equal with `==`.

```luau
ok.eq(500, wallet:balance())
```

### `ok.neq(unexpected, actual, message?)`

Passes when two values are different with `~=`.

```luau
ok.neq('closed', connection.status)
```

### `ok.isNil(value, message?)` and `ok.isNotNil(value, message?)`

Assert whether a value is `nil`.

```luau
ok.isNil(cache:get 'missing')
ok.isNotNil(cache:get 'player-42')
```

### `ok.strContains(text, substring, startIndex?, message?)`

Passes when `text` contains `substring`. Matching is plain text, not a Lua pattern.

```luau
ok.strContains('Pokémon not found', 'not found')
```

### `ok.near(expected, actual, tolerance?, message?)`

Passes when `actual` is within `tolerance` of `expected`. The default tolerance is `0`.

```luau
ok.near(1.5, pokemon.height, 0.01)
```

### `ok.deepEq(expected, actual, message?)`

Recursively compares tables and their values. It also handles cyclic tables
and reports the first differing path when the assertion fails.

```luau
ok.deepEq(player.inventory, {
	potions = 3,
	coins = 120,
})
```

### `ok.throws(callback, ...args)` and `ok.throwsWith(expectedError, callback, ...args)`

Assert that a callback throws, optionally with an exact error value.
`ok.throws` returns the captured error, so a test can inspect it further.

```luau
ok.throws(function()
	wallet:increase(-1)
end)

local failure = ok.throws(function()
	error { code = 'INSUFFICIENT_BALANCE' }
end)
ok.eq('INSUFFICIENT_BALANCE', failure.code)

ok.throwsWith('insufficient balance', function()
	wallet:decrease(999)
end)
```

## Spies

A spy calls the original function and records each call. Use one when the observable behavior is *how* a collaborator was used.

```luau
local service = {
	send = function(message)
		return `sent: {message}`
	end,
}

local spy = ok.mock.spy(service, 'send')

local result = service.send 'hello'

ok.eq('sent: hello', result)
ok.called(spy)
ok.calledTimes(spy, 1)
ok.calledWith(spy, 'hello')

ok.mock.restore(spy)
```

### `ok.mock.spy(target, fieldName)`

Replaces `target[fieldName]` with a wrapper that calls the original function and records its calls. The field must contain a function.

### `ok.called(spy, message?)`

Passes when the spy was called at least once.

### `ok.calledTimes(spy, count, message?)`

Passes when the spy was called exactly `count` times.

### `ok.calledWith(spy, ...args)`

Passes when at least one recorded call received exactly `args` and returns the
matching `SpyCall`.

```luau
local call = ok.calledWith(spy, 'hello')
ok.eq('hello', call.args[1])
```

## Stubs

A stub replaces a function with a controlled return value. The original function is not called.

```luau
local http = {
	request = function(_url)
		error 'A real request should not run in this test'
	end,
}

local stub = ok.mock.stub(http, 'request')

ok.mock.returns(stub, {
	ok = true,
	status = 200,
	body = '{}',
})

local response = http.request 'https://example.test'
ok.eq(200, response.status)

ok.mock.restore(stub)
```

### `ok.mock.stub(target, fieldName)`

Replaces a function with a stub. Until configured, it returns no values.

### `ok.mock.returns(stub, ...values)`

Sets the default values returned by every later stub call. It preserves multiple return values, including `nil` values.

```luau
ok.mock.returns(stub, true, nil, 'cached')
```

### `ok.mock.returnsOnce(stub, ...values)`

Queues values for the next stub call only. Queued returns are consumed in first-in, first-out order; once the queue is empty, the stub falls back to `returns`.

```luau
ok.mock.returns(stub, 'default')
ok.mock.returnsOnce(stub, 'first')
ok.mock.returnsOnce(stub, 'second')

ok.eq('first', dependency.load())
ok.eq('second', dependency.load())
ok.eq('default', dependency.load())
```

## Controlled interception

Interception pauses a specific call. It is useful at asynchronous or side-effecting boundaries where a test needs to inspect the call before deciding how it continues.

```luau
local http = {
	request = function(_url)
		return { ok = false }
	end,
}

local intercept = ok.mock.intercept(http, 'request')
local response

local call = ok.mock.capture(intercept, function()
	response = http.request 'https://example.test/pokemon/gengar'
end)

ok.eq('https://example.test/pokemon/gengar', call.args[1])

ok.mock.respond(call, {
	ok = true,
	status = 200,
	body = '{}',
})

ok.eq(200, response.status)
ok.mock.restore(intercept)
```

### `ok.mock.intercept(target, fieldName)`

Replaces a function with a controlled interception point. A call to that function pauses until it is resolved by `respond` or `release`.

### `ok.mock.capture(intercept, callback)`

Runs `callback` in a coroutine and returns its first call captured by
`intercept`. The intercepted calls must happen inside that callback.

The callback may make sequential calls to the same intercept. `respond` and
`release` return the next captured call, or `nil` after the callback finishes.
Multiple callbacks may be pending on the same intercept; resolving a call
resumes only its own callback.

`capture`, `respond`, and `release` may yield while waiting for the controlled
callback or released original method to continue. The test runner must support
yielding tests when the code under test does.

Only the coroutine passed to `capture` is controlled. Calls made from child or
independent coroutines, such as ones created with `task.spawn`, are outside the
capture scope and must be coordinated by the test separately.
Resolve every captured call before restoring its intercept.

```luau
local call = ok.mock.capture(intercept, function()
	service:load('profile')
	service:load('inventory')
end)

call = ok.mock.respond(call, { id = 42 })
ok.mock.respond(call, { potions = 3 })
```

### `call.args`

The captured call's public arguments. Dot calls preserve their explicit
arguments; for method syntax, the target table itself is omitted.

```luau
local call = ok.mock.capture(intercept, function()
	service:load('profile')
end)

ok.eq('profile', call.args[1])
```

### `ok.mock.respond(call, ...values)`

Resumes a captured call with `values` as its return values. Returns the next
captured call from the callback, or `nil` when it finishes.

### `ok.mock.release(call)`

Resumes a captured call by invoking the original function with the captured
arguments. Returns the next captured call from the callback, or `nil` when it
finishes.

### `ok.mock.restore(mock)`

Restores the original function for a spy, stub, or intercept.

Always restore in reverse creation order when mocks wrap the same field.
Restoring an older mock while a newer one still wraps the field fails:

```luau
local stub = ok.mock.stub(service, 'load')
local spy = ok.mock.spy(service, 'load')

-- test

ok.mock.restore(spy)
ok.mock.restore(stub)
```

Restoring the same mock twice also fails.

## Luau types

The module exports `Arguments`, `Call`, `SpyCall`, `Spy`, `Stub`, `Intercept`,
and `Mock` types. `Call.args` and `Spy.calls` are typed public data; mock
implementation details remain private.

## Example

[`pokedex/`](pokedex) is a small Lute CLI that queries the PokéAPI and renders sprites with [Chafa](https://github.com/hpjansson/chafa). Its unit tests are co-located with the modules they specify; its HTTP integration tests live in [`pokedex/tests/`](pokedex/tests). It demonstrates assertions, stubs, spies, and controlled interception in one project.

## Status

`ok` is ready to use in Luau and Roblox projects. The public API is still evolving, so minor releases may include breaking changes while the library settles.

## Releases

This repository uses [Changesets](https://github.com/changesets/changesets) and SemVer. Add a changeset for every user-facing change:

```console
npx changeset
```

On `main`, GitHub Actions opens or updates a release pull request. Merging that pull request publishes the new Wally version and creates a GitHub Release with `ok.rbxm` attached. Publishing requires a repository secret named `WALLY_AUTH_TOKEN`.

## License

`ok` is distributed under the terms of the [MIT License](LICENSE).
