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

return nil
