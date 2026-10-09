`timescale 1ns/1ps

module order_book_basic_tb;

    // Your testbench goes here.
    logic        clk;
    logic        rst;
    logic        event_valid;
    logic        event_ready;
    logic [1:0]  event_type;
    logic [15:0] order_id;
    logic        side;
    logic [31:0] price;
    logic [31:0] quantity;
    logic        result_valid;
    logic [2:0]  error_code;
    logic        best_bid_valid;
    logic [31:0] best_bid_price;
    logic [35:0] best_bid_quantity;
    logic        best_ask_valid;
    logic [31:0] best_ask_price;
    logic [35:0] best_ask_quantity;

    // generating the clock (10ns period)
    always #5 clk = ~clk;

    order_book order_book_dut (
        .clk(clk),
        .rst(rst),
        .event_valid(event_valid),
        .event_ready(event_ready),
        .event_type(event_type),
        .order_id(order_id),
        .side(side),
        .price(price),
        .quantity(quantity),
        .result_valid(result_valid),
        .error_code(error_code),
        .best_bid_valid(best_bid_valid),
        .best_bid_price(best_bid_price),
        .best_bid_quantity(best_bid_quantity),
        .best_ask_valid(best_ask_valid),
        .best_ask_price(best_ask_price),
        .best_ask_quantity(best_ask_quantity)
    );

    initial begin
        clk = 0; rst = 1;

        event_valid = 0;
        event_type = 0;
        order_id = 0;
        side = 0;
        price = 0;
        quantity = 0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;
        #1;


        // checks
        // no BUY after reset
        if (best_bid_valid !== 1'b0)
            $fatal(1, "Expected no bid after reset");

        // No sell after reset
        if (best_ask_valid !== 1'b0)
            $fatal(1, "Expected no ask after reset");

        // best bid price
        if (best_bid_price !== 32'b0)
            $fatal(1, "Expected no bid price after reset");
        
        // best ask price
        if (best_ask_price !== 32'b0)
            $fatal(1, "Expected no ask price after reset");

        // bid quantity
        if (best_bid_quantity !== 32'b0)
            $fatal(1, "Expected no bid quantity after reset");

        // ask quantity
        if (best_ask_quantity !== 32'b0)
            $fatal(1, "Expected no ask quantity after reset");

        // the result is valid
        if (result_valid !== 1'b0)
            $fatal(1, "Expected no valid result after reset");
        
        // error code check
        if (error_code !== 1'b0)
            $fatal(1, "Expected no error code after reset");
        
        // event ready check
        if (event_ready !== 1'b1)
            $fatal(1, "Expected ready to be accepted after reset");

        $display("Reset test passed");
        $finish;
    end




endmodule