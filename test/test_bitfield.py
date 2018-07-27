#!/usr/bin/python

# For coverage script
import sparsebitfield

import pickle as cPickle
import pickle
import random
import unittest


class BitfieldTest(unittest.TestCase):

    def test_repr_eval(self):
        b = sparsebitfield.SparseBitfield()
        b.add(100)
        c = eval(repr(b))
        self.assertEqual(b, c)
        for i in range(0, 1000, 13):
            b.add(i)
        c = eval(repr(b))
        self.assertEqual(b, c)

    def test_count(self):
        b = sparsebitfield.SparseBitfield()
        self.assertEqual(b.count, 0)
        b.add(0)
        self.assertEqual(b.count, 1)
        b.add(10000)
        self.assertEqual(b.count, 2)
        self.assertEqual(len(b), 2)

    def test_mutating_while_iterating(self):
        b = sparsebitfield.SparseBitfield([[0, 1000]])
        count = len(b)
        for num in b:
            self.assertIn(num, b)
            b.remove(num)
            count -= 1
            self.assertEqual(len(b), count)
            self.assertNotIn(num, b)
        self.assertEqual(count, 0)

    def test_membership(self):
        b = sparsebitfield.SparseBitfield()
        b.add(0)
        b.add(1)
        b.add(2)
        self.assertTrue(1 in b)
        self.assertFalse(3 in b)
        self.assertEqual(list(b), [0, 1, 2])

    def test_add_remove(self):
        b = sparsebitfield.SparseBitfield()
        self.assertEqual(list(b), [])
        for i in range(0, 1000000, 881):
            b.add(i)
            self.assertEqual(list(b), [i])
            b.remove(i)

    def test_merging(self):
        a = sparsebitfield.SparseBitfield()
        b = sparsebitfield.SparseBitfield()
        a.add(0)
        b.add(0)
        a.update(b)
        self.assertEqual(list(a), [0])
        a.add(1000)
        b.add(1000000)
        b.update(a)
        self.assertEqual(list(b), [0, 1000, 1000000])

    def test_in(self):
        a = sparsebitfield.SparseBitfield()
        for i in range(0, 100, 13):
            a.add(i)
        self.assertIn(13, a)
        self.assertIn(0, a)
        self.assertIn(26, a)
        self.assertNotIn(27, a)
        self.assertIn(39, a)
        self.assertNotIn(1000000, a)
        a.add(1000000)
        self.assertIn(1000000, a)

    def test_clone(self):
        a = sparsebitfield.SparseBitfield()
        a.add(1)
        a.add(10)
        a.add(5000000)
        b = a.clone()
        self.assertEqual(a, b)
        b.add(45)
        self.assertNotEqual(a, b)

    def test_symmetric_difference(self):
        field = sparsebitfield.SparseBitfield
        a = field()
        b = field()
        a.add(1)
        self.assertEqual(a.symmetric_difference(b), field([1]))
        self.assertEqual(a ^ b, a)
        b.add(2)
        self.assertEqual(list(a ^ b), list(field([1, 2])))

        full = field([[1, 100000]])
        full_set = set(range(1, 100000))
        self.assertEqual(set(full), full_set)
        self.assertEqual(set(full ^ a), full_set - set([1]))

        odds = field(range(1, 90000, 2))
        evens = field(range(0, 90000, 2))
        full = odds ^ evens
        self.assertSequenceEqual(list(full), range(90000))
        self.assertEqual(len(full), len(odds) + len(evens))
        self.assertEqual(len((odds ^ odds) | (evens ^ evens)), 0)

    def test_creating_large_field(self):
        # This is a strange test, the idea is to create a large set, then do something with it
        # provided the test completes in a 'reasonable' timescale, then it should be fine
        one_million = 1000000
        size = one_million * 1000

        field1 = sparsebitfield.SparseBitfield([[0, size]])
        field2 = sparsebitfield.SparseBitfield([[size, size * 2]])
        self.assertEqual(len(field1), size)
        self.assertEqual(len(field2), size)
        self.assertEqual(len(field1 | field2), size * 2)

    def test_init_with_small_ranges(self):
        a = sparsebitfield.SparseBitfield((
            (0, 1),
            (3, 10),
        ),)
        self.assertSequenceEqual(list(a), [0, 3, 4, 5, 6, 7, 8, 9])

    def test_init_with_large_ranges(self):
        a = sparsebitfield.SparseBitfield(((0, 20000), (30000, 100000)))
        self.assertEqual(len(a), 90000)
        self.assertEqual(max(a), 99999)
        self.assertEqual(min(a), 0)

    def test_large_numbers(self):
        size = 78
        field1 = sparsebitfield.SparseBitfield()
        field2 = sparsebitfield.SparseBitfield()
        for p in range(1, size + 1):
            field1.add(2**p)
            self.assertIn(2**p, field1)
            field2.add(2**p - 1)
            self.assertIn(2**p - 1, field2)
        self.assertEqual(len(field1), size)
        self.assertEqual(len(field2), size)
        self.assertEqual(len(field1 | field2), size * 2)
        field1 = sparsebitfield.SparseBitfield([[2**70, 2**70 + 3000000]])
        for num in range(2**70, 2**70 + 3000000):
            self.assertIn(num, field1)
        self.assertEqual(len(field1), 3000000)


class SetEqualityTest(unittest.TestCase):

    def _test_field_result(self, a, b, func):
        set_a = set(a)
        set_b = set(b)
        bitfield_result = func(a, b)
        set_result = func(set_a, set_b)
        set_as_list = sorted(set_result)
        self.assertEqual(list(bitfield_result), set_as_list)

    def _test_simple_result(self, a, b, func):
        set_a = set(a)
        set_b = set(b)
        bitfield_result = func(a, b)
        set_result = func(set_a, set_b)
        self.assertEqual(bitfield_result, set_result)

    def _test_methods(self, a, b):
        a_pure = a.copy()
        b_pure = b.copy()
        self._test_field_result(a, b, lambda x, y: x | y)
        self._test_field_result(a, b, lambda x, y: x ^ y)
        self._test_field_result(a, b, lambda x, y: x & y)
        self._test_field_result(a, b, lambda x, y: x - y)
        self._test_field_result(a, b, lambda x, y: x.union(y))
        self._test_simple_result(a, b, lambda x, y: x.isdisjoint(y))
        self._test_simple_result(a, b, lambda x, y: x.issubset(y))
        self._test_simple_result(a, b, lambda x, y: x < y)
        self._test_simple_result(a, b, lambda x, y: x <= y)
        self._test_simple_result(a, b, lambda x, y: x == y)
        self._test_simple_result(a, b, lambda x, y: x != y)
        self._test_simple_result(a, b, lambda x, y: x >= y)
        self._test_simple_result(a, b, lambda x, y: x > y)

        a_2, b_2 = pickle.loads(cPickle.dumps([a, b]))
        self.assertEqual(a_2, a)
        self.assertEqual(b_2, b)
        self.assertEqual(a_pure, a)
        self.assertEqual(b_pure, b)

    def test_empty(self):
        self._test_methods(sparsebitfield.SparseBitfield(), sparsebitfield.SparseBitfield())

    def test_simple(self):
        self._test_methods(sparsebitfield.SparseBitfield([1, 2, 3]), sparsebitfield.SparseBitfield([1, 2, 3]))
        self._test_methods(sparsebitfield.SparseBitfield([1, 2, 3]), sparsebitfield.SparseBitfield([1, 2]))
        self._test_methods(sparsebitfield.SparseBitfield([1, 2, 3]), sparsebitfield.SparseBitfield([3, 4, 5]))
        self._test_methods(sparsebitfield.SparseBitfield([1]), sparsebitfield.SparseBitfield([1, 3, 4, 5]))

    def test_multi_page(self):

        def nums(*numbers):
            return list([page_numbers[n] for n in numbers])

        page_max = sparsebitfield.get_all_sizes()["PAGE_MAX"]
        page_numbers = [5 + (page_max * i) for i in range(10)]
        a = sparsebitfield.SparseBitfield(nums(0, 2))
        b = sparsebitfield.SparseBitfield(nums(1, 3))
        self._test_methods(a, b)
        self._test_methods(b, a)

    def test_empty_full(self):
        page_max = sparsebitfield.get_all_sizes()["PAGE_MAX"]
        a = sparsebitfield.SparseBitfield([[0, page_max]])
        b = sparsebitfield.SparseBitfield()
        self._test_methods(a, b)
        self._test_methods(b, a)


if __name__ == "__main__":
    unittest.main()
