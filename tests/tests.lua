--[[
LibSerializer-1.0 - Chat-safe (un)serializer library.
(c) 2014 Adirelle (adirelle@gmail.com)

This file is part of LibSerializer-1.0.

LibSerializer-1.0 is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

LibSerializer-1.0 is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with LibSerializer-1.0.  If not, see <http://www.gnu.org/licenses/>.
--]]

package.path = package.path .. ";./wowmock/?.lua"
local LuaUnit = require('luaunit')
local wowmock = require('wowmock')

local lib

tests = {}

function tests:setup()
    lib = wowmock("../LibSerializer-1.0.lua")
end

local function dataprovider(name, ...)
	local method = tests[name]
	tests[name] = nil
	for i = 1, select('#', ...) do
		local args = select(i, ...)
		tests[name.."_"..i] = function()
			return method(tests, unpack(args))
		end
	end
end

function tests:test_serialize(input, expected)
	assertEquals(lib:serialize(input), expected)
end

dataprovider('test_serialize',
	{ 0, "10" },
	{ true, "1t" },
	{ false, "1f" },
	{ {}, "1e" },
	{ nil, "1z" },
	{ 45, "1n45:" },
	{ 1/3, "1d6004799503160661:-54:" },
	{ "FooBar", "1sFooBar:" },
	{ "Foo Bar !", "1~Foo~`Bar~`!:" },
	{ "FooBar~", "1~FooBar~~:", },
	{ "a:b", "1~a~1b:" },
	{ { a = 5, "b" }, "1T1sb:sa:5z" },
	{ { { b = 8 } }, "1T1Tsb:8zz" },
	{ { "aaaaa", "bb:bb", "aaaaa", "c", "bb:bb" }, "1T1saaaaa:2~bb~1bb:3<0:4sc:5<1:z" }
)

function tests:test_serialize_error_function()
	assertEquals(pcall(lib.serialize, lib, function() end), false)
end

function tests:test_serialize_error_coroutine()
	local function bla()
	end
	assertEquals(pcall(lib.serialize, lib, coroutine.create(bla)), false)
end

function tests:test_serialize_references()
	local a = { 5 }
	local b = { 8, a }
	local c = {}
	a[2] = b
	a[3] = c
	a[4] = c
	assertEquals(lib:serialize(a), "1T152T182r0:z3e4r2:z")
end

function tests:test_deserialize(expected, input)
	assertEquals(lib:unserialize(input), expected)
end

dataprovider('test_deserialize',
	{ 0, "10" },
	{ true, "1t" },
	{ false, "1f" },
	{ {}, "1e" },
	{ nil, "1z" },
	{ 45, "1n45:" },
	{ 1/3, "1d6004799503160661:-54:" },
	{ "FooBar", "1sFooBar:" },
	{ "Foo Bar !", "1~Foo~`Bar~`!:" },
	{ "FooBar~", "1~FooBar~~:", },
	{ "a:b", "1~a~1b:" },
	{ { a = 5, "b" }, "1T1sb:sa:5z" },
	{ { { b = 8 } }, "1T1Tsb:8zz" },
	{ { "aaaaa", "bb:bb", "aaaaa", "c", "bb:bb" }, "1T1saaaaa:2~bb~1bb:3<0:4sc:5<1:z" }
)

function tests:test_deserialize_error(input)
	local success, message = pcall(lib.unserialize, lib, input)
	assertEquals(success, false)
end

dataprovider('test_deserialize_error',
	{ "" },
	{ "zz" },
	{ "1:zz" },
	{ "1w" },
	{ 5 },
	{ "1n48" },
	{ "1s575997" },
	{ "1s575:7898" },
	{ "1T0102" },
	{ "1~Foo~5ar:" },
	{ "1~FooBar~:" }
)

function tests:test_deserialize_references()
	local a = lib:unserialize("1T152T182r0:z3e4r2:z")
	assertEquals(a[1], 5)
	local b = a[2]
	assertEquals(b[1], 8)
	local c = a[3]
	assertEquals(b[2] == a, true)
	assertEquals(a[4] == c, true)
end

os.exit(LuaUnit:Run())