`timescale 1ns/1ps
module order_book_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1, event_valid = 0, event_ready;
    logic [1:0] event_type = 0;
    logic [15:0] order_id = 0;
    logic side = 0;
    logic [31:0] price = 0, quantity = 0;
    logic result_valid;
    logic [2:0] error_code;
    logic best_bid_valid, best_ask_valid;
    logic [31:0] best_bid_price, best_ask_price;
    logic [35:0] best_bid_quantity, best_ask_quantity;
    order_book dut (.*);

    // Independent behavioural scoreboard, updated only for successful events.
    bit active [0:15];
    logic [15:0] ref_id [0:15];
    bit ref_side [0:15];
    logic [31:0] ref_price [0:15], ref_quantity [0:15];
    integer tests = 0;
    integer j;

    task automatic check_outputs;
        bit bid_valid, ask_valid;
        logic [31:0] bid, ask;
        logic [35:0] bid_qty, ask_qty;
        begin
            bid_valid = 0; ask_valid = 0;
            bid = 0; ask = 0; bid_qty = 0; ask_qty = 0;
            for (int k = 0; k < 16; k++) begin
                if (active[k]) begin
                    if (!ref_side[k]) begin
                        if (!bid_valid || ref_price[k] > bid) begin
                            bid_valid = 1; bid = ref_price[k];
                        end
                    end else if (!ask_valid || ref_price[k] < ask) begin
                        ask_valid = 1; ask = ref_price[k];
                    end
                end
            end
            for (int k = 0; k < 16; k++) begin
                if (active[k] && !ref_side[k] && ref_price[k] == bid)
                    bid_qty = bid_qty + {4'b0, ref_quantity[k]};
                if (active[k] && ref_side[k] && ref_price[k] == ask)
                    ask_qty = ask_qty + {4'b0, ref_quantity[k]};
            end
            if ({best_bid_valid, best_bid_price, best_bid_quantity,
                 best_ask_valid, best_ask_price, best_ask_quantity} !==
                {bid_valid, bid, bid_qty, ask_valid, ask, ask_qty})
                $fatal(1, "Book outputs differ from scoreboard after event %0d", tests);
        end
    endtask

    task automatic send_event(input logic [1:0] kind, input logic [15:0] id,
                              input logic sell, input logic [31:0] p,
                              input logic [31:0] qty, input logic [2:0] expected);
        integer slot, cycles;
        logic [137:0] previous_outputs;
        begin
            @(negedge clk);
            while (!event_ready) @(negedge clk);
            previous_outputs = {best_bid_valid, best_bid_price, best_bid_quantity,
                                best_ask_valid, best_ask_price, best_ask_quantity};
            event_valid = 1; event_type = kind; order_id = id;
            side = sell; price = p; quantity = qty;
            @(posedge clk); #1;
            if (event_ready) $fatal(1, "Ready remained high after acceptance");
            @(negedge clk);
            // Change inputs to verify that the accepted event was captured.
            event_valid = 0; event_type = 3; order_id = 0; price = 0; quantity = 0;
            cycles = 0;
            while (!result_valid) begin
                @(posedge clk); #1;
                cycles++;
                if (cycles > 50) $fatal(1, "Completion timeout");
                if (event_ready) $fatal(1, "Ready asserted while busy");
                if (!result_valid && previous_outputs !==
                    {best_bid_valid, best_bid_price, best_bid_quantity,
                     best_ask_valid, best_ask_price, best_ask_quantity})
                    $fatal(1, "Outputs changed before completion");
            end
            if (error_code !== expected)
                $fatal(1, "Expected error %0d, received %0d", expected, error_code);
            if (expected == 0) begin
                slot = -1;
                for (int k = 0; k < 16; k++)
                    if (active[k] && ref_id[k] == id) slot = k;
                if (kind == 0) begin
                    for (int k = 15; k >= 0; k--)
                        if (!active[k]) slot = k;
                    if (slot == -1) $fatal(1, "Scoreboard has no free slot");
                    active[slot] = 1; ref_id[slot] = id; ref_side[slot] = sell;
                    ref_price[slot] = p; ref_quantity[slot] = qty;
                end else begin
                    if (slot == -1) $fatal(1, "Scoreboard cannot find order");
                    ref_quantity[slot] = ref_quantity[slot] - qty;
                    if (ref_quantity[slot] == 0) active[slot] = 0;
                end
            end
            tests++;
            check_outputs();
            @(posedge clk); #1;
            if (result_valid || !event_ready) $fatal(1, "Invalid completion pulse");
        end
    endtask

    task automatic reset_book;
        begin
            @(negedge clk); rst = 1; event_valid = 0;
            @(posedge clk); #1;
            for (int k = 0; k < 16; k++) active[k] = 0;
            check_outputs();
            if (result_valid || event_ready || error_code != 0)
                $fatal(1, "Invalid reset outputs");
            @(negedge clk); rst = 0;
        end
    endtask

    initial begin
        reset_book();
        // Specification example and error atomicity.
        send_event(0, 1, 0, 100, 10, 0);
        send_event(0, 2, 0, 100, 5, 0);
        send_event(0, 3, 1, 103, 8, 0);
        send_event(2, 1, 1, 0, 4, 0);
        send_event(1, 2, 1, 0, 5, 0);
        send_event(1, 1, 0, 0, 7, 5);
        send_event(2, 1, 0, 0, 7, 5);
        send_event(3, 0, 0, 0, 0, 1);
        send_event(0, 0, 0, 100, 1, 2);
        send_event(0, 4, 0, 0, 1, 2);
        send_event(0, 4, 0, 100, 0, 2);
        send_event(1, 0, 0, 0, 1, 2);
        send_event(2, 1, 0, 0, 0, 2);
        send_event(0, 1, 1, 99, 1, 3);
        send_event(1, 99, 0, 0, 1, 4);
        send_event(2, 99, 0, 0, 1, 4);
        // Removal, reused ID, crossed prices, and best-price replacement.
        send_event(2, 1, 0, 0, 6, 0);
        send_event(0, 1, 0, 105, 2, 0);
        send_event(0, 4, 1, 99, 3, 0);
        send_event(1, 4, 0, 0, 3, 0);
        send_event(1, 3, 0, 0, 8, 0);
        send_event(1, 1, 0, 0, 2, 0);
        reset_book();
        // Full capacity, last-slot lookup, and a total larger than 32 bits.
        for (j = 1; j <= 16; j++)
            send_event(0, j[15:0], 0, 32'hffffffff, 32'hffffffff, 0);
        send_event(0, 17, 0, 100, 1, 6);
        send_event(0, 16, 0, 100, 1, 3);
        send_event(2, 16, 0, 0, 32'hffffffff, 0);
        send_event(0, 16'hffff, 1, 1, 32'hffffffff, 0);
        reset_book();
        // Reset must abandon an accepted event without a completion.
        @(negedge clk);
        event_valid = 1; event_type = 0; order_id = 1; side = 0; price = 100; quantity = 10;
        @(posedge clk); #1;
        reset_book();
        repeat (40) begin
            @(posedge clk); #1;
            if (result_valid) $fatal(1, "Abandoned event completed after reset");
            check_outputs();
        end
        $display("PASS: %0d events checked", tests);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Global simulation timeout");
    end
endmodule
