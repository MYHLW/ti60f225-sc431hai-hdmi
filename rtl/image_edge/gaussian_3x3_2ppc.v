module gaussian_3x3_2ppc
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

    // Separable 3x3 kernel [1 2 1]' * [1 2 1], normalized by 16.
    function [9:0] horizontal_sum;
        input [7:0] left;
        input [7:0] center;
        input [7:0] right;
        begin
            horizontal_sum = {2'b0, left} + {1'b0, center, 1'b0} + {2'b0, right};
        end
    endfunction

    wire [9:0] lane0_row0 = horizontal_sum(i_window0[71:64], i_window0[63:56], i_window0[55:48]);
    wire [9:0] lane0_row1 = horizontal_sum(i_window0[47:40], i_window0[39:32], i_window0[31:24]);
    wire [9:0] lane0_row2 = horizontal_sum(i_window0[23:16], i_window0[15:8], i_window0[7:0]);
    wire [9:0] lane1_row0 = horizontal_sum(i_window1[71:64], i_window1[63:56], i_window1[55:48]);
    wire [9:0] lane1_row1 = horizontal_sum(i_window1[47:40], i_window1[39:32], i_window1[31:24]);
    wire [9:0] lane1_row2 = horizontal_sum(i_window1[23:16], i_window1[15:8], i_window1[7:0]);

    reg sof_1p, sol_1p, valid_1p;
    reg [1:0] border_1p;
    reg [9:0] lane0_row0_1p, lane0_row1_1p, lane0_row2_1p;
    reg [9:0] lane1_row0_1p, lane1_row1_1p, lane1_row2_1p;

    reg sof_2p, sol_2p, valid_2p;
    reg [1:0] border_2p;
    reg [11:0] lane0_sum_2p, lane1_sum_2p;
    wire [11:0] lane0_rounded = lane0_sum_2p + 12'd8;
    wire [11:0] lane1_rounded = lane1_sum_2p + 12'd8;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sof_1p <= 1'b0;
            sol_1p <= 1'b0;
            valid_1p <= 1'b0;
            border_1p <= 2'b11;
            lane0_row0_1p <= 10'b0;
            lane0_row1_1p <= 10'b0;
            lane0_row2_1p <= 10'b0;
            lane1_row0_1p <= 10'b0;
            lane1_row1_1p <= 10'b0;
            lane1_row2_1p <= 10'b0;
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
            lane0_sum_2p <= 12'b0;
            lane1_sum_2p <= 12'b0;
        end else begin
            sof_2p <= sof_1p;
            sol_2p <= sol_1p;
            valid_2p <= valid_1p;
            border_2p <= border_1p;
            lane0_sum_2p <= {2'b0, lane0_row0_1p} + {1'b0, lane0_row1_1p, 1'b0} + {2'b0, lane0_row2_1p};
            lane1_sum_2p <= {2'b0, lane1_row0_1p} + {1'b0, lane1_row1_1p, 1'b0} + {2'b0, lane1_row2_1p};
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
            o_gray[15:8] <= border_2p[0] ? 8'b0 : lane0_rounded[11:4];
            o_gray[7:0] <= border_2p[1] ? 8'b0 : lane1_rounded[11:4];
        end
    end

endmodule
