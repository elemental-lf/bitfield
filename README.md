sparsebitfield
==============

This is a fork of https://github.com/stestagg/bitfield which has been
adapted to be efficient with sparse bitfields and large numbers. The
API is the same but support for Python 2 has been dropped.

__WARNING__ : The serialisation mechanism isn't portable at the moment.

Installation
------------

```
$ sudo pip3 install sparsebitfield
```

Usage
-----

```python
>>> import sparsebitfield
>>> field = sparsebitfield.SparseBitfield()
>>> field.add(100)
>>> print(list(field))
[100]
>>> second = sparsebitfield.SparseBitfield([2, 100])
>>> list(field | second)
[2, 100]

>>> second.add(10000)
>>> second.pickle()
b'BZ:x\x9c\xed\xce\xc1\t\x00 \x0c\x04\xb0+8@\xf7\x9f\xd6\x87\x0f7P(\xc9\x04I\x8eZ\xb9:\x00\x93\xd4\xef\x00\x00\x00\x00\x00\x00\x00<\xb3\x01\xda\x86\x00\x17'

>>> import random
>>> large=sparsebitfield.SparseBitfield(random.sample(range(1000000), 500000)) # 500,000 items, randomly distributed
>>> len(large)
500000
>>> len(large.pickle())
125269  # 122KB

>>> large=sparsebitfield.SparseBitfield(range(1000000)) # 1 million items, all sequential
>>> len(large)
1000000
>>> len(large.pickle())
69 # <100 bytes
```

Sparse bitfields support most of the same operations/usage as regular sets,
see the tests for examples.

Design
------

Sparsebitfield was designed to efficiently handle tracking large sets of items.

The main design goals were:
 * Space-efficient serialisation format
 * Fast membership tests and set differences
 * Space-efficent handling of large sparse bitfields
 * Support for large integers (>2**64)

Internally, sparsebitfield achieves this by using a 1-d bitmap split into
pages.  These pages are organised as a sorted list.

Within a page, a number is recorded as being present in the set by setting
the n-th bit to 1.  I.e.  the set([1]) is recorded as ...00000010b, while
set([1,4]) would be ...00010010b.

If a particular page is empty (no set members in that range) or full, then
the bitfield is discarded, and represented by an EMPTY or FULL flag.  Pages
which haven not been written to don't take up any memory at all. Also empty
pages are not included in the pickled data.
