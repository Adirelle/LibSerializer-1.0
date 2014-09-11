LibSerializer-1.0
=================

LibSerializer-1.0 is a LibStub-based library allowing to (un)serialize Lua values.

[![Build Status](https://travis-ci.org/Adirelle/LibSerializer-1.0.svg?branch=master)](https://travis-ci.org/Adirelle/LibSerializer-1.0)

It gracefully handles circular table references. For obvious reasons, it cannot (un)serialize functions, userdata nor threads.

The resulting string can be sent across chat channels or used in hyperlinks.

Usage
-----

```lua
local serializer = LibStub('LibSerializer-1.0')

-- Serialize a value
local blob = serializer:serializer(someValue)

-- Unserialize a value
local value = serializer:unserializer(blob)
```

License
-------

LibSerializer-1.0 is licensed with the GNU Public License version 3.0.
