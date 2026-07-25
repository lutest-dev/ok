# Project Concept

`ok` is a runner-agnostic assertion and mocking library for Luau and Roblox.
It can be used with Lutest, TestEZ, Jest-Roblox, or custom test runners.

The library provides direct assertions, spies, stubs, and controlled
interception. Its purpose is ergonomic, deterministic testing of Luau/Roblox
code, especially at boundaries involving services, asynchronous work, timing,
and side effects.

## Design Direction

- Design for idiomatic Luau and Roblox first.
- Use Jest as inspiration only; do not implement a Jest compatibility layer.
- Prefer direct, compact APIs over fluent assertion chains.
- Keep assertions separate from mock creation and control.
- Treat controlled interception as a way to pause a specific call, inspect it,
  and decide how its coroutine continues.

## Test-First Workflow

- Keep Lutest cases co-located with the module they specify.
- During the red phase, tests may refer to APIs that do not exist yet.
- Do not add existence guards or other preflight checks solely to make an
  incomplete API fail more neatly; describe the intended behavior directly.
- Preserve the module's existing structure when adding tests.
- When asked to add tests, respond with a well-formatted explanation of the
  covered cases and example API calls.

## References

- Lute test assertions: <https://lute.luau.org/std/test/assert>
- Lute test types: <https://lute.luau.org/std/test/types>
- Lutest documentation: <https://lutest-dev.github.io/site/>
- Jest expect: <https://jestjs.io/docs/expect>
- Jest mock functions: <https://jestjs.io/docs/mock-function-api>
