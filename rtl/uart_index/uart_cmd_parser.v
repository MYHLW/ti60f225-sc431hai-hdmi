// `timescale 1ns/1ns
// // uart_cmd_parser - set-only enables + toggle enable9
// // Behavior:
// //  - 0x01..0x08 -> set enable1..enable8 = 1 respectively (others unchanged)
// //  - 0x00        -> clear all enables
// //  - 0x61        -> toggle enable9
// //  - others      -> no change
// // Echo: send back sampled byte (txd_data) with 1-cycle txd_en pulse when processed.
// module uart_cmd_parser
// (
//     input           clk,
//     input           rst_n,

//     // UART receiver interface
//     input   [7:0]   rxd_data,
//     input           rxd_flag,   // pulse: new byte available

//     // UART transmitter interface (echo)
//     output reg [7:0] txd_data,
//     output reg       txd_en,

//     // Enables 1..9
//     output reg       enable1,
//     output reg       enable2,
//     output reg       enable3,
//     output reg       enable4,
//     output reg       enable5,
//     output reg       enable6,
//     output reg       enable7,
//     output reg       enable8,
//     output reg       enable9
// );

//     // sampled byte and pending flag (two-stage processing)
//     reg [7:0] rxd_byte;
//     reg       rxd_pending;

//     // Stage1: sample incoming byte when rxd_flag asserted
//     always @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             rxd_byte    <= 8'd0;
//             rxd_pending <= 1'b0;
//         end else begin
//             if (rxd_flag) begin
//                 rxd_byte    <= rxd_data;   // sample newly received byte
//                 rxd_pending <= 1'b1;      // mark pending for next cycle
//             end else begin
//                 rxd_pending <= 1'b0;      // single-cycle pending behavior
//             end
//         end
//     end

//     // Stage2: apply command when pending (set-only semantics, toggle for 0x61)
//     always @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             enable1 <= 1'b0;
//             enable2 <= 1'b0;
//             enable3 <= 1'b0;
//             enable4 <= 1'b0;
//             enable5 <= 1'b0;
//             enable6 <= 1'b0;
//             enable7 <= 1'b0;
//             enable8 <= 1'b0;
//             enable9 <= 1'b0;
//         end else begin
//             if (rxd_pending) begin
//                 case (rxd_byte)
//                     8'h00: begin
//                         // clear all enables
//                         enable1 <= 1'b0;
//                         enable2 <= 1'b0;
//                         enable3 <= 1'b0;
//                         enable4 <= 1'b0;
//                         enable5 <= 1'b0;
//                         enable6 <= 1'b0;
//                         enable7 <= 1'b0;
//                         enable8 <= 1'b0;
//                         // keep enable9 unchanged on 0x00 (optional: change if you want)
//                     end
//                     8'h01: begin enable1 <= 1'b1; end
//                     8'h02: begin enable2 <= 1'b1; end
//                     8'h03: begin enable3 <= 1'b1; end
//                     8'h04: begin enable4 <= 1'b1; end
//                     8'h05: begin enable5 <= 1'b1; end
//                     8'h06: begin enable6 <= 1'b1; end
//                     8'h07: begin enable7 <= 1'b1; end
//                     8'h08: begin enable8 <= 1'b1; end
//                     8'h61: begin enable9 <= ~enable9; end // toggle enable9
//                     default: begin
//                         // do nothing: keep previous enables
//                         enable1 <= enable1;
//                         enable2 <= enable2;
//                         enable3 <= enable3;
//                         enable4 <= enable4;
//                         enable5 <= enable5;
//                         enable6 <= enable6;
//                         enable7 <= enable7;
//                         enable8 <= enable8;
//                         enable9 <= enable9;
//                     end
//                 endcase
//             end
//             // if not pending, keep enables unchanged (no extra assignments)
//         end
//     end

//     // Echo: output sampled byte during processing cycle
//     always @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             txd_data <= 8'd0;
//             txd_en   <= 1'b0;
//         end else begin
//             txd_data <= rxd_byte;
//             txd_en   <= rxd_pending; // 1-cycle pulse when processing
//         end
//     end

// endmodule
/*
`timescale 1ns/1ns
// uart_cmd_parser - set/clear/toggle enables
// Behavior:
//  - 0x01..0x08 -> set enable1..enable8 = 1 respectively (others unchanged)
//  - 0x81..0x88 -> clear enable1..enable8 respectively (others unchanged)
//  - 0x00        -> clear all enables (enable1..enable8); enable9 unchanged
//  - 0x61        -> toggle enable9
//  - others      -> no change
// Echo: send back sampled byte (txd_data) with 1-cycle txd_en pulse when processed.
module uart_cmd_parser
(
    input           clk,
    input           rst_n,

    // UART receiver interface
    input   [7:0]   rxd_data,
    input           rxd_flag,   // pulse: new byte available

    // UART transmitter interface (echo)
    output reg [7:0] txd_data,
    output reg       txd_en,

    // Enables 1..9
    output reg       enable1,
    output reg       enable2,
    output reg       enable3,
    output reg       enable4,
    output reg       enable5,
    output reg       enable6,
    output reg       enable7,
    output reg       enable8,
    output reg       enable9
);

    // sampled byte and pending flag (two-stage processing)
    reg [7:0] rxd_byte;
    reg       rxd_pending;

    // Stage1: sample incoming byte when rxd_flag asserted
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_byte    <= 8'd0;
            rxd_pending <= 1'b0;
        end else begin
            if (rxd_flag) begin
                rxd_byte    <= rxd_data;   // sample newly received byte
                rxd_pending <= 1'b1;      // mark pending for next cycle
            end else begin
                rxd_pending <= 1'b0;      // single-cycle pending behavior
            end
        end
    end

    // Stage2: apply command when pending
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable1 <= 1'b0;
            enable2 <= 1'b0;
            enable3 <= 1'b0;
            enable4 <= 1'b0;
            enable5 <= 1'b0;
            enable6 <= 1'b0;
            enable7 <= 1'b0;
            enable8 <= 1'b0;
            enable9 <= 1'b0; enable10 <= 1'b0; enable11 <= 1'b0; enable12 <= 1'b0;
        end else begin
            if (rxd_pending) begin
                case (rxd_byte)
                    8'h00: begin
                        // clear all 1..8 (leave enable9 unchanged)
                        enable1 <= 1'b0;
                        enable2 <= 1'b0;
                        enable3 <= 1'b0;
                        enable4 <= 1'b0;
                        enable5 <= 1'b0;
                        enable6 <= 1'b0;
                        enable7 <= 1'b0;
                        enable8 <= 1'b0;
                    end
                    // set commands
                    8'h01: begin enable1 <= 1'b1; end
                    8'h02: begin enable2 <= 1'b1; end
                    8'h03: begin enable3 <= 1'b1; end
                    8'h04: begin enable4 <= 1'b1; end
                    8'h05: begin enable5 <= 1'b1; end
                    8'h06: begin enable6 <= 1'b1; end
                    8'h07: begin enable7 <= 1'b1; end
                    8'h08: begin enable8 <= 1'b1; end

                    // clear commands (0x81..0x88)
                    8'h81: begin enable1 <= 1'b0; end
                    8'h82: begin enable2 <= 1'b0; end
                    8'h83: begin enable3 <= 1'b0; end
                    8'h84: begin enable4 <= 1'b0; end
                    8'h85: begin enable5 <= 1'b0; end
                    8'h86: begin enable6 <= 1'b0; end
                    8'h87: begin enable7 <= 1'b0; end
                    8'h88: begin enable8 <= 1'b0; end

                    // toggle enable9
                    8'h61: begin enable9 <= ~enable9; end

                    default: begin
                        // do nothing (preserve all enables)
                        enable1 <= enable1;
                        enable2 <= enable2;
                        enable3 <= enable3;
                        enable4 <= enable4;
                        enable5 <= enable5;
                        enable6 <= enable6;
                        enable7 <= enable7;
                        enable8 <= enable8;
                        enable9 <= enable9;
                    end
                endcase
            end
            // when not pending, retain current enables (no assignments needed)
        end
    end

    // Echo: output sampled byte during processing cycle
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            txd_data <= 8'd0;
            txd_en   <= 1'b0;
        end else begin
            txd_data <= rxd_byte;
            txd_en   <= rxd_pending; // 1-cycle pulse when processing
        end
    end

endmodule */
 `timescale 1ns/1ns
// uart_cmd_parser - set/clear/toggle enables with hold & debounce protection
// Features:
//  - 0x01..0x08 -> set enable1..enable8 = 1 (others unchanged). When set, each enable gets a hold timer.
//  - 0x81..0x88 -> clear specific enable1..enable8; if hold active, mark clear_pending and clear after hold expires.
//  - 0x00        -> request clear all enable1..enable8 (will obey holds: pending clear if hold active).
//  - 0x61        -> toggle enable9, but protected by debounce window to avoid double-toggle from press+release.
//  - Others      -> no change
//  - Echo: send back sampled byte (txd_data) with 1-cycle txd_en pulse when processed.
//
// NOTE:
//  - Adjust HOLD_CYCLES and DEBOUNCE_CYCLES_9 according to your FPGA clock frequency.
//  - Default values assume a 96 MHz clk: HOLD_CYCLES=96_000 ~= 1 ms, DEBOUNCE_CYCLES_9=48_000 ~= 0.5 ms.

module uart_cmd_parser
#(
    parameter integer HOLD_CYCLES         = 96_000,   // hold duration in clock cycles for enable1..8 (default ~1ms @96MHz)
    parameter integer DEBOUNCE_CYCLES_9   = 48_000    // debounce window for enable9 toggle (~0.5ms @96MHz)
)
(
    input           clk,
    input           rst_n,

    // UART receiver interface
    input   [7:0]   rxd_data,
    input           rxd_flag,   // pulse: new byte available

    // UART transmitter interface (echo)
    output reg [7:0] txd_data,
    output reg       txd_en,

    // Enables 1..9 outputs
    output reg       enable1,
    output reg       enable2,
    output reg       enable3,
    output reg       enable4,
    output reg       enable5,
    output reg       enable6,
    output reg       enable7,
    output reg       enable8,
    output reg       enable9,
    output reg       enable10,
    output reg       enable11,
    output reg       enable12
);

    // ----------------------------
    // Internal registers
    // ----------------------------
    reg [7:0] rxd_byte;
    reg       rxd_pending;

    // hold counters for enable1..enable8 (down counters)
    reg [31:0] hold_cnt1, hold_cnt2, hold_cnt3, hold_cnt4;
    reg [31:0] hold_cnt5, hold_cnt6, hold_cnt7, hold_cnt8;
    // pending clear flags when clear command received during hold
    reg        clear_pending1, clear_pending2, clear_pending3, clear_pending4;
    reg        clear_pending5, clear_pending6, clear_pending7, clear_pending8;

    // debounce counter for enable9
    reg [31:0] debounce_cnt9;
    // debounce counters for enable10..enable12 (same behavior as enable9)
    reg [31:0] debounce_cnt10;
    reg [31:0] debounce_cnt11;
    reg [31:0] debounce_cnt12;

    // ----------------------------
    // Stage1: sample incoming byte when rxd_flag asserted
    // ----------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_byte    <= 8'd0;
            rxd_pending <= 1'b0;
        end else begin
            if (rxd_flag) begin
                rxd_byte    <= rxd_data;
                rxd_pending <= 1'b1;
            end else begin
                rxd_pending <= 1'b0;
            end
        end
    end

    // ----------------------------
    // Stage2: process command when pending
    // ----------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // clear enables
            enable1 <= 1'b0; enable2 <= 1'b0; enable3 <= 1'b0; enable4 <= 1'b0;
            enable5 <= 1'b0; enable6 <= 1'b0; enable7 <= 1'b0; enable8 <= 1'b0;
            enable9 <= 1'b0; enable10 <= 1'b0; enable11 <= 1'b0; enable12 <= 1'b0;

            // clear counters and pending flags
            hold_cnt1 <= 32'd0; hold_cnt2 <= 32'd0; hold_cnt3 <= 32'd0; hold_cnt4 <= 32'd0;
            hold_cnt5 <= 32'd0; hold_cnt6 <= 32'd0; hold_cnt7 <= 32'd0; hold_cnt8 <= 32'd0;

            clear_pending1 <= 1'b0; clear_pending2 <= 1'b0; clear_pending3 <= 1'b0; clear_pending4 <= 1'b0;
            clear_pending5 <= 1'b0; clear_pending6 <= 1'b0; clear_pending7 <= 1'b0; clear_pending8 <= 1'b0;

            debounce_cnt9 <= 32'd0; debounce_cnt10 <= 32'd0;
            debounce_cnt11 <= 32'd0; debounce_cnt12 <= 32'd0;
        end else begin
            if (rxd_pending) begin
                // decode command
                case (rxd_byte)
                    // clear-all request: mark clear for those with active hold, immediate clear for others
                    8'h00: begin
                        // for each enable i: if hold==0 -> clear immediately; else mark pending
                        if (hold_cnt1 == 0) enable1 <= 1'b0; else clear_pending1 <= 1'b1;
                        if (hold_cnt2 == 0) enable2 <= 1'b0; else clear_pending2 <= 1'b1;
                        if (hold_cnt3 == 0) enable3 <= 1'b0; else clear_pending3 <= 1'b1;
                        if (hold_cnt4 == 0) enable4 <= 1'b0; else clear_pending4 <= 1'b1;
                        if (hold_cnt5 == 0) enable5 <= 1'b0; else clear_pending5 <= 1'b1;
                        if (hold_cnt6 == 0) enable6 <= 1'b0; else clear_pending6 <= 1'b1;
                        if (hold_cnt7 == 0) enable7 <= 1'b0; else clear_pending7 <= 1'b1;
                        if (hold_cnt8 == 0) enable8 <= 1'b0; else clear_pending8 <= 1'b1;
                        // leave enable9 unchanged
                    end

                    // set commands (01..08): set enable and reload hold counter
                    8'h01: begin enable1 <= 1'b1; hold_cnt1 <= HOLD_CYCLES; clear_pending1 <= 1'b0; end
                    8'h02: begin enable2 <= 1'b1; hold_cnt2 <= HOLD_CYCLES; clear_pending2 <= 1'b0; end
                    8'h03: begin enable3 <= 1'b1; hold_cnt3 <= HOLD_CYCLES; clear_pending3 <= 1'b0; end
                    8'h04: begin enable4 <= 1'b1; hold_cnt4 <= HOLD_CYCLES; clear_pending4 <= 1'b0; end
                    8'h05: begin enable5 <= 1'b1; hold_cnt5 <= HOLD_CYCLES; clear_pending5 <= 1'b0; end
                    8'h06: begin enable6 <= 1'b1; hold_cnt6 <= HOLD_CYCLES; clear_pending6 <= 1'b0; end
                    8'h07: begin enable7 <= 1'b1; hold_cnt7 <= HOLD_CYCLES; clear_pending7 <= 1'b0; end
                    8'h08: begin enable8 <= 1'b1; hold_cnt8 <= HOLD_CYCLES; clear_pending8 <= 1'b0; end

                    // clear single (81..88): if hold==0 clear immediately else mark pending
                    8'h81: begin if (hold_cnt1==0) enable1 <= 1'b0; else clear_pending1 <= 1'b1; end
                    8'h82: begin if (hold_cnt2==0) enable2 <= 1'b0; else clear_pending2 <= 1'b1; end
                    8'h83: begin if (hold_cnt3==0) enable3 <= 1'b0; else clear_pending3 <= 1'b1; end
                    8'h84: begin if (hold_cnt4==0) enable4 <= 1'b0; else clear_pending4 <= 1'b1; end
                    8'h85: begin if (hold_cnt5==0) enable5 <= 1'b0; else clear_pending5 <= 1'b1; end
                    8'h86: begin if (hold_cnt6==0) enable6 <= 1'b0; else clear_pending6 <= 1'b1; end
                    8'h87: begin if (hold_cnt7==0) enable7 <= 1'b0; else clear_pending7 <= 1'b1; end
                    8'h88: begin if (hold_cnt8==0) enable8 <= 1'b0; else clear_pending8 <= 1'b1; end

                    // toggle enable9, but ignore if within debounce window
                    8'h61: begin
                        if (debounce_cnt9 == 0) begin
                            enable9 <= ~enable9;
                            debounce_cnt9 <= DEBOUNCE_CYCLES_9;
                        end
                        // if debounce_cnt9 > 0, ignore this 0x61
                    end

                        // toggle enable10..enable12 (0x62..0x64), same debounce behavior
                        8'h62: begin
                            if (debounce_cnt10 == 0) begin
                                enable10 <= ~enable10;
                                debounce_cnt10 <= DEBOUNCE_CYCLES_9;
                            end
                        end
                        8'h63: begin
                            if (debounce_cnt11 == 0) begin
                                enable11 <= ~enable11;
                                debounce_cnt11 <= DEBOUNCE_CYCLES_9;
                            end
                        end
                        8'h64: begin
                            if (debounce_cnt12 == 0) begin
                                enable12 <= ~enable12;
                                debounce_cnt12 <= DEBOUNCE_CYCLES_9;
                            end
                        end

                    default: begin
                        // ignore unknown codes, preserve enables
                    end
                endcase
            end

            // Each clock tick: decrement hold counters if non-zero;
            // when a hold counter expires and clear_pending is set, perform the clear.
            if (hold_cnt1 != 0) begin
                hold_cnt1 <= hold_cnt1 - 1;
                if (hold_cnt1 == 1) begin
                    // it will reach zero this tick -> check pending
                    if (clear_pending1) begin
                        enable1 <= 1'b0;
                        clear_pending1 <= 1'b0;
                    end
                end
            end

            if (hold_cnt2 != 0) begin
                hold_cnt2 <= hold_cnt2 - 1;
                if (hold_cnt2 == 1) if (clear_pending2) begin enable2 <= 1'b0; clear_pending2 <= 1'b0; end
            end

            if (hold_cnt3 != 0) begin
                hold_cnt3 <= hold_cnt3 - 1;
                if (hold_cnt3 == 1) if (clear_pending3) begin enable3 <= 1'b0; clear_pending3 <= 1'b0; end
            end

            if (hold_cnt4 != 0) begin
                hold_cnt4 <= hold_cnt4 - 1;
                if (hold_cnt4 == 1) if (clear_pending4) begin enable4 <= 1'b0; clear_pending4 <= 1'b0; end
            end

            if (hold_cnt5 != 0) begin
                hold_cnt5 <= hold_cnt5 - 1;
                if (hold_cnt5 == 1) if (clear_pending5) begin enable5 <= 1'b0; clear_pending5 <= 1'b0; end
            end

            if (hold_cnt6 != 0) begin
                hold_cnt6 <= hold_cnt6 - 1;
                if (hold_cnt6 == 1) if (clear_pending6) begin enable6 <= 1'b0; clear_pending6 <= 1'b0; end
            end

            if (hold_cnt7 != 0) begin
                hold_cnt7 <= hold_cnt7 - 1;
                if (hold_cnt7 == 1) if (clear_pending7) begin enable7 <= 1'b0; clear_pending7 <= 1'b0; end
            end

            if (hold_cnt8 != 0) begin
                hold_cnt8 <= hold_cnt8 - 1;
                if (hold_cnt8 == 1) if (clear_pending8) begin enable8 <= 1'b0; clear_pending8 <= 1'b0; end
            end

            // debounce counter for enable9: decrement if >0
            if (debounce_cnt9 != 0) begin
                debounce_cnt9 <= debounce_cnt9 - 1;
            end
            // debounce counters for enable10..12: decrement if >0
            if (debounce_cnt10 != 0) begin
                debounce_cnt10 <= debounce_cnt10 - 1;
            end
            if (debounce_cnt11 != 0) begin
                debounce_cnt11 <= debounce_cnt11 - 1;
            end
            if (debounce_cnt12 != 0) begin
                debounce_cnt12 <= debounce_cnt12 - 1;
            end
        end
    end

    // ----------------------------
    // Echo: output sampled byte during processing cycle
    // ----------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            txd_data <= 8'd0;
            txd_en   <= 1'b0;
        end else begin
            txd_data <= rxd_byte;
            txd_en   <= rxd_pending; // 1-cycle pulse when processing
        end
    end

endmodule
