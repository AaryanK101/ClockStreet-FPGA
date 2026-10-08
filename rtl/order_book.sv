// One instrument, up to 16 active orders, one event processed at a time.
// Successful event: IDLE -> LOOKUP -> APPLY -> REBUILD -> PUBLISH -> COMPLETE.
// Rejected event:   IDLE -> LOOKUP -> APPLY -> COMPLETE (no book changes).
// CANCEL and EXECUTE both remove quantity; EXECUTE records a reported fill.
// This module does not choose trades or match BUY orders against SELL orders.
module order_book (
    input  logic        clk,
    input  logic        rst,
    input  logic        event_valid,
    output logic        event_ready,
    input  logic [1:0]  event_type,
    input  logic [15:0] order_id,
    input  logic        side,
    input  logic [31:0] price,
    input  logic [31:0] quantity,
    output logic        result_valid,
    output logic [2:0]  error_code,
    output logic        best_bid_valid,
    output logic [31:0] best_bid_price,
    output logic [35:0] best_bid_quantity,
    output logic        best_ask_valid,
    output logic [31:0] best_ask_price,
    output logic [35:0] best_ask_quantity
);
    localparam logic [1:0] ADD = 2'b00;
    localparam logic [1:0] CANCEL = 2'b01;
    localparam logic [1:0] EXECUTE = 2'b10;
    localparam logic [2:0] OK = 3'd0, INVALID_TYPE = 3'd1,
        ZERO_FIELD = 3'd2, DUPLICATE_ID = 3'd3, UNKNOWN_ID = 3'd4,
        EXCESS_QUANTITY = 3'd5, BOOK_FULL = 3'd6;

    // Each state selects the work performed on the next rising clock edge.
    // LOOKUP and REBUILD each visit one slot per edge, taking 16 edges.
    typedef enum logic [2:0] {IDLE, LOOKUP, APPLY, REBUILD, PUBLISH, COMPLETE} state_t;
    state_t state;

    // These parallel arrays together form 16 order records. For example,
    // ids[3], sides[3], prices[3], quantities[3] describe the same order.
    // occupied[3] decides whether that record counts as part of the book.
    // The slot index is a storage location, not the external order ID.
    logic occupied [0:15];
    logic [15:0] ids [0:15];
    logic sides [0:15];
    logic [31:0] prices [0:15];
    logic [31:0] quantities [0:15];

    // Capture the event so the sender can change its inputs after acceptance.
    logic [1:0] captured_type;
    logic [15:0] captured_id;
    logic captured_side;
    logic [31:0] captured_price, captured_quantity;
    // scan_index is the slot being examined. match_index remembers the order
    // we found; free_index remembers an empty slot where ADD could store data.
    // The found flags determine whether those remembered indices are usable.
    logic [3:0] scan_index, match_index, free_index;
    logic match_found, free_found;
    logic [2:0] validation_error;

    // Temporary results keep published outputs stable during processing.
    // Each quantity sums only orders at the best price found so far.
    // 36 bits can hold the sum of all 16 unsigned 32-bit quantities.
    logic bid_found, ask_found;
    logic [31:0] bid_price, ask_price;
    logic [35:0] bid_quantity, ask_quantity;
    integer i;

    // Accept only while idle: there is no queue for a second event.
    assign event_ready = (state == IDLE) && !rst;

    // Validation only calculates a decision; it never changes order storage.
    // APPLY uses this decision after LOOKUP has examined all 16 slots.
    // The if/else order gives deterministic priority when several errors apply.
    always_comb begin
        validation_error = OK;
        if (captured_type != ADD && captured_type != CANCEL && captured_type != EXECUTE)
            validation_error = INVALID_TYPE;
        else if (captured_id == 0 || captured_quantity == 0 ||
                 (captured_type == ADD && captured_price == 0))
            validation_error = ZERO_FIELD;
        else if (captured_type == ADD) begin
            // An existing ID is rejected even if another slot is empty.
            // If the ID is new, ADD still needs a free slot.
            if (match_found)
                validation_error = DUPLICATE_ID;
            else if (!free_found)
                validation_error = BOOK_FULL;
        end else begin
            // CANCEL/EXECUTE need an existing order and cannot remove more
            // than it contains. Their side and price inputs are ignored.
            if (!match_found)
                validation_error = UNKNOWN_ID;
            else if (captured_quantity > quantities[match_index])
                validation_error = EXCESS_QUANTITY;
        end
    end

    // Nonblocking assignments (<=) update registers together after this edge.
    // Conditions here read their old values. That is why the final scan result
    // is consumed in the following state, rather than on the same scan edge.
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset takes priority over every state, abandoning any pending
            // event and clearing the book without producing a completion.
            state <= IDLE;
            result_valid <= 0;
            error_code <= OK;
            best_bid_valid <= 0;
            best_bid_price <= 0;
            best_bid_quantity <= 0;
            best_ask_valid <= 0;
            best_ask_price <= 0;
            best_ask_quantity <= 0;
            captured_type <= ADD;
            captured_id <= 0;
            captured_side <= 0;
            captured_price <= 0;
            captured_quantity <= 0;
            scan_index <= 0;
            match_index <= 0;
            free_index <= 0;
            match_found <= 0;
            free_found <= 0;
            bid_found <= 0;
            ask_found <= 0;
            bid_price <= 0;
            ask_price <= 0;
            bid_quantity <= 0;
            ask_quantity <= 0;
            // Unlike the sequential scans below, this reset loop clears all
            // slots on this one edge; it does not take 16 clock cycles.
            for (i = 0; i < 16; i = i + 1) begin
                occupied[i] <= 0;
                ids[i] <= 0;
                sides[i] <= 0;
                prices[i] <= 0;
                quantities[i] <= 0;
            end
        end else begin
            // Default to no completion. APPLY (error) or PUBLISH (success)
            // overrides this for one cycle; the next edge clears the pulse.
            result_valid <= 0;
            case (state)
                IDLE: begin
                    // Ready is high in IDLE, so valid means an event is accepted.
                    // Copy its fields and start a fresh search from slot zero.
                    if (event_valid) begin
                        captured_type <= event_type;
                        captured_id <= order_id;
                        captured_side <= side;
                        captured_price <= price;
                        captured_quantity <= quantity;
                        scan_index <= 0;
                        match_found <= 0;
                        free_found <= 0;
                        state <= LOOKUP;
                    end
                end
                LOOKUP: begin
                    // Search for two things in parallel: the requested active
                    // ID and the first empty slot. Scan the entire book even
                    // after finding an empty slot, since a duplicate ID may
                    // exist later. Only occupied slots can match an order ID.
                    if (occupied[scan_index] && ids[scan_index] == captured_id) begin
                        match_found <= 1;
                        match_index <= scan_index;
                    end
                    // Once an empty slot is remembered, do not replace it.
                    if (!occupied[scan_index] && !free_found) begin
                        free_found <= 1;
                        free_index <= scan_index;
                    end
                    // APPLY runs on the next edge, so it sees matches or free
                    // slots discovered at index 15 as well as earlier ones.
                    if (scan_index == 15)
                        state <= APPLY;
                    else
                        scan_index <= scan_index + 1'b1;
                end
                APPLY: begin
                    // All validation finishes before any storage is modified.
                    error_code <= validation_error;
                    if (validation_error != OK) begin
                        // Report the error immediately. Skip REBUILD/PUBLISH
                        // so both order records and published prices stay intact.
                        result_valid <= 1;
                        state <= COMPLETE;
                    end else begin
                        if (captured_type == ADD) begin
                            // Write one complete record into the remembered
                            // empty slot and mark it active.
                            occupied[free_index] <= 1;
                            ids[free_index] <= captured_id;
                            sides[free_index] <= captured_side;
                            prices[free_index] <= captured_price;
                            quantities[free_index] <= captured_quantity;
                        end else if (captured_quantity == quantities[match_index]) begin
                            // Removing the entire quantity frees the slot.
                            // Its old ID/side/price are harmless because all
                            // searches ignore slots with occupied == 0.
                            occupied[match_index] <= 0;
                            quantities[match_index] <= 0;
                        end else begin
                            // Partial CANCEL/EXECUTE preserves ID, side, price.
                            // Example: 10 units minus 3 leaves 7 in this slot.
                            quantities[match_index] <= quantities[match_index] - captured_quantity;
                        end
                        // Recalculate from scratch: deleting the best order
                        // could make a previously worse price become best.
                        // Zero initial values also handle an empty side.
                        scan_index <= 0;
                        bid_found <= 0;
                        ask_found <= 0;
                        bid_price <= 0;
                        ask_price <= 0;
                        bid_quantity <= 0;
                        ask_quantity <= 0;
                        state <= REBUILD;
                    end
                end
                REBUILD: begin
                    // The APPLY updates are now visible. Examine one active
                    // slot per cycle, keeping the best price seen so far.
                    if (occupied[scan_index]) begin
                        if (!sides[scan_index]) begin
                            // BUY: a higher price is better. The first BUY or
                            // a new higher price replaces the running result,
                            // including its quantity: lower-price totals no
                            // longer belong to the best bid.
                            if (!bid_found || prices[scan_index] > bid_price) begin
                                bid_found <= 1;
                                bid_price <= prices[scan_index];
                                bid_quantity <= {4'b0, quantities[scan_index]};
                            end else if (prices[scan_index] == bid_price)
                                // Same best price: combine the quantities.
                                // Zero extension preserves all 32 quantity bits.
                                bid_quantity <= bid_quantity + {4'b0, quantities[scan_index]};
                            // A lower BUY price contributes nothing to this total.
                        end else begin
                            // SELL: a lower price is better. Replace the running
                            // total on a lower price; add on an equal price.
                            // Example: SELL 103 x 8 and SELL 103 x 2 give 10;
                            // finding SELL 101 x 4 changes the best ask to 101 x 4.
                            if (!ask_found || prices[scan_index] < ask_price) begin
                                ask_found <= 1;
                                ask_price <= prices[scan_index];
                                ask_quantity <= {4'b0, quantities[scan_index]};
                            end else if (prices[scan_index] == ask_price)
                                ask_quantity <= ask_quantity + {4'b0, quantities[scan_index]};
                        end
                    end
                    // PUBLISH runs one edge later so the last slot's updates
                    // are included in the outputs.
                    if (scan_index == 15)
                        state <= PUBLISH;
                    else
                        scan_index <= scan_index + 1'b1;
                end
                PUBLISH: begin
                    // Commit both sides together and announce success. Until
                    // this edge, consumers saw the previous completed book.
                    // If no order existed on a side, its temporary values are
                    // still zero and its found flag is false.
                    best_bid_valid <= bid_found;
                    best_bid_price <= bid_price;
                    best_bid_quantity <= bid_quantity;
                    best_ask_valid <= ask_found;
                    best_ask_price <= ask_price;
                    best_ask_quantity <= ask_quantity;
                    result_valid <= 1;
                    state <= COMPLETE;
                end
                // Keep ready low throughout the completion pulse. This edge
                // clears result_valid and returns to IDLE; a new event can be
                // accepted on the next edge if the sender asserts valid.
                COMPLETE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
