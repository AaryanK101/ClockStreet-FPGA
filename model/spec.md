# ClockStreet — Order Book Specification v0.1

## Scope
Track the visible orders for one instrument.
This module reconstructs market state; it does not match or submit trades.

## Order fields
- order_id: unique positive integer among active orders
- side: BUY or SELL
- price: positive integer in price ticks
- quantity: positive integer in units

Use integers throughout; no floating-point prices.

## Events

### ADD(order_id, side, price, quantity)
Create a new order.
Reject an invalid side, non-positive value, or duplicate active order ID.

### CANCEL(order_id, quantity)
Remove the specified quantity from an existing order.
Delete the order if its remaining quantity becomes zero.

### EXECUTE(order_id, quantity)
Record a reported fill by removing quantity from an existing order.
Delete the order if its remaining quantity becomes zero.
This event reports an execution; the book does not decide matches.

For CANCEL and EXECUTE:
- Reject unknown order IDs.
- Reject non-positive quantities.
- Reject quantities greater than the remaining order quantity.

## Error behaviour
Rejected events return an error and leave the entire book unchanged.

## Book outputs
- Total remaining quantity at each price, separately for BUY and SELL.
- Best bid: highest active BUY price.
- Best ask: lowest active SELL price.
- An empty side has no best price, represented by None in Python.

## Assumptions
Events arrive in order and are processed one at a time.
Prices and sides cannot change on an existing order.
An order ID may be reused after its previous order has been removed.
Crossed books are allowed; this module does not perform matching.
Hardware widths and capacity limits will be defined later.

## Worked example
Prices below are ticks, not currency amounts.

1. ADD(1, BUY, 100, 10)
   Best bid: 100, quantity 10. No ask.

2. ADD(2, BUY, 100, 5)
   Best bid: 100, aggregated quantity 15.

3. ADD(3, SELL, 103, 8)
   Best ask: 103, quantity 8.

4. EXECUTE(1, 4)
   Order 1 has 6 remaining. Bid quantity at 100 is 11.

5. CANCEL(2, 5)
   Order 2 is removed. Bid quantity at 100 is 6.

6. CANCEL(1, 7)
   Rejected: only 6 remain. Book unchanged.