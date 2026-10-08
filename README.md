# ClockStreet-FPGA
FPGA-based market-data and trading engine

The Python reference model in `model/order_book.py` implements the single-instrument
order book described in [docs/order_book_spec.md](docs/order_book_spec.md). It tracks reported orders and executions;
it does not match or submit trades.

Use `add()`, `cancel()`, and `execute()` to apply events. Invalid events raise
`ValueError` and leave the book unchanged. `price_totals("BUY")` and
`price_totals("SELL")` return quantities by price; `best_bid` and `best_ask` are
properties that return a price or `None` for an empty side.

Run the reference-model tests from the repository root:

```powershell
python -m unittest discover -s tb -v
```

The initial hardware design is documented in [docs/hardware_spec.md](docs/hardware_spec.md):
16 order slots, fixed field widths, event handshakes, completion codes, and best
bid/ask outputs. The first RTL implementation is in `rtl/order_book.sv`, with a
self-checking testbench in `tb/order_book_tb.sv`.

With Icarus Verilog installed, run the hardware simulation from the repository root:

```powershell
iverilog -g2012 -s order_book_tb -o "$env:TEMP/clockstreet_order_book.vvp" rtl/order_book.sv tb/order_book_tb.sv
vvp "$env:TEMP/clockstreet_order_book.vvp"
```
