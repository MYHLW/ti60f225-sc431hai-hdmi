module ccl_edge_conditioner_2ppc #(
    parameter integer IMAGE_WIDTH     = 1920,
    parameter integer IMAGE_HEIGHT    = 1080,
    parameter integer PAIR_ADDR_WIDTH = 10,
    parameter integer ROW_COUNT_WIDTH = 11
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_sof,
    input  wire        i_sol,
    input  wire        i_valid,
    input  wire [15:0] i_binary,
    input  wire [3:0]  i_direction,

    output wire        o_sof,
    output wire        o_sol,
    output wire        o_valid,
    output wire [15:0] o_binary,
    output wire [3:0]  o_direction,
    output wire [1:0]  o_direction_valid
);

    // Two 3x3 dilations form a 5x5 connection mask for the recognition branch.
    // Bit 7 is the expanding mask.  Bit 6 and bits 1:0 preserve the original
    // Canny edge and its direction, so synthetic bridge pixels do not bias the
    // per-component direction histogram.
    wire [7:0] input_sample0 = {|i_binary[15:8], 1'b0, 4'b0, i_direction[3:2]};
    wire [7:0] input_sample1 = {|i_binary[7:0],  1'b0, 4'b0, i_direction[1:0]};

    wire stage1_sof;
    wire stage1_sol;
    wire stage1_valid;
    wire [71:0] stage1_window0;
    wire [71:0] stage1_window1;
    window_3x3_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH),
        .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH)
    ) stage1_window_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(i_sof), .i_sol(i_sol), .i_valid(i_valid),
        .i_gray({input_sample0, input_sample1}),
        .o_sof(stage1_sof), .o_sol(stage1_sol), .o_valid(stage1_valid),
        .o_border(), .o_window0(stage1_window0), .o_window1(stage1_window1)
    );

    wire stage1_edge0 = stage1_window0[71] || stage1_window0[63] ||
                        stage1_window0[55] || stage1_window0[47] ||
                        stage1_window0[39] || stage1_window0[31] ||
                        stage1_window0[23] || stage1_window0[15] ||
                        stage1_window0[7];
    wire stage1_edge1 = stage1_window1[71] || stage1_window1[63] ||
                        stage1_window1[55] || stage1_window1[47] ||
                        stage1_window1[39] || stage1_window1[31] ||
                        stage1_window1[23] || stage1_window1[15] ||
                        stage1_window1[7];
    wire [7:0] stage1_sample0 = {
        stage1_edge0, stage1_window0[39], 4'b0, stage1_window0[33:32]
    };
    wire [7:0] stage1_sample1 = {
        stage1_edge1, stage1_window1[39], 4'b0, stage1_window1[33:32]
    };

    // Cascaded window generators require a bubble at each line boundary.  This
    // small skid FIFO preserves every pair while inserting that bubble.
    reg [15:0] stage1_fifo_data [0:7];
    reg        stage1_fifo_sof [0:7];
    reg        stage1_fifo_sol [0:7];
    reg [2:0]  stage1_fifo_wr_ptr;
    reg [2:0]  stage1_fifo_rd_ptr;
    reg [3:0]  stage1_fifo_count;
    reg        stage1_previous_valid;
    wire stage1_insert_gap = (stage1_fifo_count != 0) &&
                             stage1_fifo_sol[stage1_fifo_rd_ptr] &&
                             stage1_previous_valid;
    wire stage1_fifo_valid = (stage1_fifo_count != 0) && !stage1_insert_gap;
    wire stage1_fifo_out_sof = stage1_fifo_sof[stage1_fifo_rd_ptr];
    wire stage1_fifo_out_sol = stage1_fifo_sol[stage1_fifo_rd_ptr];
    wire [15:0] stage1_fifo_out_data = stage1_fifo_data[stage1_fifo_rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_fifo_wr_ptr <= 3'b0;
            stage1_fifo_rd_ptr <= 3'b0;
            stage1_fifo_count <= 4'b0;
            stage1_previous_valid <= 1'b0;
        end else begin
            if (stage1_valid) begin
                stage1_fifo_data[stage1_fifo_wr_ptr] <= {stage1_sample0, stage1_sample1};
                stage1_fifo_sof[stage1_fifo_wr_ptr] <= stage1_sof;
                stage1_fifo_sol[stage1_fifo_wr_ptr] <= stage1_sol;
                stage1_fifo_wr_ptr <= stage1_fifo_wr_ptr + 1'b1;
            end
            if (stage1_fifo_valid)
                stage1_fifo_rd_ptr <= stage1_fifo_rd_ptr + 1'b1;

            case ({stage1_valid, stage1_fifo_valid})
                2'b10: stage1_fifo_count <= stage1_fifo_count + 1'b1;
                2'b01: stage1_fifo_count <= stage1_fifo_count - 1'b1;
                default: stage1_fifo_count <= stage1_fifo_count;
            endcase
            stage1_previous_valid <= stage1_fifo_valid;
        end
    end

    wire [71:0] stage2_window0;
    wire [71:0] stage2_window1;
    window_3x3_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH),
        .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH)
    ) stage2_window_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(stage1_fifo_out_sof), .i_sol(stage1_fifo_out_sol),
        .i_valid(stage1_fifo_valid), .i_gray(stage1_fifo_out_data),
        .o_sof(o_sof), .o_sol(o_sol), .o_valid(o_valid),
        .o_border(), .o_window0(stage2_window0), .o_window1(stage2_window1)
    );

    wire edge0 = stage2_window0[71] || stage2_window0[63] ||
                 stage2_window0[55] || stage2_window0[47] ||
                 stage2_window0[39] || stage2_window0[31] ||
                 stage2_window0[23] || stage2_window0[15] ||
                 stage2_window0[7];
    wire edge1 = stage2_window1[71] || stage2_window1[63] ||
                 stage2_window1[55] || stage2_window1[47] ||
                 stage2_window1[39] || stage2_window1[31] ||
                 stage2_window1[23] || stage2_window1[15] ||
                 stage2_window1[7];

    assign o_binary = {edge0 ? 8'hff : 8'h00, edge1 ? 8'hff : 8'h00};
    assign o_direction = {stage2_window0[33:32], stage2_window1[33:32]};
    assign o_direction_valid = {stage2_window0[38], stage2_window1[38]};

endmodule
