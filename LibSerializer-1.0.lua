--[[
LibSerializer-1.0 - chat-safe (un)serializer library.
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

local MAJOR, MINOR, lib = "LibSerializer-1.0", 1
if LibStub then
	lib = LibStub:NewLibrary(MAJOR, MINOR)
	if not lib then return end
else
	lib = {}
end

local _G = _G
local assert = _G.assert
local error = _G.error
local format = _G.format
local frexp = _G.frexp
local gsub = _G.gsub
local next = _G.next
local pairs = _G.pairs
local pcall = _G.pcall
local strchar = _G.strchar
local strfind = _G.strfind
local strlen = _G.strlen
local strsub = _G.strsub
local strtrim = _G.strtrim
local tconcat = _G.table.concat
local tonumber = _G.tonumber
local tostring = _G.tostring
local type = _G.type
local wipe = _G.wipe

-- Format version
lib.FORMAT = 1

--[[
Format of different values:

nil: "z"
true: "t"
false: "f"

0: "0"
1: "1"
...
8: "8"
9: "9"
number: "n" number ":"
floating number: "d" integer_mantissa ":" exponent ":"

"": "S"
string: either:
	"s" string ":"
	"~" escaped_string ":"     if the string contains unsafe characters
	"<" reference_number ":"   if the string has already been seen
	Only strings whose serialized length is greater than 4 can be referenced.

{}: "e"
table: either:
	"T" serialized_key1 serialized_value1 ... serialized_keyN serialized_valueN "z"
	"r" reference_number ":" if the table has already been seen
--]]

local REF_MIN_LENGTH = 2

-- Used for table references
local tableRefs, numTableRefs = {}, 0

-- Used for string references
local stringRefs, numStringRefs = {}, 0

------------------------------------------------------------------------------
-- Serialization
------------------------------------------------------------------------------

do
	-- Holds the strings during serialization
	local output = {}
	local position = 1

	local function escapeChar(char)
		if char == '~' then
			return '~~'
		elseif char == ":" then
			return '~1'
		elseif char == "|" then
			return '~2'
		elseif char == "\127" then
			return '~?'
		end
		local byte = strbyte(char)
		if byte >= 0 and byte <= 32 then
			return '~'..strchar(64+byte)
		end
		error(format("do not know how to escape '%s'\n", char))
	end

	function writeValue(value)
		if value == false then
			output[position] = "f"

		elseif value == true then
			output[position] = "t"

		elseif value == "" then
			output[position] = "S"

		elseif value == nil then
			output[position] = "z"

		elseif value == 0 or value == 1 or value == 2 or value == 3 or value == 4
			or value == 5 or value == 6 or value == 7 or value == 8 or value == 9 then
			output[position] = tostring(value)

		else
			local type_ = type(value)
			local data

			if type_ == "table" then
				local refNum = tableRefs[value]
				if refNum then
					output[position] = "r"
					data = tostring(refNum)
				else
					tableRefs[value] = numTableRefs
					numTableRefs = numTableRefs + 1
					local k, v = next(value)
					output[position] = k and "T" or "e"
					position = position + 1
					if not k then
						return
					end
					while k do
						writeValue(k)
						writeValue(v)
						k, v = next(value, k)
					end
					output[position] = "z"
					position = position + 1
					return
				end

			elseif type_ == "number" then
				local str = tostring(value)
				if tonumber(str) == value then
					output[position] = "n"
					data = str
				else
					local m, e = frexp(value)
					output[position] = format("d%.0f:", m*2^53)
					data = tostring(e-53)
				end

			elseif type_ == "string" then
				local refNum = stringRefs[value]
				if refNum then
					output[position] = "<"
					data = tostring(refNum)
				else
					if strlen(value) > 4 then
						stringRefs[value] = numStringRefs
						numStringRefs = numStringRefs + 1
					end
					local escapingCount
					data, escapingCount = gsub(value, "[%c \127:~]", escapeChar)
					output[position] = escapingCount > 0 and "~" or "s"
				end

			else
				error(format("cannot serialize %s", type_))
			end

			output[position+1] = data
			output[position+2] = ":"
			position = position + 2
		end

		position = position + 1
	end

	-- Always start with the format number
	position = 1
	writeValue(lib.FORMAT)
	local startPosition = position

	function lib:serialize(value)
		position, numTableRefs, numStringRefs = startPosition, 0, 0
		local success, message = pcall(writeValue, value)
		wipe(tableRefs)
		wipe(stringRefs)
		if success then
			return tconcat(output, "", 1, position-1)
		end
		error(format("serialize: %s", strtrim(message)), 2)
	end
end

------------------------------------------------------------------------------
-- String unescaping
------------------------------------------------------------------------------

local function unescapeChar(seq)
	if seq == '~~' then
		return '~'
	elseif seq == "~1" then
		return ':'
	elseif seq == "~2" then
		return '|'
	elseif seq == "~?" then
		return '\127'
	end
	local byte = strbyte(seq, 2)
	if byte and byte >= 64 and byte <= 96 then
		return strchar(byte - 64)
	end
	error(format("unknown escape sequence '%s'\n", seq))
end

local function unescapeString(str)
	return gsub(str, "%~.?", unescapeChar)
end

------------------------------------------------------------------------------
-- Unserialization
------------------------------------------------------------------------------

local function unserialize(input)
	local position, length = 1, strlen(input)

	local function readValue()
		assert(position <= length, "unterminated serialized data\n")
		local code = strsub(input, position, position)
		position = position + 1

		if code == "f" then
			return false

		elseif code == "t" then
			return true

		elseif code == "S" then
			return ""

		elseif code == "z" then
			return nil

		elseif code == "0" or code == "1" or code == "2" or code == "3" or code == "4"
			or code == "5" or code == "6" or code == "7" or code == "8" or code == "9" then
			return tonumber(code)

		elseif code == "e" or code == "T" then
			local t = {}
			tableRefs[numTableRefs] = t
			numTableRefs = numTableRefs + 1
			if code == "T" then
				local k = readValue()
				while k ~= nil do
					t[k] = readValue()
					k = readValue()
				end
			end
			return t
		end

		if code ~= "n" and code ~= "d" and code ~= "r" and code ~= "<" and code ~= "s" and code ~= "~" then
			error(format("unknown code '%s' at position %d\n", code, position - 1))
		end

		local _, terminator, data = strfind(input, '([^:]+):', position)
		assert(terminator, "unterminated serialized data\n")
		position = terminator + 1

		if code == "~" then
			code, data = "s", unescapeString(data)
		end

		if code == "n" then
			return tonumber(data)

		elseif code == "s" then
			if strlen(data) > 4 then
				stringRefs[numStringRefs] = data
				numStringRefs = numStringRefs + 1
			end
			return data

		elseif code == "<" then
			local idx = tonumber(data)
			assert(idx <= numStringRefs, format("invalid string backreference: %d\n", idx))
			return stringRefs[idx]

		elseif code == "r" then
			local idx = tonumber(data)
			assert(idx <= numTableRefs, format("invalid table backreference: %d\n", idx))
			return tableRefs[idx]

		end

		-- "d"
		local _, terminator, exponent = strfind(input, '([^:]+):', position)
		assert(terminator, "unterminated serialized data\n")
		position = terminator + 1
		return tonumber(data) * 2 ^ tonumber(exponent)
	end

	local version = readValue()
	assert(version == 1, format("unknown format version: %s", version or "nil"))
	local value = readValue()
	assert(position == length + 1, format("garbage at position %d", position))
	return value
end

function lib:unserialize(str)
	numTableRefs, numStringRefs = 0, 0
	local success, valueOrMessage = pcall(unserialize, str)
	wipe(tableRefs)
	wipe(stringRefs)
	if success then
		return valueOrMessage
	end
	error(format("unserialize: %s", strtrim(valueOrMessage)), 2)
end

return lib
