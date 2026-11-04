module canny_2ppc #(
    parameter integer IMAGE_WIDTH     = 1920,
    parameter integer IMAGE_HEIGHT    = 1080,
    parameter integer PAIR_ADDR_WIDTH = 10,
    parameter integer ROW_COUNT_WIDTH = 11
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               i_sof,
    input  wire               i_sol,
    input  wire               i_valid,
    input  wire [1:0]         i_border,
    input  wire signed [11:0] i_gx0,
    input  wire signed [11:0] i_gy0,
    input  wire signed [11:0] i_gx1,
    input  wire signed [11:0] i_gy1,
    input  wire [21:0]        i_magnitude,
    input  wire [10:0]        i_high_threshold,
    input  wire [10:0]        i_low_threshold,

    output wire               o_sof,
    output wire               o_sol,
    output wire               o_valid,
    output wire [1:0]         o_border,
    output wire [15:0]        o_binary,
    output wire [3:0]         o_direction,
    output wire [1:0]         o_relaxed_candidate
);

    function [1:0] direction_bin;
        input signed [11:0] gx;
        input signed [11:0] gy;
        reg [10:0] abs_gx;
        reg [10:0] abs_gy;
        reg [13:0] gx_x5;
        reg [13:0] gy_x5;
        reg [13:0] gx_x12;
        reg [13:0] gy_x12;
        begin
            abs_gx = gx[11] ? (~gx[10:0] + 1'b1) : gx[10:0];
            abs_gy = gy[11] ? (~gy[10:0] + 1'b1) : gy[10:0];
            gx_x5 = ({3'b0, abs_gx} << 2) + {3'b0, abs_gx};
            gy_x5 = ({3'b0, abs_gy} << 2) + {3'b0, abs_gy};
            gx_x12 = ({3'b0, abs_gx} << 3) + ({3'b0, abs_gx} << 2);
            gy_x12 = ({3'b0, abs_gy} << 3) + ({3'b0, abs_gy} << 2);
            // 5/12 = 0.4167, close to tan(22.5 degrees).  This selects the
            // four output direction tags more accurately than 1/2. NMS itself
            // interpolates using the original derivatives, not these bins.
            if (gy_x12 <= gx_x5)
                direction_bin = 2'd0;
            else if (gx_x12 <= gy_x5)
                direction_bin = 2'd2;
            else if (gx[11] == gy[11])
                direction_bin = 2'd1;
            else
                direction_bin = 2'd3;
        end
    endfunction

    function [34:0] pack_gradient;
        input [10:0] magnitude;
        input signed [11:0] gx;
        input signed [11:0] gy;
        input [1:0] direction;
        reg [9:0] abs_gx;
        reg [9:0] abs_gy;
        begin
            // 3x3 Sobel on 8-bit pixels bounds both absolute derivatives at 1020.
            abs_gx = gx[11] ? (~gx[9:0] + 1'b1) : gx[9:0];
            abs_gy = gy[11] ? (~gy[9:0] + 1'b1) : gy[9:0];
            pack_gradient = {magnitude,
                             abs_gx >= abs_gy ? abs_gx : abs_gy,
                             abs_gx >= abs_gy ? abs_gy : abs_gx,
                             abs_gx >= abs_gy, gx[11] == gy[11], direction};
        end
    endfunction

    wire [10:0] magnitude0 = i_border[0] ? 11'b0 : i_magnitude[21:11];
    wire [10:0] magnitude1 = i_border[1] ? 11'b0 : i_magnitude[10:0];
    wire [1:0] direction0 = direction_bin(i_gx0, i_gy0);
    wire [1:0] direction1 = direction_bin(i_gx1, i_gy1);
    wire [69:0] packed_pair_next = {
        pack_gradient(magnitude0, i_gx0, i_gy0, direction0),
        pack_gradient(magnitude1, i_gx1, i_gy1, direction1)
    };
    reg packed_sof;
    reg packed_sol;
    reg packed_valid;
    reg [69:0] packed_pair;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            packed_sof <= 1'b0;
            packed_sol <= 1'b0;
            packed_valid <= 1'b0;
            packed_pair <= 70'b0;
        end else begin
            packed_sof <= i_sof;
            packed_sol <= i_sol;
            packed_valid <= i_valid;
            packed_pair <= packed_pair_next;
        end
    end

    wire magnitude_sof;
    wire magnitude_sol;
    wire magnitude_valid;
    wire [1:0] magnitude_border;
    wire [314:0] magnitude_window0;
    wire [314:0] magnitude_window1;
    window_3x3_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH),
        .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH),
        .PIXEL_WIDTH(35)
    ) magnitude_window_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(packed_sof), .i_sol(packed_sol),
        .i_valid(packed_valid), .i_gray(packed_pair),
        .o_sof(magnitude_sof), .o_sol(magnitude_sol), .o_valid(magnitude_valid),
        .o_border(magnitude_border),
        .o_window0(magnitude_window0), .o_window1(magnitude_window1)
    );

    wire [10:0] nms_magnitude0, nms_magnitude1;
    wire [1:0] center_direction0, center_direction1;
    interpolated_nms_pixel nms_lane0 (
        .clk(clk), .rst_n(rst_n), .i_window(magnitude_window0),
        .i_border(magnitude_border[0]),
        .o_magnitude(nms_magnitude0), .o_direction(center_direction0)
    );
    interpolated_nms_pixel nms_lane1 (
        .clk(clk), .rst_n(rst_n), .i_window(magnitude_window1),
        .i_border(magnitude_border[1]),
        .o_magnitude(nms_magnitude1), .o_direction(center_direction1)
    );
    // Match the three-clock interpolation pipeline, including blank line gaps.
    reg [2:0] nms_sof_pipe, nms_sol_pipe, nms_valid_pipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nms_sof_pipe <= 0; nms_sol_pipe <= 0; nms_valid_pipe <= 0;
        end else begin
            nms_sof_pipe <= {nms_sof_pipe[1:0], magnitude_sof};
            nms_sol_pipe <= {nms_sol_pipe[1:0], magnitude_sol};
            nms_valid_pipe <= {nms_valid_pipe[1:0], magnitude_valid};
        end
    end

    wire [10:0] relaxed_threshold = {2'b0, i_high_threshold[10:2]};
    // Keep the quantized gradient direction beside the strong/weak class so
    // it remains aligned through the hysteresis window.  Bits [7:6] encode
    // none/weak/strong; bits [1:0] carry the direction bin.
    wire [1:0] edge_class0 = (nms_magnitude0 > i_high_threshold) ? 2'b10 :
                             (nms_magnitude0 > i_low_threshold)  ? 2'b01 : 2'b00;
    wire [1:0] edge_class1 = (nms_magnitude1 > i_high_threshold) ? 2'b10 :
                             (nms_magnitude1 > i_low_threshold)  ? 2'b01 : 2'b00;
    wire relaxed_candidate0 = nms_magnitude0 > relaxed_threshold;
    wire relaxed_candidate1 = nms_magnitude1 > relaxed_threshold;
    wire [7:0] edge_sample0 = {edge_class0, relaxed_candidate0, 3'b0, center_direction0};
    wire [7:0] edge_sample1 = {edge_class1, relaxed_candidate1, 3'b0, center_direction1};

    // A cascaded window needs at least one idle clock between lines. The first
    // window's synthetic bottom-border line can otherwise follow the previous
    // line without a gap, so a small skid FIFO inserts that single bubble.
    reg [15:0] class_fifo_data [0:7];
    reg        class_fifo_sof [0:7];
    reg        class_fifo_sol [0:7];
    reg [2:0] class_fifo_wr_ptr;
    reg [2:0] class_fifo_rd_ptr;
    reg [3:0] class_fifo_count;
    reg       class_previous_valid;
    wire class_insert_gap = (class_fifo_count != 0) &&
                            class_fifo_sol[class_fifo_rd_ptr] && class_previous_valid;
    wire class_valid = (class_fifo_count != 0) && !class_insert_gap;
    wire class_sof = class_fifo_sof[class_fifo_rd_ptr];
    wire class_sol = class_fifo_sol[class_fifo_rd_ptr];
    wire [15:0] class_data = class_fifo_data[class_fifo_rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            class_fifo_wr_ptr <= 3'b0;
            class_fifo_rd_ptr <= 3'b0;
            class_fifo_count <= 4'b0;
            class_previous_valid <= 1'b0;
        end else begin
            if (nms_valid_pipe[2]) begin
                class_fifo_data[class_fifo_wr_ptr] <= {edge_sample0, edge_sample1};
                class_fifo_sof[class_fifo_wr_ptr] <= nms_sof_pipe[2];
                class_fifo_sol[class_fifo_wr_ptr] <= nms_sol_pipe[2];
                class_fifo_wr_ptr <= class_fifo_wr_ptr + 1'b1;
            end
            if (class_valid)
                class_fifo_rd_ptr <= class_fifo_rd_ptr + 1'b1;

            case ({nms_valid_pipe[2], class_valid})
                2'b10: class_fifo_count <= class_fifo_count + 1'b1;
                2'b01: class_fifo_count <= class_fifo_count - 1'b1;
                default: class_fifo_count <= class_fifo_count;
            endcase
            class_previous_valid <= class_valid;
        end
    end

    wire hysteresis_sof;
    wire hysteresis_sol;
    wire hysteresis_valid;
    wire [1:0] hysteresis_border;
    wire [71:0] hysteresis_window0;
    wire [71:0] hysteresis_window1;
    window_3x3_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH),
        .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH)
    ) hysteresis_window_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(class_sof), .i_sol(class_sol),
        .i_valid(class_valid), .i_gray(class_data),
        .o_sof(hysteresis_sof), .o_sol(hysteresis_sol), .o_valid(hysteresis_valid),
        .o_border(hysteresis_border),
        .o_window0(hysteresis_window0), .o_window1(hysteresis_window1)
    );

    wire center_strong0 = (hysteresis_window0[39:38] == 2'b10);
    wire center_strong1 = (hysteresis_window1[39:38] == 2'b10);
    wire center_weak0 = (hysteresis_window0[39:38] == 2'b01);
    wire center_weak1 = (hysteresis_window1[39:38] == 2'b01);
    wire neighbor_strong0 = (hysteresis_window0[71:70] == 2'b10) ||
                            (hysteresis_window0[63:62] == 2'b10) ||
                            (hysteresis_window0[55:54] == 2'b10) ||
                            (hysteresis_window0[47:46] == 2'b10) ||
                            (hysteresis_window0[31:30] == 2'b10) ||
                            (hysteresis_window0[23:22] == 2'b10) ||
                            (hysteresis_window0[15:14] == 2'b10) ||
                            (hysteresis_window0[7:6] == 2'b10);
    wire neighbor_strong1 = (hysteresis_window1[71:70] == 2'b10) ||
                            (hysteresis_window1[63:62] == 2'b10) ||
                            (hysteresis_window1[55:54] == 2'b10) ||
                            (hysteresis_window1[47:46] == 2'b10) ||
                            (hysteresis_window1[31:30] == 2'b10) ||
                            (hysteresis_window1[23:22] == 2'b10) ||
                            (hysteresis_window1[15:14] == 2'b10) ||
                            (hysteresis_window1[7:6] == 2'b10);
    wire edge0 = !hysteresis_border[0] &&
                 (center_strong0 || (center_weak0 && neighbor_strong0));
    wire edge1 = !hysteresis_border[1] &&
                 (center_strong1 || (center_weak1 && neighbor_strong1));

    assign o_sof = hysteresis_sof;
    assign o_sol = hysteresis_sol;
    assign o_valid = hysteresis_valid;
    assign o_border = hysteresis_border;
    assign o_binary = {edge0 ? 8'hff : 8'h00, edge1 ? 8'hff : 8'h00};
    assign o_direction = {
        edge0 ? hysteresis_window0[33:32] : 2'b0,
        edge1 ? hysteresis_window1[33:32] : 2'b0
    };
    assign o_relaxed_candidate = {
        !hysteresis_border[0] && hysteresis_window0[37],
        !hysteresis_border[1] && hysteresis_window1[37]
    };

endmodule
