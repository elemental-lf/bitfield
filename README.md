sparsebitfield
==============

This is a fork of https://github.com/stestagg/bitfield which has been
adapted to be efficient with sparse bitfields and large numbers. The
API is the same but support for Python 2 has been dropped.

There currently seems to be a bug in bitfield.fill_range with very large
numbers which I couldn't find, yet.  The rest looks okay and the tests 
apart from this one case are successful.

__WARNING__ : The serialisation mechanism is not currently portable.

Installation
------------

```
$ sudo pip3 install --upgrade git+https://github.com/elemental-lf/sparsebitfield
```

Usage
-----

```python
>>> import sparsebitfield
>>> field = sparsebitfield.SparseBitfield()
>>> field.add(100)
>>> print list(field)
[100L]
>>> second = sparsebitfield.SparseBitfield([2, 100])
>>> list(field | second)
[2L, 100L]

>>> second.add(10000)
>>> second.pickle()
'BZ:x\x9cca@\x00\x01\x86Q0\nF\xc1(\x18N\x80\x11\x00e\xe0\x00\x16'

>>> large=sparsebitfield.SparseBitfield(random.sample(xrange(1000000), 500000)) # 500,000 items, randomly distributed
>>> len(large)
500000
>>> len(large.pickle())
125049  # 122KB

>>> large=sparsebitfield.SparseBitfield(xrange(1000000)) # 1 million items, all sequential
>>> len(large)
1000000
>>> len(large.pickle())
36 # <40 bytes
```

Bitfields support most of the same operations/usage as regular sets, see the tests for examples.

Design
------

Bitfield was designed to efficiently handle tracking large sets of items.

The main design goals were:
 * Space-efficient serialisation format (well, RLE would be useful, too...)
 * Fast membership tests and set differences
 * Space-efficent handling of large sparse bitfields
 * Support for large integers (>2**64)

Internally, bitfield achieves this by using a 1-d bitmap split into pages. 
These pages are organised as a sorted list.

Within a page, a number is recorded as being present in the set by setting
the n-th bit to 1.  I.e.  the set([1]) is recorded as ...00000010b, while
set([1,4]) would be ...00010010b.

If a particular page is empty (no set members in that range) or full, then
the bitfield is discarded, and represented by an EMPTY or FULL flag.  Pages
which haven not been written to don't take up any memory at all.
