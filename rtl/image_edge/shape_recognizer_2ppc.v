module shape_recognizer_2ppc #(
    parameter integer IMAGE_WIDTH          = 1920,
    parameter integer IMAGE_HEIGHT         = 1080,
    parameter integer PAIR_ADDR_WIDTH      = 10,
    parameter integer ROW_COUNT_WIDTH      = 11,
    parameter integer MIN_SHAPE_WIDTH      = 48,
    parameter integer MIN_SHAPE_HEIGHT     = 48,
    parameter integer MIN_TOTAL_EDGES      = 96,
    parameter integer MIN_ROW_EDGES        = 2,
    parameter integer BOX_THICKNESS        = 3
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        i_canny_sof,
    input  wire        i_canny_sol,
    input  wire        i_canny_valid,
    input  wire [15:0] i_canny_binary,

    input  wire        i_raw_sof,
    input  wire        i_raw_sol,
    input  wire        i_raw_valid,
    input  wire [47:0] i_raw_rgb,

    output wire        o_overlay_valid,
    output wire [47:0] o_overlay_rgb,
    output reg         o_result_valid,
    output reg  [2:0]  o_shape_class,
    output reg  [10:0] o_bbox_x_min,
    output reg  [10:0] o_bbox_x_max,
    output reg  [10:0] o_bbox_y_min,
    output reg  [10:0] o_bbox_y_max
);

    localparam [2:0] SHAPE_NONE          = 3'd0;
    localparam [2:0] SHAPE_RECTANGLE     = 3'd1;
    localparam [2:0] SHAPE_TRIANGLE_UP   = 3'd2;
    localparam [2:0] SHAPE_CIRCLE        = 3'd3;
    localparam [2:0] SHAPE_UNKNOWN       = 3'd4;
    localparam [2:0] SHAPE_TRIANGLE_DOWN = 3'd5;

    localparam integer PAIRS_PER_LINE = IMAGE_WIDTH / 2;
    localparam integer SUMMARY_WIDTH = 35;

    wire edge0 = |i_canny_binary[15:8];
    wire edge1 = |i_canny_binary[7:0];
    wire [1:0] pair_edge_count = {1'b0, edge0} + {1'b0, edge1};

    reg [PAIR_ADDR_WIDTH-1:0] canny_next_pair;
    reg [ROW_COUNT_WIDTH-1:0] canny_next_row;
    wire canny_line_start = i_canny_sof || i_canny_sol;
    wire [PAIR_ADDR_WIDTH-1:0] canny_pair = canny_line_start ?
        {PAIR_ADDR_WIDTH{1'b0}} : canny_next_pair;
    wire [ROW_COUNT_WIDTH-1:0] canny_row = i_canny_sof ?
        {ROW_COUNT_WIDTH{1'b0}} : canny_next_row;
    wire [10:0] canny_x0 = {canny_pair, 1'b0};
    wire [10:0] canny_x1 = canny_x0 + 1'b1;

    reg [11:0] row_edge_count;
    reg [10:0] row_x_min;
    reg [10:0] row_x_max;
    wire [11:0] row_count_base = canny_line_start ? 12'b0 : row_edge_count;
    wire [10:0] row_min_base = canny_line_start ? 11'h7ff : row_x_min;
    wire [10:0] row_max_base = canny_line_start ? 11'b0 : row_x_max;
    wire [11:0] row_count_next = row_count_base + pair_edge_count;
    wire [10:0] row_min_after0 = (edge0 && (canny_x0 < row_min_base)) ? canny_x0 : row_min_base;
    wire [10:0] row_min_next = (edge1 && (canny_x1 < row_min_after0)) ? canny_x1 : row_min_after0;
    wire [10:0] row_max_after0 = (edge0 && (canny_x0 > row_max_base)) ? canny_x0 : row_max_base;
    wire [10:0] row_max_next = (edge1 && (canny_x1 > row_max_after0)) ? canny_x1 : row_max_after0;
    wire canny_last_pair = (canny_pair == PAIRS_PER_LINE - 1);
    wire canny_last_row = (canny_row == IMAGE_HEIGHT - 1);
    wire summary_write = i_canny_valid && canny_last_pair;
    wire [SUMMARY_WIDTH-1:0] summary_write_data = {
        (row_count_next != 0), row_count_next, row_min_next, row_max_next
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            canny_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
            canny_next_row <= {ROW_COUNT_WIDTH{1'b0}};
            row_edge_count <= 12'b0;
            row_x_min <= 11'h7ff;
            row_x_max <= 11'b0;
        end else if (i_canny_valid) begin
            row_edge_count <= row_count_next;
            row_x_min <= row_min_next;
            row_x_max <= row_max_next;
            if (canny_last_pair) begin
                canny_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
                canny_next_row <= canny_row + 1'b1;
            end else begin
                canny_next_pair <= canny_pair + 1'b1;
                canny_next_row <= canny_row;
            end
        end
    end

    localparam [3:0] SCAN_IDLE     = 4'd0;
    localparam [3:0] SCAN_P1_READ  = 4'd1;
    localparam [3:0] SCAN_P1_USE   = 4'd2;
    localparam [3:0] SCAN_PREPARE  = 4'd3;
    localparam [3:0] SCAN_P2_READ  = 4'd4;
    localparam [3:0] SCAN_P2_USE   = 4'd5;
    localparam [3:0] SCAN_CLASSIFY = 4'd6;

    reg [3:0] scan_state;
    reg [ROW_COUNT_WIDTH-1:0] scan_row;
    wire [SUMMARY_WIDTH-1:0] summary_read_data;
    wire summary_row_valid = summary_read_data[34];
    wire [11:0] summary_row_count = summary_read_data[33:22];
    wire [10:0] summary_row_min = summary_read_data[21:11];
    wire [10:0] summary_row_max = summary_read_data[10:0];
    wire summary_row_active = summary_row_valid && (summary_row_count >= MIN_ROW_EDGES);
    wire [11:0] summary_row_span = {1'b0, summary_row_max} -
                                   {1'b0, summary_row_min} + 1'b1;

    true_dual_port_ram #(
        .DATA_WIDTH(SUMMARY_WIDTH),
        .ADDR_WIDTH(ROW_COUNT_WIDTH),
        .WRITE_MODE_1("READ_FIRST"),
        .WRITE_MODE_2("READ_FIRST"),
        .OUTPUT_REG_1("FALSE"),
        .OUTPUT_REG_2("FALSE"),
        .RAM_INIT_FILE("")
    ) row_summary_ram (
        .we1(summary_write), .we2(1'b0),
        .clka(clk), .clkb(clk),
        .din1(summary_write_data), .din2({SUMMARY_WIDTH{1'b0}}),
        .addr1(canny_row), .addr2(scan_row),
        .dout1(), .dout2(summary_read_data)
    );

    reg p1_found;
    reg [10:0] p1_x_min;
    reg [10:0] p1_x_max;
    reg [10:0] p1_y_min;
    reg [10:0] p1_y_max;
    reg [23:0] p1_total_edges;
    reg [11:0] p1_active_rows;
    reg [10:0] sample_y0;
    reg [10:0] sample_y1;
    reg [10:0] sample_y2;
    reg [10:0] sample_y3;
    reg [10:0] sample_y4;
    reg [10:0] sample_band;
    reg [11:0] sample_span0;
    reg [11:0] sample_span1;
    reg [11:0] sample_span2;
    reg [11:0] sample_span3;
    reg [11:0] sample_span4;
    reg [4:0] sample_valid;

    wire [11:0] p1_bbox_width = {1'b0, p1_x_max} - {1'b0, p1_x_min} + 1'b1;
    wire [11:0] p1_bbox_height = {1'b0, p1_y_max} - {1'b0, p1_y_min} + 1'b1;
    wire [14:0] p1_height_times3 = {3'b0, p1_bbox_height} +
                                         ({3'b0, p1_bbox_height} << 1);
    wire [14:0] p1_height_times7 = {3'b0, p1_bbox_height} +
                                         ({3'b0, p1_bbox_height} << 1) +
                                         ({3'b0, p1_bbox_height} << 2);
    wire p1_candidate_valid = p1_found &&
                              (p1_bbox_width >= MIN_SHAPE_WIDTH) &&
                              (p1_bbox_height >= MIN_SHAPE_HEIGHT) &&
                              (p1_total_edges >= MIN_TOTAL_EDGES) &&
                              ((p1_active_rows << 1) >= p1_bbox_height);

    wire [11:0] scan_row_11 = scan_row;
    wire sample_hit0 = summary_row_active &&
                       ({1'b0, scan_row_11} + {1'b0, sample_band} >= {1'b0, sample_y0}) &&
                       ({1'b0, scan_row_11} <= {1'b0, sample_y0} + {1'b0, sample_band});
    wire sample_hit1 = summary_row_active &&
                       ({1'b0, scan_row_11} + {1'b0, sample_band} >= {1'b0, sample_y1}) &&
                       ({1'b0, scan_row_11} <= {1'b0, sample_y1} + {1'b0, sample_band});
    wire sample_hit2 = summary_row_active &&
                       ({1'b0, scan_row_11} + {1'b0, sample_band} >= {1'b0, sample_y2}) &&
                       ({1'b0, scan_row_11} <= {1'b0, sample_y2} + {1'b0, sample_band});
    wire sample_hit3 = summary_row_active &&
                       ({1'b0, scan_row_11} + {1'b0, sample_band} >= {1'b0, sample_y3}) &&
                       ({1'b0, scan_row_11} <= {1'b0, sample_y3} + {1'b0, sample_band});
    wire sample_hit4 = summary_row_active &&
                       ({1'b0, scan_row_11} + {1'b0, sample_band} >= {1'b0, sample_y4}) &&
                       ({1'b0, scan_row_11} <= {1'b0, sample_y4} + {1'b0, sample_band});

    wire [12:0] width_ext = {1'b0, p1_bbox_width};
    wire [12:0] rect_tolerance = {1'b0, (p1_bbox_width >> 3)} + 13'd2;
    wire [12:0] profile_step = {1'b0, (p1_bbox_width >> 5)} + 13'd1;
    wire [12:0] symmetry_tolerance = rect_tolerance;
    wire [12:0] span0_ext = {1'b0, sample_span0};
    wire [12:0] span1_ext = {1'b0, sample_span1};
    wire [12:0] span2_ext = {1'b0, sample_span2};
    wire [12:0] span3_ext = {1'b0, sample_span3};
    wire [12:0] span4_ext = {1'b0, sample_span4};
    wire [12:0] dim_max = (p1_bbox_width >= p1_bbox_height) ?
                          {1'b0, p1_bbox_width} : {1'b0, p1_bbox_height};
    wire [12:0] dim_min = (p1_bbox_width >= p1_bbox_height) ?
                          {1'b0, p1_bbox_height} : {1'b0, p1_bbox_width};
    wire [12:0] dim_difference = dim_max - dim_min;
    wire [12:0] span04_difference = (span0_ext >= span4_ext) ?
                                    (span0_ext - span4_ext) : (span4_ext - span0_ext);
    wire [12:0] span13_difference = (span1_ext >= span3_ext) ?
                                    (span1_ext - span3_ext) : (span3_ext - span1_ext);

    wire samples_complete = &sample_valid;
    wire enough_contour = ({1'b0, p1_total_edges} << 1) >=
                          ({13'b0, p1_bbox_width} + {13'b0, p1_bbox_height});
    wire rectangle_profile =
        (span0_ext + rect_tolerance >= width_ext) &&
        (span1_ext + rect_tolerance >= width_ext) &&
        (span2_ext + rect_tolerance >= width_ext) &&
        (span3_ext + rect_tolerance >= width_ext) &&
        (span4_ext + rect_tolerance >= width_ext);
    wire triangle_up_profile =
        (span1_ext >= span0_ext + profile_step) &&
        (span2_ext >= span1_ext + profile_step) &&
        (span3_ext >= span2_ext + profile_step) &&
        (span4_ext >= span3_ext + profile_step) &&
        (span4_ext >= span0_ext + (width_ext >> 1)) &&
        (span0_ext <= (width_ext >> 1) + 13'd2) &&
        (span4_ext + (width_ext >> 2) + 13'd2 >= width_ext);
    wire triangle_down_profile =
        (span0_ext >= span1_ext + profile_step) &&
        (span1_ext >= span2_ext + profile_step) &&
        (span2_ext >= span3_ext + profile_step) &&
        (span3_ext >= span4_ext + profile_step) &&
        (span0_ext >= span4_ext + (width_ext >> 1)) &&
        (span4_ext <= (width_ext >> 1) + 13'd2) &&
        (span0_ext + (width_ext >> 2) + 13'd2 >= width_ext);
    wire circle_profile =
        (dim_difference <= (dim_max >> 2) + 13'd2) &&
        (span0_ext + (width_ext >> 1) + 13'd2 >= width_ext) &&
        (span4_ext + (width_ext >> 1) + 13'd2 >= width_ext) &&
        (span1_ext + (width_ext >> 2) + 13'd2 >= width_ext) &&
        (span3_ext + (width_ext >> 2) + 13'd2 >= width_ext) &&
        (span2_ext + (width_ext >> 3) + 13'd2 >= width_ext) &&
        (span1_ext >= span0_ext + profile_step) &&
        (span2_ext >= span1_ext + profile_step) &&
        (span2_ext >= span3_ext + profile_step) &&
        (span3_ext >= span4_ext + profile_step) &&
        (span04_difference <= symmetry_tolerance) &&
        (span13_difference <= symmetry_tolerance);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_state <= SCAN_IDLE;
            scan_row <= {ROW_COUNT_WIDTH{1'b0}};
            p1_found <= 1'b0;
            p1_x_min <= 11'h7ff;
            p1_x_max <= 11'b0;
            p1_y_min <= 11'b0;
            p1_y_max <= 11'b0;
            p1_total_edges <= 24'b0;
            p1_active_rows <= 12'b0;
            sample_y0 <= 11'b0;
            sample_y1 <= 11'b0;
            sample_y2 <= 11'b0;
            sample_y3 <= 11'b0;
            sample_y4 <= 11'b0;
            sample_band <= 11'd1;
            sample_span0 <= 12'b0;
            sample_span1 <= 12'b0;
            sample_span2 <= 12'b0;
            sample_span3 <= 12'b0;
            sample_span4 <= 12'b0;
            sample_valid <= 5'b0;
            o_result_valid <= 1'b0;
            o_shape_class <= SHAPE_NONE;
            o_bbox_x_min <= 11'b0;
            o_bbox_x_max <= 11'b0;
            o_bbox_y_min <= 11'b0;
            o_bbox_y_max <= 11'b0;
        end else begin
            case (scan_state)
                SCAN_IDLE: begin
                    if (summary_write && canny_last_row) begin
                        scan_row <= {ROW_COUNT_WIDTH{1'b0}};
                        p1_found <= 1'b0;
                        p1_x_min <= 11'h7ff;
                        p1_x_max <= 11'b0;
                        p1_y_min <= 11'b0;
                        p1_y_max <= 11'b0;
                        p1_total_edges <= 24'b0;
                        p1_active_rows <= 12'b0;
                        scan_state <= SCAN_P1_READ;
                    end
                end

                SCAN_P1_READ:
                    scan_state <= SCAN_P1_USE;

                SCAN_P1_USE: begin
                    if (summary_row_active) begin
                        if (!p1_found) begin
                            p1_found <= 1'b1;
                            p1_x_min <= summary_row_min;
                            p1_x_max <= summary_row_max;
                            p1_y_min <= scan_row;
                            p1_y_max <= scan_row;
                        end else begin
                            if (summary_row_min < p1_x_min)
                                p1_x_min <= summary_row_min;
                            if (summary_row_max > p1_x_max)
                                p1_x_max <= summary_row_max;
                            p1_y_max <= scan_row;
                        end
                        p1_total_edges <= p1_total_edges + summary_row_count;
                        p1_active_rows <= p1_active_rows + 1'b1;
                    end

                    if (scan_row == IMAGE_HEIGHT - 1) begin
                        scan_state <= SCAN_PREPARE;
                    end else begin
                        scan_row <= scan_row + 1'b1;
                        scan_state <= SCAN_P1_READ;
                    end
                end

                SCAN_PREPARE: begin
                    if (!p1_candidate_valid) begin
                        o_result_valid <= 1'b0;
                        o_shape_class <= SHAPE_NONE;
                        scan_state <= SCAN_IDLE;
                    end else begin
                        sample_y0 <= p1_y_min + (p1_bbox_height >> 3);
                        sample_y1 <= p1_y_min + (p1_bbox_height >> 2);
                        sample_y2 <= p1_y_min + (p1_bbox_height >> 1);
                        sample_y3 <= p1_y_min + (p1_height_times3 >> 2);
                        sample_y4 <= p1_y_min + (p1_height_times7 >> 3);
                        sample_band <= ((p1_bbox_height >> 5) == 0) ?
                                       11'd1 : (p1_bbox_height >> 5);
                        sample_span0 <= 12'b0;
                        sample_span1 <= 12'b0;
                        sample_span2 <= 12'b0;
                        sample_span3 <= 12'b0;
                        sample_span4 <= 12'b0;
                        sample_valid <= 5'b0;
                        scan_row <= p1_y_min;
                        scan_state <= SCAN_P2_READ;
                    end
                end

                SCAN_P2_READ:
                    scan_state <= SCAN_P2_USE;

                SCAN_P2_USE: begin
                    if (sample_hit0) begin
                        sample_valid[0] <= 1'b1;
                        if (summary_row_span > sample_span0)
                            sample_span0 <= summary_row_span;
                    end
                    if (sample_hit1) begin
                        sample_valid[1] <= 1'b1;
                        if (summary_row_span > sample_span1)
                            sample_span1 <= summary_row_span;
                    end
                    if (sample_hit2) begin
                        sample_valid[2] <= 1'b1;
                        if (summary_row_span > sample_span2)
                            sample_span2 <= summary_row_span;
                    end
                    if (sample_hit3) begin
                        sample_valid[3] <= 1'b1;
                        if (summary_row_span > sample_span3)
                            sample_span3 <= summary_row_span;
                    end
                    if (sample_hit4) begin
                        sample_valid[4] <= 1'b1;
                        if (summary_row_span > sample_span4)
                            sample_span4 <= summary_row_span;
                    end

                    if (scan_row == p1_y_max) begin
                        scan_state <= SCAN_CLASSIFY;
                    end else begin
                        scan_row <= scan_row + 1'b1;
                        scan_state <= SCAN_P2_READ;
                    end
                end

                SCAN_CLASSIFY: begin
                    o_result_valid <= 1'b1;
                    o_bbox_x_min <= p1_x_min;
                    o_bbox_x_max <= p1_x_max;
                    o_bbox_y_min <= p1_y_min;
                    o_bbox_y_max <= p1_y_max;
                    if (!samples_complete || !enough_contour)
                        o_shape_class <= SHAPE_UNKNOWN;
                    else if (rectangle_profile)
                        o_shape_class <= SHAPE_RECTANGLE;
                    else if (triangle_up_profile)
                        o_shape_class <= SHAPE_TRIANGLE_UP;
                    else if (triangle_down_profile)
                        o_shape_class <= SHAPE_TRIANGLE_DOWN;
                    else if (circle_profile)
                        o_shape_class <= SHAPE_CIRCLE;
                    else
                        o_shape_class <= SHAPE_UNKNOWN;
                    scan_state <= SCAN_IDLE;
                end

                default:
                    scan_state <= SCAN_IDLE;
            endcase
        end
    end

    reg [PAIR_ADDR_WIDTH-1:0] raw_next_pair;
    reg [ROW_COUNT_WIDTH-1:0] raw_next_row;
    wire raw_line_start = i_raw_sof || i_raw_sol;
    wire [PAIR_ADDR_WIDTH-1:0] raw_pair = raw_line_start ?
        {PAIR_ADDR_WIDTH{1'b0}} : raw_next_pair;
    wire [ROW_COUNT_WIDTH-1:0] raw_row = i_raw_sof ?
        {ROW_COUNT_WIDTH{1'b0}} : raw_next_row;
    wire [10:0] raw_x0 = {raw_pair, 1'b0};
    wire [10:0] raw_x1 = raw_x0 + 1'b1;
    wire [10:0] raw_y = raw_row;

    reg display_result_valid;
    reg [2:0] display_shape_class;
    reg [10:0] display_x_min;
    reg [10:0] display_x_max;
    reg [10:0] display_y_min;
    reg [10:0] display_y_max;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
            raw_next_row <= {ROW_COUNT_WIDTH{1'b0}};
            display_result_valid <= 1'b0;
            display_shape_class <= SHAPE_NONE;
            display_x_min <= 11'b0;
            display_x_max <= 11'b0;
            display_y_min <= 11'b0;
            display_y_max <= 11'b0;
        end else begin
            if (i_raw_sof) begin
                display_result_valid <= o_result_valid;
                display_shape_class <= o_shape_class;
                display_x_min <= o_bbox_x_min;
                display_x_max <= o_bbox_x_max;
                display_y_min <= o_bbox_y_min;
                display_y_max <= o_bbox_y_max;
            end

            if (i_raw_valid) begin
                if (raw_pair == PAIRS_PER_LINE - 1) begin
                    raw_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
                    raw_next_row <= raw_row + 1'b1;
                end else begin
                    raw_next_pair <= raw_pair + 1'b1;
                    raw_next_row <= raw_row;
                end
            end
        end
    end

    wire active_result_valid = i_raw_sof ? o_result_valid : display_result_valid;
    wire [2:0] active_shape_class = i_raw_sof ? o_shape_class : display_shape_class;
    wire [10:0] active_x_min = i_raw_sof ? o_bbox_x_min : display_x_min;
    wire [10:0] active_x_max = i_raw_sof ? o_bbox_x_max : display_x_max;
    wire [10:0] active_y_min = i_raw_sof ? o_bbox_y_min : display_y_min;
    wire [10:0] active_y_max = i_raw_sof ? o_bbox_y_max : display_y_max;

    wire raw_y_inside = (raw_y >= active_y_min) && (raw_y <= active_y_max);
    wire horizontal_box = raw_y_inside &&
                          ((raw_y < active_y_min + BOX_THICKNESS) ||
                           (raw_y + BOX_THICKNESS > active_y_max));
    wire raw_x0_inside = (raw_x0 >= active_x_min) && (raw_x0 <= active_x_max);
    wire raw_x1_inside = (raw_x1 >= active_x_min) && (raw_x1 <= active_x_max);
    wire pixel0_box = active_result_valid && raw_y_inside && raw_x0_inside &&
                      (horizontal_box || (raw_x0 < active_x_min + BOX_THICKNESS) ||
                       (raw_x0 + BOX_THICKNESS > active_x_max));
    wire pixel1_box = active_result_valid && raw_y_inside && raw_x1_inside &&
                      (horizontal_box || (raw_x1 < active_x_min + BOX_THICKNESS) ||
                       (raw_x1 + BOX_THICKNESS > active_x_max));

    reg [23:0] shape_color;
    always @(*) begin
        case (active_shape_class)
            SHAPE_RECTANGLE: shape_color = 24'h0000ff; // screen red
            SHAPE_TRIANGLE_UP,
            SHAPE_TRIANGLE_DOWN: shape_color = 24'h00ff00; // screen green
            SHAPE_CIRCLE:    shape_color = 24'hff0000; // screen blue
            default:         shape_color = 24'h00ffff; // screen yellow
        endcase
    end

    assign o_overlay_valid = i_raw_valid;
    assign o_overlay_rgb = {
        pixel0_box ? shape_color : i_raw_rgb[47:24],
        pixel1_box ? shape_color : i_raw_rgb[23:0]
    };

endmodule
