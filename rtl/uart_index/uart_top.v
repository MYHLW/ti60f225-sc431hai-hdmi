`timescale 1ns/1ns
// FPGA_UART_Test (updated)
// - retains ctrl_out[7:0] for compatibility (enable1..enable8)
// - adds new port enable9 (toggle by receiving 0x61)
// - instances: integer_divider, uart_receiver, uart_transfer, uart_cmd_parser
module FPGA_UART_Test
#(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer DIVIDE_CNT  = (CLK_FREQ_HZ + BAUD_RATE * 8) / (BAUD_RATE * 16)
)
(
    // global clock and active-low reset
    input               clk,
    input               rst_n,

    // UART physical interface
    input               fpga_rxd,           // PC -> FPGA RX
    output              fpga_txd,           // FPGA -> PC TX

    // control outputs
    output  [7:0]       rxd_data,
    output              rxd_valid,
    output  [7:0]       ctrl_out,           // enable1..enable8 mapped as {e8..e1}
    output              enable9,            // new: separate enable9 (toggle on 0x61)
    output              enable10,           // new: separate enable10 (toggle on 0x62)
    output              enable11,           // new: separate enable11 (toggle on 0x63)
    output              enable12,           // separate enable12 (toggle on 0x64)
    output reg [2:0]    compare_left,
    output reg [2:0]    compare_right,
    output reg          compare_req_toggle
);

    // local signals
    wire    clk_ref = clk;
    wire    sys_rst_n = rst_n;

    //------------------------------------
    // Precise clock divider for UART sampling (as before)
    wire    divide_clken;
    integer_divider
    #(
        .DEVIDE_CNT (DIVIDE_CNT)
    )
    u_integer_devider
    (
        .clk            (clk_ref),
        .rst_n          (sys_rst_n),
        .divide_clken   (divide_clken)
    );
    wire clken_16bps = divide_clken;

    //---------------------------------
    // UART Receiver (PC -> FPGA)
    wire            rxd_flag;
    wire    [7:0]   rxd_data;
    assign rxd_valid = rxd_flag;
    // Independent selectors: RAW, SOBEL, CANNY, BOOST, OVRLY; skip SHAPE.
    // Single-byte actions never latch an enable or require a release byte.
    function [2:0] next_compare_algorithm;
        input [2:0] mode;
        begin
            case (mode)
                0: next_compare_algorithm=1;
                1: next_compare_algorithm=2;
                2: next_compare_algorithm=3;
                3: next_compare_algorithm=5;
                default: next_compare_algorithm=0;
            endcase
        end
    endfunction
    always @(posedge clk_ref or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            compare_left<=2; compare_right<=3; compare_req_toggle<=0;
        end else if (rxd_flag) begin
            if (rxd_data==8'h76) begin
                compare_left<=next_compare_algorithm(compare_left);
                compare_req_toggle<=~compare_req_toggle;
            end else if (rxd_data==8'h77) begin
                compare_right<=next_compare_algorithm(compare_right);
                compare_req_toggle<=~compare_req_toggle;
            end
        end
    end
    uart_receiver u_uart_receiver
    (
        .clk            (clk_ref),
        .rst_n          (sys_rst_n),
        .clken_16bps    (clken_16bps),
        .rxd            (fpga_rxd),
        .rxd_data       (rxd_data),
        .rxd_flag       (rxd_flag)
    );

    //---------------------------------
    // Parser instance: produces enable1..enable9 and txd echo signals
    wire [7:0] parser_txd_data;
    wire       parser_txd_en;
    wire       enable1, enable2, enable3, enable4;
    wire       enable5, enable6, enable7, enable8;

    uart_cmd_parser #(
        .HOLD_CYCLES       (CLK_FREQ_HZ / 1000),
        .DEBOUNCE_CYCLES_9 (CLK_FREQ_HZ / 2000)
    ) u_uart_cmd_parser
    (
        .clk        (clk_ref),
        .rst_n      (sys_rst_n),
        .rxd_data   (rxd_data),
        .rxd_flag   (rxd_flag),

        .txd_data   (parser_txd_data),
        .txd_en     (parser_txd_en),

        .enable1    (enable1),
        .enable2    (enable2),
        .enable3    (enable3),
        .enable4    (enable4),
        .enable5    (enable5),
        .enable6    (enable6),
        .enable7    (enable7),
        .enable8    (enable8),
        .enable9    (enable9),    // NEW: capture enable9..enable12 from parser
        .enable10   (enable10),
        .enable11   (enable11),
        .enable12   (enable12)
    );

    //---------------------------------
    // UART Transmit: use parser's txd_data/txd_en to send echo back to PC
    uart_transfer u_uart_transfer
    (
        .clk            (clk_ref),
        .rst_n          (sys_rst_n),
        .clken_16bps    (clken_16bps),
        .txd            (fpga_txd),

        .txd_en         (parser_txd_en),
        .txd_data       (parser_txd_data),
        .txd_flag       ()
    );

    //---------------------------------
    // Map enables 1..8 back to ctrl_out bus for legacy compatibility
    assign ctrl_out = { enable8, enable7, enable6, enable5,
                        enable4, enable3, enable2, enable1 };

endmodule
