import unittest

from model.order_book import OrderBook


class OrderBookTests(unittest.TestCase):
    def test_spec_worked_example(self):
        book = OrderBook()
        self.assertIsNone(book.best_bid)
        self.assertIsNone(book.best_ask)
        book.add(1, "BUY", 100, 10)
        book.add(2, "BUY", 100, 5)
        self.assertEqual(book.price_totals("BUY"), {100: 15})
        book.add(3, "SELL", 103, 8)
        self.assertEqual((book.best_bid, book.best_ask), (100, 103))
        book.execute(1, 4)
        self.assertEqual(book.orders[1].quantity, 6)
        self.assertEqual(book.price_totals("BUY"), {100: 11})
        book.cancel(2, 5)
        self.assertNotIn(2, book.orders)
        self.assertEqual(book.price_totals("BUY"), {100: 6})
        before = book.orders.copy()
        with self.assertRaises(ValueError):
            book.cancel(1, 7)
        self.assertEqual(book.orders, before)

    def test_removal_best_prices_crossed_book_and_id_reuse(self):
        book = OrderBook()
        book.add(1, "BUY", 105, 2)
        book.add(2, "BUY", 100, 3)
        book.add(3, "SELL", 99, 4)
        book.add(4, "SELL", 110, 5)
        self.assertEqual((book.best_bid, book.best_ask), (105, 99))
        book.cancel(1, 2)
        book.execute(3, 4)
        self.assertEqual((book.best_bid, book.best_ask), (100, 110))
        book.add(1, "SELL", 108, 6)
        self.assertEqual(book.best_ask, 108)
        book.execute(2, 3)
        self.assertIsNone(book.best_bid)
        totals = book.price_totals("SELL")
        totals.clear()
        self.assertEqual(book.price_totals("SELL"), {110: 5, 108: 6})

    def test_rejected_events_leave_book_unchanged(self):
        book = OrderBook()
        book.add(1, "BUY", 100, 10)
        invalid_adds = [(1, "BUY", 101, 1), (2, "OTHER", 100, 1)]
        for index in (0, 2, 3):
            for value in (0, -1, 1.5, True, "1", None):
                args = [2, "SELL", 103, 8]
                args[index] = value
                invalid_adds.append(tuple(args))
        for args in invalid_adds:
            with self.subTest(event="ADD", args=args):
                before = book.orders.copy()
                with self.assertRaises(ValueError):
                    book.add(*args)
                self.assertEqual(book.orders, before)

        for event in (book.cancel, book.execute):
            for order_id, quantity in ((99, 1), (1, 11), (1, 0), (1, -1),
                                       (1, True), (1, 1.5), (True, 1),
                                       (1.0, 1), (None, 1), (1, "1")):
                with self.subTest(event=event.__name__, args=(order_id, quantity)):
                    before = book.orders.copy()
                    with self.assertRaises(ValueError):
                        event(order_id, quantity)
                    self.assertEqual(book.orders, before)

    def test_invalid_output_side(self):
        with self.assertRaises(ValueError):
            OrderBook().price_totals("OTHER")


if __name__ == "__main__":
    unittest.main()
