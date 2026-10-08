# Order book hardware specification v0.1

This first RTL design tracks one instrument using the event rules in
[order_book_spec.md](order_book_spec.md). It processes one event at a time and does not match trades.
These are initial design choices. The first implementation is
`rtl/order_book.sv`, with a self-checking simulation in `tb/order_book_tb.sv`.
Clock frequency and resource usage require synthesis for a target device.

## Storage

There are 16 order slots. Each slot contains:

| Field | Bits | Meaning |
| --- | ---: | --- |
| occupied | 1 | 1 means the slot contains an active order |
| order_id | 16 | Positive unsigned order ID |
| side | 1 | 0 = BUY, 1 = SELL |
| price | 32 | Positive unsigned integer price ticks |
| quantity | 32 | Positive unsigned remaining quantity |

The records require 1,312 bits before control logic and output registers.
Zero is invalid for order ID, price, and event quantity. Order IDs may be reused
after removal. A full book rejects ADD; CANCEL and EXECUTE can still proceed.
The Python model remains an unbounded behavioural reference. Hardware inputs
must fit these widths, and tests must account for the hardware capacity limit.

## Clock and reset

All signals use one clock, `clk`. State changes on its rising edge.
`rst` is active-high and synchronous. Reset clears every occupied flag, output
valid flag, and output value. No event is accepted while reset is asserted.
Reset abandons any event being processed without producing a completion.

## Event inputs

| Signal | Bits | Meaning |
| --- | ---: | --- |
| event_valid | 1 | Sender has an event available |
| event_ready | 1 | Output: book can accept an event |
| event_type | 2 | 00 = ADD, 01 = CANCEL, 10 = EXECUTE, 11 = invalid |
| order_id | 16 | Order to create or update |
| side | 1 | Used only for ADD |
| price | 32 | Used only for ADD |
| quantity | 32 | Quantity to add or remove |

An event is accepted on a rising edge when event_valid and event_ready are both
1 and rst is 0. The sender holds event_valid and all event fields unchanged
until acceptance. The book captures the fields and deasserts event_ready while
processing. Side and price are ignored for CANCEL and EXECUTE.

## Completion and errors

| Signal | Bits | Meaning |
| --- | ---: | --- |
| result_valid | 1 | One-cycle pulse when processing completes |
| error_code | 3 | Result code, meaningful during result_valid |

Every accepted event produces exactly one completion unless interrupted by
reset. Completion follows acceptance on a later clock edge. There is no result
backpressure: the consumer must sample the completion pulse. A new event is
accepted only after the previous completion cycle.

| Code | Meaning |
| --- | --- |
| 000 | Success |
| 001 | Invalid event type |
| 010 | Zero in a required field |
| 011 | Duplicate active order ID |
| 100 | Unknown order ID |
| 101 | Removal quantity exceeds remaining quantity |
| 110 | Book full |
| 111 | Reserved |

If several errors apply, check in this order: event type, required fields,
order ID lookup, then quantity or capacity. For ADD, duplicate ID takes
precedence over book full. Rejecting an event leaves all order slots and book
outputs unchanged. Only successful events modify storage.

## Book outputs

| Signal | Bits | Meaning |
| --- | ---: | --- |
| best_bid_valid | 1 | At least one BUY order exists |
| best_bid_price | 32 | Highest active BUY price |
| best_bid_quantity | 36 | Total BUY quantity at that price |
| best_ask_valid | 1 | At least one SELL order exists |
| best_ask_price | 32 | Lowest active SELL price |
| best_ask_quantity | 36 | Total SELL quantity at that price |

The totals use 36 bits because up to 16 orders can each hold a 32-bit quantity.
When a side is empty, its valid flag, price, and quantity are all zero.
Crossed books are permitted.

Outputs represent the last completed event and remain stable while the next
event is processed. Updated outputs are available during result_valid for a
successful event. A rejected event preserves the previous outputs.

The first RTL interface exposes totals at the best prices. Arbitrary price-level
queries remain available in the Python model; a hardware query interface is
deferred beyond this first implementation.

## Implementation plan

1. Capture an accepted event.
2. Scan the 16 slots for its order ID and an empty slot.
3. Validate the event and apply its change, or report an error.
4. Recompute best bid and ask and their aggregated quantities after a change.
5. Publish the outputs and completion, then return to accepting events.

Use a sequential slot scan initially to keep control logic understandable.
The current RTL completes a rejected event 17 clock cycles after acceptance
and a successful event 34 clock cycles after acceptance. It keeps ready low
through the completion pulse, then returns to idle on the following edge.
Simulation should cover the model's worked example, invalid events without
mutation, full capacity, slot and ID reuse, empty sides, crossed books, reset,
input handshakes, and aggregation near the maximum quantities.
