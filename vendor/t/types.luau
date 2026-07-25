export type TestMode = 'run' | 'skip' | 'only' | 'todo'
export type TestFn = () -> ()
export type HookFn = () -> ()

export type SuiteHooks = {
	before_all: { HookFn },
	before_each: { HookFn },
	after_each: { HookFn },
	after_all: { HookFn },
}

export type TestScope = {
	name: string,
	hooks: SuiteHooks,
}

export type RunnableTestSpec = {
	name: string,
	mode: 'run' | 'skip' | 'only',
	fn: TestFn,
	scope: TestScope?,
}

export type TodoTestSpec = {
	name: string,
	mode: 'todo',
	scope: TestScope?,
}

export type TestSpec = RunnableTestSpec | TodoTestSpec

return nil
