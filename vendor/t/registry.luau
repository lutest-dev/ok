local types = require '@vendor/t/types'

export type TestSpec = types.TestSpec

type TestBuckets = { [string]: { TestSpec } }

local test_buckets = {} :: TestBuckets
local active_module_identity = nil :: string?

local function bucket_for(module_identity: string): { TestSpec }
	local bucket = test_buckets[module_identity]
	if bucket ~= nil then return bucket end

	bucket = {}
	test_buckets[module_identity] = bucket
	return bucket
end

local function clear_bucket(bucket: { TestSpec })
	while #bucket > 0 do
		table.remove(bucket)
	end
end

local function begin(module_identity: string)
	active_module_identity = module_identity
	clear_bucket(bucket_for(module_identity))
end

local function register(test: TestSpec)
	local module_identity = active_module_identity
	if module_identity == nil then return end

	table.insert(bucket_for(module_identity), test)
end

local function collect(module_identity: string): { TestSpec }
	return bucket_for(module_identity)
end

local function clear(module_identity: string?)
	if module_identity == nil then
		active_module_identity = nil

		for _, bucket in test_buckets do
			clear_bucket(bucket)
		end

		return
	end

	clear_bucket(bucket_for(module_identity))
	if active_module_identity == module_identity then
		active_module_identity = nil
	end
end

local function is_active(): boolean
	return active_module_identity ~= nil
end

return {
	begin = begin,
	clear = clear,
	collect = collect,
	is_active = is_active,
	register = register,
}
