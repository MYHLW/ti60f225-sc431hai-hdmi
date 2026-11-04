module median_3x3_2ppc
(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_sof,
    input  wire        i_sol,
    input  wire        i_valid,
    input  wire [1:0]  i_border,
    input  wire [71:0] i_window0,
    input  wire [71:0] i_window1,

    output reg         o_sof,
    output reg         o_sol,
    output reg         o_valid,
    output reg  [1:0]  o_border,
    output reg  [15:0] o_gray
);

    function [23:0] sort3;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        reg [7:0] lo;
        reg [7:0] mid;
        reg [7:0] hi;
        reg [7:0] swap;
        begin
            lo = a;
            mid = b;
            hi = c;
            if (lo > mid) begin swap = lo; lo = mid; mid = swap; end
            if (mid > hi) begin swap = mid; mid = hi; hi = swap; end
            if (lo > mid) begin swap = lo; lo = mid; mid = swap; end
            sort3 = {lo, mid, hi};
        end
    endfunction

    wire [23:0] lane0_row0 = sort3(i_window0[71:64], i_window0[63:56], i_window0[55:48]);
    wire [23:0] lane0_row1 = sort3(i_window0[47:40], i_window0[39:32], i_window0[31:24]);
    wire [23:0] lane0_row2 = sort3(i_window0[23:16], i_window0[15:8],  i_window0[7:0]);
    wire [23:0] lane1_row0 = sort3(i_window1[71:64], i_window1[63:56], i_window1[55:48]);
    wire [23:0] lane1_row1 = sort3(i_window1[47:40], i_window1[39:32], i_window1[31:24]);
    wire [23:0] lane1_row2 = sort3(i_window1[23:16], i_window1[15:8],  i_window1[7:0]);

    reg sof_1p, sol_1p, valid_1p;
    reg [1:0] border_1p;
    reg [23:0] lane0_row0_1p, lane0_row1_1p, lane0_row2_1p;
    reg [23:0] lane1_row0_1p, lane1_row1_1p, lane1_row2_1p;

    reg sof_2p, sol_2p, valid_2p;
    reg [1:0] border_2p;
    reg [7:0] lane0_a_2p, lane0_b_2p, lane0_c_2p;
    reg [7:0] lane1_a_2p, lane1_b_2p, lane1_c_2p;

    wire [23:0] lane0_mid_sort = sort3(lane0_row0_1p[15:8], lane0_row1_1p[15:8], lane0_row2_1p[15:8]);
    wire [23:0] lane1_mid_sort = sort3(lane1_row0_1p[15:8], lane1_row1_1p[15:8], lane1_row2_1p[15:8]);
    wire [7:0] lane0_max_lo = (lane0_row0_1p[23:16] > lane0_row1_1p[23:16]) ?
                                ((lane0_row0_1p[23:16] > lane0_row2_1p[23:16]) ? lane0_row0_1p[23:16] : lane0_row2_1p[23:16]) :
                                ((lane0_row1_1p[23:16] > lane0_row2_1p[23:16]) ? lane0_row1_1p[23:16] : lane0_row2_1p[23:16]);
    wire [7:0] lane1_max_lo = (lane1_row0_1p[23:16] > lane1_row1_1p[23:16]) ?
                                ((lane1_row0_1p[23:16] > lane1_row2_1p[23:16]) ? lane1_row0_1p[23:16] : lane1_row2_1p[23:16]) :
                                ((lane1_row1_1p[23:16] > lane1_row2_1p[23:16]) ? lane1_row1_1p[23:16] : lane1_row2_1p[23:16]);
    wire [7:0] lane0_min_hi = (lane0_row0_1p[7:0] < lane0_row1_1p[7:0]) ?
                                ((lane0_row0_1p[7:0] < lane0_row2_1p[7:0]) ? lane0_row0_1p[7:0] : lane0_row2_1p[7:0]) :
                                ((lane0_row1_1p[7:0] < lane0_row2_1p[7:0]) ? lane0_row1_1p[7:0] : lane0_row2_1p[7:0]);
    wire [7:0] lane1_min_hi = (lane1_row0_1p[7:0] < lane1_row1_1p[7:0]) ?
                                ((lane1_row0_1p[7:0] < lane1_row2_1p[7:0]) ? lane1_row0_1p[7:0] : lane1_row2_1p[7:0]) :
                                ((lane1_row1_1p[7:0] < lane1_row2_1p[7:0]) ? lane1_row1_1p[7:0] : lane1_row2_1p[7:0]);
    wire [23:0] lane0_final_sort = sort3(lane0_a_2p, lane0_b_2p, lane0_c_2p);
    wire [23:0] lane1_final_sort = sort3(lane1_a_2p, lane1_b_2p, lane1_c_2p);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sof_1p <= 1'b0;
            sol_1p <= 1'b0;
            valid_1p <= 1'b0;
            border_1p <= 2'b11;
            lane0_row0_1p <= 24'b0;
            lane0_row1_1p <= 24'b0;
            lane0_row2_1p <= 24'b0;
            lane1_row0_1p <= 24'b0;
            lane1_row1_1p <= 24'b0;
            lane1_row2_1p <= 24'b0;
        end else begin
            sof_1p <= i_sof;
            sol_1p <= i_sol;
            valid_1p <= i_valid;
            border_1p <= i_border;
            lane0_row0_1p <= lane0_row0;
            lane0_row1_1p <= lane0_row1;
            lane0_row2_1p <= lane0_row2;
            lane1_row0_1p <= lane1_row0;
            lane1_row1_1p <= lane1_row1;
            lane1_row2_1p <= lane1_row2;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sof_2p <= 1'b0;
            sol_2p <= 1'b0;
            valid_2p <= 1'b0;
            border_2p <= 2'b11;
            lane0_a_2p <= 8'b0;
            lane0_b_2p <= 8'b0;
            lane0_c_2p <= 8'b0;
            lane1_a_2p <= 8'b0;
            lane1_b_2p <= 8'b0;
            lane1_c_2p <= 8'b0;
        end else begin
            sof_2p <= sof_1p;
            sol_2p <= sol_1p;
            valid_2p <= valid_1p;
            border_2p <= border_1p;
            lane0_a_2p <= lane0_max_lo;
            lane0_b_2p <= lane0_mid_sort[15:8];
            lane0_c_2p <= lane0_min_hi;
            lane1_a_2p <= lane1_max_lo;
            lane1_b_2p <= lane1_mid_sort[15:8];
            lane1_c_2p <= lane1_min_hi;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_sof <= 1'b0;
            o_sol <= 1'b0;
            o_valid <= 1'b0;
            o_border <= 2'b11;
            o_gray <= 16'b0;
        end else begin
            o_sof <= sof_2p;
            o_sol <= sol_2p;
            o_valid <= valid_2p;
            o_border <= border_2p;
            o_gray[15:8] <= border_2p[0] ? 8'b0 : lane0_final_sort[15:8];
            o_gray[7:0] <= border_2p[1] ? 8'b0 : lane1_final_sort[15:8];
        end
    end

endmodule
