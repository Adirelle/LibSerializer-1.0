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

-- Format version
lib.FORMAT = 1

-- Type constants
local NIL = "z" -- [z]ero
local TRUE = "t"
local FALSE = "f"

local NUMBER = "n"
local FLOAT = "d" -- [d]ouble, f is already taken

local STRING = "s"
local EMPTY_STRING = "S"
local ESCAPED_STRING = "\126"
local STRING_REF = "<"

local TABLE = "T" -- "t" is already taken
local EMPTY_TABLE = "e"
local TABLE_REF = "r"

local TERMINATOR = ":"

--[[
Format of different values (UPPERCASE NAMES stand for constants, lowercase ones for values):

nil: NIL
true: TRUE
false: FALSE

0: 0
1: 1
...
8: 8
9: 9
number: NUMBER number TERMINATOR
floating number: FLOAT integer_mantissa TERMINATOR exponent TERMINATOR

"": EMPTY_STRING
string: either:
	STRING string TERMINATOR
	ESCAPED_STRING escaped_string TERMINATOR if the string contains unsafe characters
	STRING_REF reference_number TERMINATOR   if the string has already been seen
	Only strings whose serialized length is greater than 4 can be referenced.

{}: EMPTY_TABLE
table: either:
	TABLE serialized_key1 serialized_value1 ... serialized_keyN serialized_valueN NIL
	TABLE_REF reference_number TERMINATOR if the table has already been seen
--]]

-- Used for table references
local tableRefs, numTableRefs = {}, 0

-- Used for string references
local stringRefs, numStringRefs = {}, 0

------------------------------------------------------------------------------
-- String escaping
------------------------------------------------------------------------------

local escapeTable = {
	[ESCAPED_STRING] = ESCAPED_STRING..ESCAPED_STRING,
	[TERMINATOR]     = ESCAPED_STRING..'1',
	["\127"]         = ESCAPED_STRING..'?',
	['|']            = ESCAPED_STRING..'3',
}
for ascii = 0, 32 do
	escapeTable[strchar(ascii)] = ESCAPED_STRING..strchar(64+ascii)
end

local function escapeChar(raw)
	return assert(escapeTable[raw], format("do not know how to escape '%s'\n", raw))
end

local escapeRE = format("[%%c \127%%%s%%%s]", TERMINATOR, ESCAPED_STRING)

local function escapeString(str)
	return gsub(str, escapeRE, escapeChar)
end

------------------------------------------------------------------------------
-- Serialization
------------------------------------------------------------------------------

-- Holds the strings during serialization
local output = {}

local function writeNumber(position, num)
	output[position] = tostring(num)..TERMINATOR
	return position + 1
end

local writeValue

local writersByType = {
	["number"] = function(position, num)
		if tonumber(tostring(num)) == num then
			return NUMBER, writeNumber(position, num)
		end
		local m, e = frexp(num)
		output[position] = format("%.0f%s%d%s", m*2^53, TERMINATOR, e-53, TERMINATOR)
		return FLOAT, position + 1
	end,
	["string"] = function(position, str)
		if stringRefs[str] then
			return STRING_REF, writeNumber(position, stringRefs[str])
		end
		local safeString, isEscaped = escapeString(str)
		output[position] = safeString .. TERMINATOR
		if strlen(safeString) > 4 then
			stringRefs[str] = numStringRefs
			numStringRefs = numStringRefs + 1
		end
		return isEscaped > 0 and ESCAPED_STRING or STRING, position + 1
	end,
	["table"] = function(position, table_)
		if tableRefs[table_] then
			return TABLE_REF, writeNumber(position, tableRefs[table_])
		end
		tableRefs[table_] = numTableRefs
		numTableRefs = numTableRefs + 1
		if not next(table_) then
			return EMPTY_TABLE, position
		end
		for key, value in pairs(table_) do
			position = writeValue(writeValue(position, key), value)
		end
		output[position] = NIL
		return TABLE, position + 1
	end,
	["nil"] = function(position)
		return NIL, position
	end,
}

-- Constants serialized using one character
local writeConstants = {
	[false] = FALSE,
	[true] = TRUE,
	[""] = EMPTY_STRING
}
for integer = 0, 9 do
	writeConstants[integer] = tostring(integer)
end

function writeValue(position, value)
	local constant = writeConstants[value]
	if constant then
		output[position] = constant
		return position + 1
	end
	local writer = writersByType[type(value)]
	assert(writer, format("unsupported type: %s\n", type(value)))
	output[position], position = writer(position+1, value)
	return position
end

function lib:serialize(value)
	numTableRefs, numStringRefs = 0, 0
	local startPos = writeNumber(1, lib.FORMAT)
	local success, lengthOrMessage = pcall(writeValue, startPos, value)
	wipe(tableRefs)
	wipe(stringRefs)
	if success then
		return tconcat(output, "", 1, lengthOrMessage-1)
	end
	error(format("serialize: %s", strtrim(lengthOrMessage)), 2)
end

------------------------------------------------------------------------------
-- String unescaping
------------------------------------------------------------------------------

local unescapeTable = {}
for raw, escaped in pairs(escapeTable) do
	unescapeTable[escaped] = raw
end

local function unescapeChar(escaped)
	return assert(unescapeTable[escaped], format("invalid escape sequence: '%s'\n", escaped))
end

local unescapeRe = '%'..ESCAPED_STRING..'.?'

local function unescapeString(str)
	return gsub(str, unescapeRe, unescapeChar)
end

------------------------------------------------------------------------------
-- Unserialization
------------------------------------------------------------------------------

local function readTerminatedString(data, position, what)
	assert(position < strlen(data), "unterminated serialized data\n")
	local terminatorPos = strfind(data, TERMINATOR, position, true)
	assert(terminatorPos, format("unterminated %s starting at position %d\n", what, position))
	return strsub(data, position, terminatorPos-1), terminatorPos + 1
end

local function readNumber(data, position, what)
	local str, endPosition = readTerminatedString(data, position, what)
	local value = tonumber(str)
	assert(value, format("invalid %s starting at position %d\n", what, position))
	return value, endPosition
end

local readValue

local readersByCode = {
	[NIL] = function(data, position)
		return nil, position
	end,
	[STRING] = function(data, position)
		local str, position = readTerminatedString(data, position, "string")
		if strlen(str) > 4 then
			stringRefs[numStringRefs] = str
			numStringRefs = numStringRefs + 1
		end
		return str, position
	end,
	[ESCAPED_STRING] = function(data, position)
		local rawStr, position = readTerminatedString(data, position, "escaped string")
		local str = unescapeString(rawStr)
		if strlen(rawStr) > 4 then
			stringRefs[numStringRefs] = str
			numStringRefs = numStringRefs + 1
		end
		return str, position
	end,
	[STRING_REF] = function(data, position)
		local idx, position = readNumber(data, position, "string reference")
		assert(idx <= numStringRefs, format("string reference out of bound: %d\n", idx))
		return stringRefs[idx], position
	end,
	[NUMBER] = function(data, position)
		return readNumber(data, position, "number")
	end,
	[FLOAT] = function(data, position)
		local m, e
		m, position = readNumber(data, position, "mantissa")
		e, position = readNumber(data, position, "exponent")
		return m*(2^e), position
	end,
	[TABLE] = function(data, position)
		local table_, key = {}
		tableRefs[numTableRefs] = table_
		numTableRefs = numTableRefs + 1
		key, position = readValue(data, position)
		while key ~= nil do
			table_[key], position = readValue(data, position)
			key, position = readValue(data, position)
		end
		return table_, position
	end,
	[EMPTY_TABLE] = function(data, position)
		local output = {}
		tableRefs[numTableRefs] = output
		numTableRefs = numTableRefs + 1
		return output, position
	end,
	[TABLE_REF] = function(data, position)
		local idx, position = readNumber(data, position, "table reference")
		assert(idx <= numTableRefs, format("table reference out of bound: %d\n", idx))
		return tableRefs[idx], position
	end,
}

-- Constants unserializing
local readConstants = {}
for constant, serialized in pairs(writeConstants) do
	readConstants[serialized] = constant
end

function readValue(data, position)
	assert(position <= strlen(data), "unterminated serialized data\n")
	local code = strsub(data, position, position)
	local constant = readConstants[code]
	if constant ~= nil then
		return constant, position + 1
	end
	local reader = readersByCode[code]
	assert(reader, format("invalid code at position %d: '%s'\n", position, code))
	return reader(data, position + 1)
end

local function unserialize(str)
	assert(type(str) == "string", format("attempt to unserialize a %s\n", type(str)))
	assert(str ~= "", "attempt to unserialize an empty string\n")

	local version, position = readNumber(str, 1, "format")
	assert(version == 1, format("unknown format version %d\n", version))

	local value, position = readValue(str, position)

	assert(position == 1+strlen(str), format("garbage starting at position %d\n", position))

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
