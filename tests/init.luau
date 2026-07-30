local ok = require '@lib'
local t = require '@vendor/t'

t.suite('ok public API integration', function()
	t.test('observes an original method through a spy', function()
		local target = {
			save = function(_, profile, slot)
				return `{profile}:{slot}`
			end,
		}

		local spy = ok.mock.spy(target, 'save')
		local result = target:save('ada', 2)

		ok.eq('ada:2', result)
		ok.called(spy)
		ok.calledWith(spy, 'ada', 2)
		ok.eq('ada', spy.calls[1].args[1])
		ok.eq('ada:2', ok.isNotNil(spy.calls[1].returns)[1])

		ok.mock.restore(spy)
	end)

	t.test('uses queued stub results before restoring the method', function()
		local target = {
			load = function(_, profile)
				return `original:{profile}`
			end,
		}

		local stub = ok.mock.stub(target, 'load')

		ok.mock.returns(stub, 'default')
		ok.mock.returnsOnce(stub, 'first')
		ok.mock.returnsOnce(stub, 'second')

		ok.eq('first', target:load 'ada')
		ok.eq('second', target:load 'lin')
		ok.eq('default', target:load 'kai')

		ok.mock.restore(stub)

		ok.eq('original:ada', target:load 'ada')
	end)

	t.test('controls an intercepted call and resumes its coroutine', function()
		local target = {
			load = function(_, profile)
				return `original:{profile}`
			end,
		}

		local intercept = ok.mock.intercept(target, 'load')
		local result

		local call = ok.mock.capture(intercept, function()
			result = target:load 'ada'
		end)

		ok.eq('ada', call.args[1])
		ok.isNil(ok.mock.respond(call, 'controlled:ada'))
		ok.eq('controlled:ada', result)

		ok.mock.restore(intercept)
	end)
end)
