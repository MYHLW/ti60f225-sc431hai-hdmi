module edge_post_process_2ppc #(
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
    input  wire [1:0]  i_relaxed_candidate,

    output wire        o_sof,
    output wire        o_sol,
    output wire        o_valid,
    output wire [1:0]  o_border,
    output wire [15:0] o_binary,
    output wire [15:0] o_core_binary,
    output wire [3:0]  o_direction
);

    // Each pixel is packed into one byte so the existing 2-PPC window can
    // carry the accepted edge, relaxed weak candidate and gradient direction
    // through one line-buffer pair. Bits 7/6 hold edge/candidate respectively.
    wire [7:0] packed0 = {|i_binary[15:8], i_relaxed_candidate[1],
                          4'b0, i_direction[3:2]};
    wire [7:0] packed1 = {|i_binary[7:0], i_relaxed_candidate[0],
                          4'b0, i_direction[1:0]};

    // A cascaded window requires one idle clock before a new line.  Canny may
    // emit its synthetic border line without that bubble, so buffer the stream
    // and insert exactly one gap at such line boundaries.
    reg [15:0] input_fifo_data [0:7];
    reg        input_fifo_sof  [0:7];
    reg        input_fifo_sol  [0:7];
    reg [2:0]  input_fifo_wr_ptr;
    reg [2:0]  input_fifo_rd_ptr;
    reg [3:0]  input_fifo_count;
    reg        previous_window_valid;

    wire insert_line_gap = (input_fifo_count != 0) &&
                           input_fifo_sol[input_fifo_rd_ptr] &&
                           previous_window_valid;
    wire window_input_valid = (input_fifo_count != 0) && !insert_line_gap;
    wire window_input_sof = input_fifo_sof[input_fifo_rd_ptr];
    wire window_input_sol = input_fifo_sol[input_fifo_rd_ptr];
    wire [15:0] window_input_data = input_fifo_data[input_fifo_rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_fifo_wr_ptr <= 3'b0;
            input_fifo_rd_ptr <= 3'b0;
            input_fifo_count <= 4'b0;
            previous_window_valid <= 1'b0;
        end else begin
            if (i_valid) begin
                input_fifo_data[input_fifo_wr_ptr] <= {packed0, packed1};
                input_fifo_sof[input_fifo_wr_ptr] <= i_sof;
                input_fifo_sol[input_fifo_wr_ptr] <= i_sol;
                input_fifo_wr_ptr <= input_fifo_wr_ptr + 1'b1;
            end
            if (window_input_valid)
                input_fifo_rd_ptr <= input_fifo_rd_ptr + 1'b1;

            case ({i_valid, window_input_valid})
                2'b10: input_fifo_count <= input_fifo_count + 1'b1;
                2'b01: input_fifo_count <= input_fifo_count - 1'b1;
                default: input_fifo_count <= input_fifo_count;
            endcase
            previous_window_valid <= window_input_valid;
        end
    end

    wire window_sof;
    wire window_sol;
    wire window_valid;
    wire [1:0] window_border;
    wire [71:0] window0;
    wire [71:0] window1;

    window_3x3_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH),
        .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH)
    ) edge_window (
        .clk(clk), .rst_n(rst_n),
        .i_sof(window_input_sof), .i_sol(window_input_sol),
        .i_valid(window_input_valid), .i_gray(window_input_data),
        .o_sof(window_sof), .o_sol(window_sol), .o_valid(window_valid),
        .o_border(window_border), .o_window0(window0), .o_window1(window1)
    );

    // Quantized directions are ordered 0, 45, 90 and 135 degrees.  Adjacent
    // bins are compatible; the bin two steps away is perpendicular.
    function direction_compatible;
        input [1:0] candidate_direction;
        input [1:0] seed_direction;
        begin
            direction_compatible =
                seed_direction != (candidate_direction ^ 2'b10);
        end
    endfunction

    // Result format is {edge, gradient_direction}. The baseline Canny result
    // acts as a seed. A relaxed H/4 NMS candidate is accepted only beside a
    // direction-compatible seed along the contour tangent. This adds one local
    // hysteresis hop without widening the edge along its gradient normal.
    // Remaining one-pixel gaps are bridged with a coarse orientation check.
    function [2:0] filtered_sample;
        input [71:0] window;
        input        border;
        reg nw, n, ne, w, center, center_relaxed, e, sw, s, se;
        reg [1:0] center_direction;
        reg [1:0] nw_direction, n_direction, ne_direction, w_direction;
        reg [1:0] e_direction, sw_direction, s_direction, se_direction;
        reg [3:0] neighbor_count;
        reg tangent_seed;
        begin
            nw = window[71];
            n  = window[63];
            ne = window[55];
            w  = window[47];
            center = window[39];
            center_relaxed = window[38];
            e  = window[31];
            sw = window[23];
            s  = window[15];
            se = window[7];
            nw_direction = window[65:64];
            n_direction  = window[57:56];
            ne_direction = window[49:48];
            w_direction  = window[41:40];
            center_direction = window[33:32];
            e_direction  = window[25:24];
            sw_direction = window[17:16];
            s_direction  = window[9:8];
            se_direction = window[1:0];
            neighbor_count = {3'b0, nw} + {3'b0, n} + {3'b0, ne} +
                             {3'b0, w}  + {3'b0, e} + {3'b0, sw} +
                             {3'b0, s}  + {3'b0, se};
            case (center_direction)
                2'd0: tangent_seed =
                    (n && direction_compatible(center_direction, n_direction)) ||
                    (s && direction_compatible(center_direction, s_direction));
                2'd1: tangent_seed =
                    (ne && direction_compatible(center_direction, ne_direction)) ||
                    (sw && direction_compatible(center_direction, sw_direction));
                2'd2: tangent_seed =
                    (w && direction_compatible(center_direction, w_direction)) ||
                    (e && direction_compatible(center_direction, e_direction));
                default: tangent_seed =
                    (nw && direction_compatible(center_direction, nw_direction)) ||
                    (se && direction_compatible(center_direction, se_direction));
            endcase

            filtered_sample = 3'b000;
            if (!border) begin
                if (center) begin
                    if (neighbor_count != 0)
                        filtered_sample = {1'b1, center_direction};
                end else if (center_relaxed && tangent_seed) begin
                    filtered_sample = {1'b1, center_direction};
                end else if (neighbor_count <= 4) begin
                    // At least one endpoint must have the ideal quantized
                    // direction; the other may fall into an adjacent bin.
                    if (w && e &&
                        ((w_direction == 2'd2) || (e_direction == 2'd2)) &&
                        (w_direction != 2'd0) && (e_direction != 2'd0))
                        filtered_sample = {1'b1, 2'd2};
                    else if (n && s &&
                             ((n_direction == 2'd0) || (s_direction == 2'd0)) &&
                             (n_direction != 2'd2) && (s_direction != 2'd2))
                        filtered_sample = {1'b1, 2'd0};
                    else if (nw && se &&
                             ((nw_direction == 2'd3) || (se_direction == 2'd3)))
                        filtered_sample = {1'b1, 2'd3};
                    else if (ne && sw &&
                             ((ne_direction == 2'd1) || (sw_direction == 2'd1)))
                        filtered_sample = {1'b1, 2'd1};
                end
            end
        end
    endfunction

    wire [2:0] result0 = filtered_sample(window0, window_border[0]);
    wire [2:0] result1 = filtered_sample(window1, window_border[1]);

    // Keep the aligned baseline Canny mask separate from the repaired mask.
    // The display can therefore mark original Canny pixels red and only the
    // weak-link/gap-repair additions green. Cross dilation is intentionally
    // absent so it cannot dominate this diagnostic comparison.
    wire original0 = !window_border[0] && window0[39];
    wire original1 = !window_border[1] && window1[39];

    assign o_sof = window_sof;
    assign o_sol = window_sol;
    assign o_valid = window_valid;
    assign o_border = window_border;
    assign o_binary = {
        result0[2] ? 8'hff : 8'h00,
        result1[2] ? 8'hff : 8'h00
    };
    assign o_core_binary = {
        original0 ? 8'hff : 8'h00,
        original1 ? 8'hff : 8'h00
    };
    assign o_direction = {
        result0[2] ? result0[1:0] : 2'b0,
        result1[2] ? result1[1:0] : 2'b0
    };

endmodule
