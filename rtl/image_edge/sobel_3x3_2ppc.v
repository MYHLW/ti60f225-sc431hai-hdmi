module sobel_3x3_2ppc
(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               i_sof,
    input  wire               i_sol,
    input  wire               i_valid,
    input  wire [1:0]         i_border,
    input  wire [71:0]        i_window0,
    input  wire [71:0]        i_window1,
    input  wire [10:0]        i_threshold,

    output reg                o_sof,
    output reg                o_sol,
    output reg                o_valid,
    output reg  [1:0]         o_border,
    output reg signed [11:0]  o_gx0,
    output reg signed [11:0]  o_gy0,
    output reg signed [11:0]  o_gx1,
    output reg signed [11:0]  o_gy1,
    output reg  [21:0]        o_magnitude,
    output reg  [15:0]        o_binary
);

    wire [7:0] w0_p00 = i_window0[71:64];
    wire [7:0] w0_p01 = i_window0[63:56];
    wire [7:0] w0_p02 = i_window0[55:48];
    wire [7:0] w0_p10 = i_window0[47:40];
    wire [7:0] w0_p12 = i_window0[31:24];
    wire [7:0] w0_p20 = i_window0[23:16];
    wire [7:0] w0_p21 = i_window0[15:8];
    wire [7:0] w0_p22 = i_window0[7:0];

    wire [7:0] w1_p00 = i_window1[71:64];
    wire [7:0] w1_p01 = i_window1[63:56];
    wire [7:0] w1_p02 = i_window1[55:48];
    wire [7:0] w1_p10 = i_window1[47:40];
    wire [7:0] w1_p12 = i_window1[31:24];
    wire [7:0] w1_p20 = i_window1[23:16];
    wire [7:0] w1_p21 = i_window1[15:8];
    wire [7:0] w1_p22 = i_window1[7:0];

    reg sof_1p, sol_1p, valid_1p;
    reg sof_2p, sol_2p, valid_2p;
    reg [1:0] border_1p, border_2p;
    reg [10:0] threshold_1p, threshold_2p;
    reg [10:0] gx0_pos_1p, gx0_neg_1p, gy0_pos_1p, gy0_neg_1p;
    reg [10:0] gx1_pos_1p, gx1_neg_1p, gy1_pos_1p, gy1_neg_1p;
    reg signed [11:0] gx0_2p, gy0_2p, gx1_2p, gy1_2p;

    wire [10:0] abs_gx0 = gx0_2p[11] ? (~gx0_2p[10:0] + 1'b1) : gx0_2p[10:0];
    wire [10:0] abs_gy0 = gy0_2p[11] ? (~gy0_2p[10:0] + 1'b1) : gy0_2p[10:0];
    wire [10:0] abs_gx1 = gx1_2p[11] ? (~gx1_2p[10:0] + 1'b1) : gx1_2p[10:0];
    wire [10:0] abs_gy1 = gy1_2p[11] ? (~gy1_2p[10:0] + 1'b1) : gy1_2p[10:0];
    wire [10:0] max_gradient0 = (abs_gx0 >= abs_gy0) ? abs_gx0 : abs_gy0;
    wire [10:0] min_gradient0 = (abs_gx0 >= abs_gy0) ? abs_gy0 : abs_gx0;
    wire [10:0] max_gradient1 = (abs_gx1 >= abs_gy1) ? abs_gx1 : abs_gy1;
    wire [10:0] min_gradient1 = (abs_gx1 >= abs_gy1) ? abs_gy1 : abs_gx1;
    // Low-cost Euclidean magnitude approximation.  The maximum error is much
    // smaller than |Gx|+|Gy| and the response is less dependent on edge angle.
    wire [11:0] magnitude0_full = {1'b0, max_gradient0} +
                                  {3'b0, min_gradient0[10:2]} +
                                  {4'b0, min_gradient0[10:3]};
    wire [11:0] magnitude1_full = {1'b0, max_gradient1} +
                                  {3'b0, min_gradient1[10:2]} +
                                  {4'b0, min_gradient1[10:3]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sof_1p <= 1'b0;
            sol_1p <= 1'b0;
            valid_1p <= 1'b0;
            border_1p <= 2'b11;
            threshold_1p <= 11'b0;
            gx0_pos_1p <= 11'b0;
            gx0_neg_1p <= 11'b0;
            gy0_pos_1p <= 11'b0;
            gy0_neg_1p <= 11'b0;
            gx1_pos_1p <= 11'b0;
            gx1_neg_1p <= 11'b0;
            gy1_pos_1p <= 11'b0;
            gy1_neg_1p <= 11'b0;
        end else begin
            sof_1p <= i_sof;
            sol_1p <= i_sol;
            valid_1p <= i_valid;
            border_1p <= i_border;
            threshold_1p <= i_threshold;
            gx0_pos_1p <= {3'b0, w0_p02} + {2'b0, w0_p12, 1'b0} + {3'b0, w0_p22};
            gx0_neg_1p <= {3'b0, w0_p00} + {2'b0, w0_p10, 1'b0} + {3'b0, w0_p20};
            gy0_pos_1p <= {3'b0, w0_p20} + {2'b0, w0_p21, 1'b0} + {3'b0, w0_p22};
            gy0_neg_1p <= {3'b0, w0_p00} + {2'b0, w0_p01, 1'b0} + {3'b0, w0_p02};
            gx1_pos_1p <= {3'b0, w1_p02} + {2'b0, w1_p12, 1'b0} + {3'b0, w1_p22};
            gx1_neg_1p <= {3'b0, w1_p00} + {2'b0, w1_p10, 1'b0} + {3'b0, w1_p20};
            gy1_pos_1p <= {3'b0, w1_p20} + {2'b0, w1_p21, 1'b0} + {3'b0, w1_p22};
            gy1_neg_1p <= {3'b0, w1_p00} + {2'b0, w1_p01, 1'b0} + {3'b0, w1_p02};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sof_2p <= 1'b0;
            sol_2p <= 1'b0;
            valid_2p <= 1'b0;
            border_2p <= 2'b11;
            threshold_2p <= 11'b0;
            gx0_2p <= 12'sd0;
            gy0_2p <= 12'sd0;
            gx1_2p <= 12'sd0;
            gy1_2p <= 12'sd0;
        end else begin
            sof_2p <= sof_1p;
            sol_2p <= sol_1p;
            valid_2p <= valid_1p;
            border_2p <= border_1p;
            threshold_2p <= threshold_1p;
            gx0_2p <= $signed({1'b0, gx0_pos_1p}) - $signed({1'b0, gx0_neg_1p});
            gy0_2p <= $signed({1'b0, gy0_pos_1p}) - $signed({1'b0, gy0_neg_1p});
            gx1_2p <= $signed({1'b0, gx1_pos_1p}) - $signed({1'b0, gx1_neg_1p});
            gy1_2p <= $signed({1'b0, gy1_pos_1p}) - $signed({1'b0, gy1_neg_1p});
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_sof <= 1'b0;
            o_sol <= 1'b0;
            o_valid <= 1'b0;
            o_border <= 2'b11;
            o_gx0 <= 12'sd0;
            o_gy0 <= 12'sd0;
            o_gx1 <= 12'sd0;
            o_gy1 <= 12'sd0;
            o_magnitude <= 22'b0;
            o_binary <= 16'b0;
        end else begin
            o_sof <= sof_2p;
            o_sol <= sol_2p;
            o_valid <= valid_2p;
            o_border <= border_2p;
            o_gx0 <= border_2p[0] ? 12'sd0 : gx0_2p;
            o_gy0 <= border_2p[0] ? 12'sd0 : gy0_2p;
            o_gx1 <= border_2p[1] ? 12'sd0 : gx1_2p;
            o_gy1 <= border_2p[1] ? 12'sd0 : gy1_2p;
            o_magnitude[21:11] <= border_2p[0] ? 11'b0 : magnitude0_full[10:0];
            o_magnitude[10:0] <= border_2p[1] ? 11'b0 : magnitude1_full[10:0];
            o_binary[15:8] <= (!border_2p[0] && magnitude0_full[10:0] > threshold_2p) ? 8'hff : 8'h00;
            o_binary[7:0] <= (!border_2p[1] && magnitude1_full[10:0] > threshold_2p) ? 8'hff : 8'h00;
        end
    end

endmodule
