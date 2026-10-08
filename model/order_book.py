from dataclasses import dataclass


# Generates initialization and equality; frozen=True prevents field reassignment.
@dataclass(frozen=True)
class Order:
    order_id: int
    side: str
    price: int
    quantity: int


class OrderBook:
    def __init__(self):
        # __init__ runs when a book is created; self refers to that book.
        # Each active order ID maps to its Order; every book starts empty.
        self.orders: dict[int, Order] = {}

    def add(self, order_id: int, side: str, price: int, quantity: int) -> None:
        # Check each numeric field; type(...) also rejects floats and booleans.
        for name, value in (("order_id", order_id), ("price", price), ("quantity", quantity)):
            if type(value) is not int or value <= 0:
                raise ValueError(f"{name} must be a positive integer")

        if side not in ("BUY", "SELL"):
            raise ValueError("side must be BUY or SELL")

        # Membership checks dictionary keys, so an active ID cannot be reused.
        if order_id in self.orders:
            raise ValueError(f"Order ID {order_id} is already active")

        # Store only after every check passes, leaving rejected events unchanged.
        self.orders[order_id] = Order(order_id, side, price, quantity)

    def cancel(self, order_id: int, quantity: int) -> None:
        """Remove a cancelled quantity from an active order."""
        self._reduce(order_id, quantity)

    def execute(self, order_id: int, quantity: int) -> None:
        """Record a reported fill; this book does not decide matches."""
        self._reduce(order_id, quantity)

    def _reduce(self, order_id: int, quantity: int) -> None:
        for name, value in (("order_id", order_id), ("quantity", quantity)):
            if type(value) is not int or value <= 0:
                raise ValueError(f"{name} must be a positive integer")

        if order_id not in self.orders:
            raise ValueError(f"Order ID {order_id} is not active")

        order = self.orders[order_id]
        if quantity > order.quantity:
            raise ValueError("quantity exceeds the remaining order quantity")

        remaining = order.quantity - quantity
        if remaining == 0:
            del self.orders[order_id]
        else:
            # Order is frozen, so replace it with its updated quantity.
            self.orders[order_id] = Order(order.order_id, order.side, order.price, remaining)

    def price_totals(self, side: str) -> dict[int, int]:
        """Return total remaining quantity at each active price on one side."""
        if side not in ("BUY", "SELL"):
            raise ValueError("side must be BUY or SELL")

        totals: dict[int, int] = {}
        for order in self.orders.values():
            if order.side == side:
                totals[order.price] = totals.get(order.price, 0) + order.quantity
        return totals

    @property
    def best_bid(self) -> int | None:
        return max(self.price_totals("BUY"), default=None)

    @property
    def best_ask(self) -> int | None:
        return min(self.price_totals("SELL"), default=None)
