import sys
import zlib
from sortedcontainers import SortedDict

cimport cpython.buffer as pybuf
from cpython.mem cimport PyMem_Malloc, PyMem_Free

ctypedef Py_ssize_t size_t

cdef extern from "string.h":
    void *memcpy(void*, void*, size_t)


IF UNAME_SYSNAME == "Windows":
    cdef extern from "popcount.h":
        int __builtin_popcountl(unsigned int)
ELSE:
    cdef extern:
        int __builtin_popcountl(size_t)


cdef extern from "field.h":
    ctypedef unsigned long usize_t
    ctypedef unsigned long CHUNK
    const usize_t CHUNK_BYTES
    const usize_t CHUNK_FULL_COUNT
    const usize_t CHUNK_SHIFT
    const usize_t CHUNK_MASK
    const usize_t USIZE_MAX
    const usize_t CHUNK_BITS
    const usize_t PAGE_CHUNKS
    const usize_t PAGE_FULL_COUNT
    const usize_t PAGE_BYTES
    const usize_t EMPTY_CHUNK_BITS
    const usize_t FULL_CHUNK_BITS

DEF PAGE_EMPTY = 3
DEF PAGE_PARTIAL = 1
DEF PAGE_FULL = 2


def get_all_sizes():
    return dict(
        CHUNK_BYTES=CHUNK_BYTES,
        CHUNK_SHIFT=CHUNK_SHIFT,
        CHUNK_MASK=bin(CHUNK_MASK),
        CHUNK_FULL_COUNT=CHUNK_FULL_COUNT,
        CHUNK_BITS=bin(CHUNK_BITS),
        BITFIELD_MAX=USIZE_MAX,
        PAGE_CHUNKS=PAGE_CHUNKS,
        PAGE_FULL_COUNT=PAGE_FULL_COUNT,
        PAGE_BYTES=PAGE_BYTES,
        PAGE_MAX=PAGE_FULL_COUNT
    )


cdef class IdsPage:
    cdef int page_state
    cdef usize_t _count
    cdef CHUNK* data

    def __cinit__(self):
        self.page_state = PAGE_EMPTY
        self._count = 0
        self.data = NULL

    def __dealloc__(self):
        self._dealloc(PAGE_EMPTY)

    cdef void _fill(self, CHUNK value):
        cdef usize_t current
        for current in range(PAGE_CHUNKS):
            self.data[current] = value

    cdef void set_full(self):
        self._dealloc(PAGE_FULL)

    cdef void set_empty(self):
        self._dealloc(PAGE_EMPTY)

    cdef void _alloc(self, bint fill=0):
        assert(self.data == NULL)
        self.page_state = PAGE_PARTIAL
        self.data = <CHUNK *>PyMem_Malloc(sizeof(CHUNK) * PAGE_CHUNKS)
        if fill:
            self._count = PAGE_FULL_COUNT
            self._fill(CHUNK_BITS)
        else:
            self._count = 0
            self._fill(0)     

    cdef void _dealloc(self, int new_state):
        assert new_state != PAGE_PARTIAL
        self.page_state = new_state
        self._count = 0 if new_state == PAGE_EMPTY else PAGE_FULL_COUNT
        if self.data != NULL:
            PyMem_Free(self.data)
            self.data = NULL

    def __iter__(self):
        cdef usize_t chunk = 0
        cdef usize_t bit_index = 0
        cdef usize_t number = 0

        if self.page_state == PAGE_EMPTY:
            return
        elif self.page_state == PAGE_FULL:
            for number in range(0, PAGE_FULL_COUNT):
                yield number
        else:
            while chunk < PAGE_CHUNKS:
                # If the page is changing under our feet
                if self.page_state == PAGE_EMPTY:
                    return  
                elif (self.data[chunk] & ((<usize_t>1) << bit_index)) != 0:
                    yield number

                number += 1
                bit_index += 1
                if bit_index >= CHUNK_FULL_COUNT:
                    bit_index = 0
                    chunk += 1
                    # Skip empty chunks
                    while chunk < PAGE_CHUNKS and self.data[chunk] == 0:
                        chunk += 1
                        number += CHUNK_FULL_COUNT

    cdef void calc_length(self):
        cdef CHUNK *chunk
        cdef usize_t chunk_index
        cdef usize_t bits = 0
        if self.page_state != PAGE_PARTIAL:
            return
        else:    
            for chunk_index in range(PAGE_CHUNKS):
                bits += __builtin_popcountl(self.data[chunk_index])
            if bits == 0:
                self._dealloc(PAGE_EMPTY)
            elif bits == PAGE_FULL_COUNT:
                self._dealloc(PAGE_FULL)
            else:
                self._count = bits

    property count:
        def __get__(self):
            return self._count

    def __contains__(self, usize_t number):
        cdef usize_t chunk_index = number >> CHUNK_SHIFT
        cdef usize_t chunk_bit = (<usize_t>1) << (number & CHUNK_MASK)
        if chunk_index >= PAGE_CHUNKS or chunk_index < 0:
            raise AssertionError("Cannot test for %i in a page (overflow)" % number)
        if self.page_state == PAGE_FULL:
            return True
        if self.page_state == PAGE_EMPTY:
            return False
        return self.data[chunk_index] & chunk_bit != 0

    cdef void add(self, usize_t number):
        cdef usize_t chunk_index = number >> CHUNK_SHIFT
        cdef usize_t chunk_bit = (<usize_t>1) << (number & CHUNK_MASK)

        if chunk_index >= PAGE_CHUNKS or chunk_index < 0:
            raise AssertionError("Cannot add %i to a page (overflow)" % number)

        if self.page_state == PAGE_FULL:
            return
        if self.page_state == PAGE_EMPTY:
            self._alloc()

        if self.data[chunk_index] & chunk_bit:
            return

        self.data[chunk_index] |= chunk_bit
        self._count += 1
        if self._count == PAGE_FULL_COUNT:
            self._dealloc(PAGE_FULL)
        return

    cdef void remove(self, usize_t number):
        cdef usize_t chunk_index = number >> CHUNK_SHIFT
        cdef usize_t chunk_bit = (<usize_t>1) << (number & CHUNK_MASK)

        if chunk_index >= PAGE_CHUNKS or chunk_index < 0:
            raise AssertionError("Cannot remove %i from a page (overflow)" % number)

        if self.page_state == PAGE_EMPTY:
            return
        if self.page_state == PAGE_FULL:
            self._alloc(True)

        if not self.data[chunk_index] & chunk_bit:
            return

        self.data[chunk_index] &= ~chunk_bit
        self._count -= 1
        if self._count == 0:
            self._dealloc(PAGE_EMPTY)
        return

    cdef void update(self, IdsPage other):
        if other.page_state == PAGE_EMPTY:
            return
        if self.page_state == PAGE_FULL:
            return
        if other.page_state == PAGE_FULL:
            self._dealloc(PAGE_FULL)
            return
        if self.page_state == PAGE_EMPTY:
            self._alloc()
        for chunk_index in range(PAGE_CHUNKS):
            self.data[chunk_index] |= other.data[chunk_index]
        self.calc_length()

    cdef void intersection_update(self, IdsPage other):
        if other.page_state == PAGE_EMPTY:
            self._dealloc(PAGE_EMPTY)
        elif other.page_state == PAGE_FULL:
            return
        elif other.page_state == PAGE_PARTIAL:
            if self.page_state == PAGE_EMPTY:
                return
            elif self.page_state == PAGE_FULL:
                self._dealloc(PAGE_EMPTY)
                memcpy(self.data, other.data, CHUNK_BYTES * PAGE_CHUNKS)
                self.calc_length()
                return
            elif self.page_state == PAGE_PARTIAL:
                for chunk_index in range(PAGE_CHUNKS):
                    self.data[chunk_index] &= other.data[chunk_index]
                self.calc_length()
            else:
                raise AssertionError("Invalid page state")
        else:
            raise AssertionError("Invalid page state")

    cdef void difference_update(self, IdsPage other):
        if other.page_state == PAGE_EMPTY:
            return
        if self.page_state == PAGE_FULL:
            self._alloc(True)
        if other.page_state == PAGE_FULL:
            self._dealloc(PAGE_EMPTY)
            return
        if self.page_state == PAGE_EMPTY:
            return
        for chunk_index in range(PAGE_CHUNKS):
            self.data[chunk_index] &= ~other.data[chunk_index]
        self.calc_length()

    cdef symmetric_difference_update(self, IdsPage other):
        cdef usize_t chunk_index
        if self.page_state == PAGE_EMPTY:
            if other.page_state == PAGE_EMPTY:
                return
            elif other.page_state == PAGE_FULL:
                self._dealloc(PAGE_FULL)
                return
            elif other.page_state == PAGE_PARTIAL:
                self._alloc()
                memcpy(self.data, other.data, CHUNK_BYTES * PAGE_CHUNKS)
        elif self.page_state == PAGE_FULL:
            if other.page_state == PAGE_EMPTY:
                return
            elif other.page_state == PAGE_FULL:
                self._dealloc(PAGE_EMPTY)
                return
            elif other.page_state == PAGE_PARTIAL:
                self._alloc(True)
                for chunk_index in range(PAGE_CHUNKS):
                    self.data[chunk_index] = ~other.data[chunk_index]
        elif self.page_state == PAGE_PARTIAL:
            if other.page_state == PAGE_EMPTY:
                return
            elif other.page_state == PAGE_FULL:
                for chunk_index in range(PAGE_CHUNKS):
                    self.data[chunk_index] = ~self.data[chunk_index]
            elif other.page_state == PAGE_PARTIAL:
                for chunk_index in range(PAGE_CHUNKS):
                    self.data[chunk_index] ^= other.data[chunk_index]                
        self.calc_length()

    cdef IdsPage clone(self):
        new_page = IdsPage()
        new_page.page_state = self.page_state

        if self.page_state == PAGE_PARTIAL:
            new_page._alloc()
            memcpy(new_page.data, self.data, CHUNK_BYTES * PAGE_CHUNKS)
        new_page._count = self._count
        return new_page

    def __richcmp__(IdsPage a,IdsPage b, operator):
        cdef usize_t current
        if operator == 2:
            if a.count != b.count: # cheap
                return False
            if a.page_state != b.page_state:
                return False
            if a.page_state != PAGE_PARTIAL:
                return True
            for current in range(PAGE_CHUNKS):
                if a.data[current] != b.data[current]:
                    return False
            return True
        elif operator == 3:
            return not a == b
        raise NotImplementedError()

    cdef char *set_bits(self, char *start, char *end):
        cdef usize_t bytes_to_read = min(PAGE_BYTES, (end - start) + 1)
        self._alloc()
        memcpy(self.data, start, bytes_to_read)
        self.calc_length()
        return start + bytes_to_read


# Markers must be the same length
cdef bytes PICKLE_MARKER = <char *>"BF:"
cdef bytes PICKLE_MARKER_zlib = <char *>"BZ:"


cdef class SparseBitfield:
    """Efficient storage, and set-like operations on groups of positive integers
    Currently, all integers must be in the range 0 >= x <= x**79 when usize_t is 64bit
    long."""

    cdef object pages
    __slots__ = ()

    def __cinit__(self, _data=None):
        self.pages = SortedDict({})
        if _data is not None:
            self.load(_data)

    cdef _ensure_page_exists(self, usize_t page):
        if page not in self.pages:
          self.pages[page] = IdsPage()

    cpdef add(self, object number):
        """Add a positive integer to the bitfield"""
        cdef usize_t page_no = number // PAGE_FULL_COUNT
        cdef usize_t page_index = number % PAGE_FULL_COUNT
        self._ensure_page_exists(page_no)
        cdef IdsPage page = self.pages[page_no]
        page.add(page_index)

    cpdef remove(SparseBitfield self, object number):
        """Remove a positive integer from the bitfield
        If the integer does not exist in the field, raise a KeyError"""
        cdef usize_t page_no = number // PAGE_FULL_COUNT
        if page_no not in self.pages:
            raise KeyError()
        cdef usize_t page_index = number % PAGE_FULL_COUNT
        cdef IdsPage page = self.pages[page_no]
        cdef size_t before_count = page.count
        page.remove(page_index)
        cdef size_t after_count = page.count
        if before_count == after_count:
            raise KeyError()

    cpdef discard(SparseBitfield self, object number):
        """Remove a positive integer from the bitfield if it is a member.
        If the element is not a member, do nothing."""
        cdef usize_t page_no = number // PAGE_FULL_COUNT
        if page_no not in self.pages:
            return
        cdef usize_t page_index = number % PAGE_FULL_COUNT
        cdef IdsPage page = self.pages[page_no]
        page.remove(page_index)

    property count:
        """The number of integers in the field"""
        def __get__(self):
            cdef object num = 0
            for page in self.pages.values():
                num += page.count
            return num

    def __len__(self):
        """The number of integers in the field"""
        return self.count

    def __contains__(self, number):
        """Returns true if number is present in the field"""
        cdef usize_t page_no = number // PAGE_FULL_COUNT
        if page_no not in self.pages:
            return False
        cdef usize_t page_index = number % PAGE_FULL_COUNT
        return page_index in self.pages[page_no]

    def __iter__(self):
        """Iterate over all integers in the field"""
        cdef usize_t page_no
        cdef IdsPage page
        cdef usize_t next_item

        for page_no, page in self.pages.items():
             for next_item in page:
                 yield <object>next_item + (<object>page_no * <object>PAGE_FULL_COUNT)

    def __richcmp__(SparseBitfield a,SparseBitfield b, operator):
        cdef usize_t page_no
        if operator == 0:
            return (b != a) and (a.issubset(b))
        if operator == 1:
            return a.issubset(b)
        if operator == 2:
            if len(a.pages) != len(b.pages):
                return False
            for page_no in a.pages.keys():
                if page_no not in b.pages:
                    return False
                if a.pages[page_no] != b.pages[page_no]:
                    return False
            return True
        if operator == 3:
            return not a == b
        if operator == 4:
            return (a != b) and (b.issubset(a))
        if operator == 5:
            return b.issubset(a)
        raise NotImplementedError()

    def __or__(SparseBitfield x, SparseBitfield y):
        """Return a new object that is the union of two bitfields"""
        cdef SparseBitfield new
        new = x.clone()
        new.update(y)
        return new

    def __ior__(SparseBitfield x, SparseBitfield y):
        return x.update(y)

    def union(SparseBitfield self, SparseBitfield other):
        return self | other

    def __add__(SparseBitfield x, usize_t y):
        """Return a new field with the integer added"""
        cdef SparseBitfield new
        new = x.clone()
        new.add(y)
        return new

    def __iadd__(SparseBitfield x, usize_t y):
        """Add a positive integer to the field"""
        x.add(y)
        return x

    def __sub__(SparseBitfield x, SparseBitfield y):
        cdef SparseBitfield new
        new = x.clone()
        new.difference_update(y)
        return new

    def __isub__(SparseBitfield x, SparseBitfield y):
        return x.difference_update(y)

    def __xor__(SparseBitfield self, SparseBitfield other):
        return self.symmetric_difference(other)

    def __ixor__(SparseBitfield self, SparseBitfield other):
        return self.symmetric_difference_update(other)

    def __and__(SparseBitfield self, SparseBitfield other):
        return self.intersection(other)

    def __iand__(SparseBitfield self, SparseBitfield other):
        return self.intersection_update(other)

    cpdef update(self, SparseBitfield other):
        """Add all integers in 'other' to this bitfield"""
        cdef usize_t other_page_no
        cdef IdsPage other_page, page

        for other_page_no, other_page in other.pages.items():
            if other_page.page_state == PAGE_EMPTY:
                continue
            self._ensure_page_exists(other_page_no)
            page = self.pages[other_page_no]
            page.update(other_page)

    cpdef difference_update(self, SparseBitfield other):
        """Remove all integers in 'other' from this bitfield"""
        cdef usize_t other_page_no
        cdef IdsPage other_page, page

        for other_page_no, other_page in other.pages.items():
            if other_page.page_state == PAGE_EMPTY:
                continue
            self._ensure_page_exists(other_page_no)
            page = self.pages[other_page_no]
            page.difference_update(other_page)

    cpdef symmetric_difference_update(self, SparseBitfield other):
        """Update this bitfield to only contain items present in self or other, but not both    """
        cdef usize_t page_no
        cdef IdsPage page

        for page_no, page in self.pages.items():
            if page_no in other.pages:
                page.symmetric_difference_update(other.pages[page_no])

        for page_no, page in other.pages.items():
            if page_no not in self.pages:
                self.pages[page_no] = page.clone()

    cpdef symmetric_difference(self, SparseBitfield other):
        cdef SparseBitfield new = self.clone()
        new.symmetric_difference_update(other)
        return new

    cpdef intersection_update(self, SparseBitfield other):
        """Update the bitfield, keeping only integers found in it and 'other'."""
        cdef usize_t page_no
        cdef IdsPage page

        for page_no, page in self.pages.items():
            if page_no in other.pages:
                page.intersection_update(other.pages[page_no])
            else:
                page.set_empty()

    cpdef intersection(SparseBitfield self, SparseBitfield other):
        """Return a new bitfield with integers common to both this field, and 'other'."""
        cdef SparseBitfield new = self.clone()
        new.intersection_update(other)
        return new

    cpdef isdisjoint(SparseBitfield self, SparseBitfield other):
        """Return True if the bitfield has no integers in common with other. 
        SparseBitfields are disjoint if and only if their intersection is the empty set."""
        return len(self.intersection(other)) == 0

    cpdef issubset(SparseBitfield self, SparseBitfield other):
        return len(self - other) == 0

    cpdef issuperset(SparseBitfield self, SparseBitfield other):
        return other.issubset(self)

    cpdef copy(self):
        """Create a copy of the bitfield"""
        return self.clone()

    cpdef clone(self):
        """Create a copy of the bitfield"""
        new = SparseBitfield()
        cdef usize_t page_no
        cdef IdsPage page

        for page_no, page in self.pages.items():
            if page.page_state == PAGE_EMPTY:
                continue
            new.pages[page_no] = page.clone()

        return new

    def __getbuffer__(self, Py_buffer *view, int flags):
        cdef IdsPage page
        cdef size_t partial_page_count = 0
        cdef size_t buffer_len
        cdef char * pointer
        cdef usize_t page_no = 0

        if flags & pybuf.PyBUF_WRITABLE:
            raise ValueError("sparsebitfields do not provide writable buffers")

        if flags & pybuf.PyBUF_FORMAT:
            view.format = "B"
        
        view.readonly = True
        for page in self.pages.values():
            if page.data:
                partial_page_count += 1
        
        buffer_len = len(self.pages) + (PAGE_BYTES * partial_page_count) + \
                        len(self.pages) * sizeof(page_no)
        view.len = buffer_len
        view.buf = PyMem_Malloc(buffer_len)
        view.itemsize = 1
        view.suboffsets = NULL
        pointer = <char *> view.buf
        for page_no, page in self.pages.items():
            if page.page_state == PAGE_EMPTY:
                continue
            memcpy(<void *> pointer, <void *>&page_no, sizeof(page_no))
            pointer += sizeof(page_no)
            pointer[0] = <unsigned char>page.page_state
            pointer += 1
            if page.data != NULL:
                memcpy(<void *>pointer, <void*>page.data, PAGE_BYTES)
                pointer += PAGE_BYTES

        if flags & pybuf.PyBUF_ND or flags & pybuf.PyBUF_STRIDES:
            view.ndim = 0
            view.shape = NULL
            view.strides = NULL

    def __releasebuffer__(self, Py_buffer *view):
        if view.buf == NULL:
            return
        PyMem_Free(view.buf)

    def pickle(self, compress=True):
        """Return a string representation of the bitfield"""
        cdef bytes marker = PICKLE_MARKER
        cdef bytes base = memoryview(self).tobytes()
        if compress:
            base = zlib.compress(base)
            marker = PICKLE_MARKER_zlib
        return marker + base

    @classmethod
    def unpickle(cls, bytes data):
        """Read a bitfield object from a string created by SparseBitfield.piclke"""
        cdef SparseBitfield new = SparseBitfield()
        new.load_from_bytes(data)
        return new

    def __reduce__(self):
        return (unpickle_sparsebitfield, (self.pickle(), ))

    cdef load(SparseBitfield self, data):
        if isinstance(data, bytes):
            return self.load_from_bytes(data)
        for item in data:
            if isinstance(item, (int, long)):
                self.add(item)
            else:
                low, high = item
                self.fill_range(low, high)

    cdef load_from_bytes(self, bytes data):
        cdef usize_t marker_len = len(PICKLE_MARKER)
        cdef bytes marker = data[:marker_len]
        if marker != PICKLE_MARKER and marker != PICKLE_MARKER_zlib:
            raise ValueError("Could not unpickle data")
        if marker == PICKLE_MARKER_zlib:
            data = zlib.decompress(data[marker_len:])
        cdef usize_t length = len(data)

        cdef char *buf = data
        cdef IdsPage page
        cdef usize_t position = 0
        cdef char page_state
        cdef char *write_position
        cdef usize_t page_no
        while position < length:
            memcpy(<void *>&page_no, <void *>buf + position, sizeof(page_no))
            position += sizeof(page_no)
            page_state = buf[position]
            position += 1
            page = IdsPage()
            if page_state == PAGE_FULL:
                page.set_full()
            elif page_state == PAGE_PARTIAL:
                write_position = page.set_bits(buf + position, buf + position + PAGE_BYTES)
                assert write_position == buf + (position + PAGE_BYTES)
                position += PAGE_BYTES
            else:
                raise ValueError("Could not unpickle data. Invalid page state: %s" % page_state)
            self.pages[page_no] = page

    cdef fill_range(self, object low, object high):
        """Add all numbers in range(low, high) to the bitfield, optimising the case where large
        ranges are supplied"""
        cdef IdsPage page = None

        assert low < high
        # Adjust high so that it represents the last bit to set
        high -= 1
        cdef usize_t lower_page_boundary = low // PAGE_FULL_COUNT
        cdef usize_t lower_page_index = low % PAGE_FULL_COUNT
        cdef usize_t upper_page_boundary = high // PAGE_FULL_COUNT
        cdef usize_t upper_page_index = high % PAGE_FULL_COUNT
        cdef usize_t num, page_no

        # All bits are within one page
        if lower_page_boundary == upper_page_boundary:
            self._ensure_page_exists(lower_page_boundary)
            page = self.pages[lower_page_boundary]
            for num in range(lower_page_index, upper_page_index + 1):
                page.add(num)
            return

        # Fill the lower partial page (if any)
        if lower_page_index != 0:
            self._ensure_page_exists(lower_page_boundary)
            page = self.pages[lower_page_boundary]
            for num in range(lower_page_index, PAGE_FULL_COUNT):
                page.add(num)
            lower_page_boundary += 1

        # Fill the upper partial page (if any)
        if upper_page_index != 0:
            self._ensure_page_exists(upper_page_boundary)
            page = self.pages[upper_page_boundary]
            for num in range(0, upper_page_index + 1):
                page.add(num)
            upper_page_boundary -= 1

        # Fill whole pages inbetween (if any)
        if lower_page_boundary <= upper_page_boundary:
            for page_no in range(lower_page_boundary, upper_page_boundary + 1):
                self._ensure_page_exists(page_no)
                page = self.pages[page_no]
                page.set_full()

    @classmethod
    def from_intervals(type cls, interval_list):
        """Given a list of ranges in the form:  [[low1, high1], [low2, high2], ...]
        Construct a bitfield in which every integer in each range is present"""
        cdef SparseBitfield new = SparseBitfield()
        for (low, high) in interval_list:
            new.fill_range(low, high)
        return new

    def __str__(self):
        return "SparseBitfield(len=%i)" % (len(self))

    def __repr__(self):
        cls = type(self)
        return "%s.%s(%r)" % (cls.__module__, cls.__name__, self.pickle())

    def clear(self):
        self.pages = SortedDict({})


cpdef unpickle_sparsebitfield(bytes data):
    return SparseBitfield.unpickle(data)
