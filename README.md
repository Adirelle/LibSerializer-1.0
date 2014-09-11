LibSerializer-1.0
=================

LibSerializer-1.0 is a LibStub-based library allowing to (un)serialize Lua values.

[![Build Status](https://travis-ci.org/Adirelle/LibSerializer-1.0.svg?branch=master)](https://travis-ci.org/Adirelle/LibSerializer-1.0)

It gracefully handles circular table references. For obvious reasons, it cannot (un)serialize functions, userdata nor threads.

The resulting string can be sent across chat channels or used in hyperlinks.

LibSerializer-1.0 is **not** compatible with AceSerializer-3.0.

Prior testing shows that LibSerializer-1.0 is 30% slower than AceSerializer-3.0 but produces 40% smaller strings (based on 100 serializer/unserialize iterations on a table stored in a 360kbytes-long SavedVariables file).

Usage
-----

```lua
local serializer = LibStub('LibSerializer-1.0')

-- Serialize a value
local blob = serializer:serialize(someValue)

-- Unserialize a value
local value = serializer:unserialize(blob)
```

License
-------

LibSerializer-1.0 is licensed with the GNU Public License version 3.0.
