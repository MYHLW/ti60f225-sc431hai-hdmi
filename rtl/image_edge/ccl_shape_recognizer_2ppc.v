module ccl_shape_recognizer_2ppc #(
    parameter integer IMAGE_WIDTH          = 1920,
    parameter integer IMAGE_HEIGHT         = 1080,
    parameter integer PAIR_ADDR_WIDTH      = 10,
    parameter integer ROW_COUNT_WIDTH      = 11,
    parameter integer MAX_RUNS_PER_ROW     = 24,
    parameter integer MAX_LABELS           = 12,
    parameter integer MAX_OBJECTS          = 4,
    parameter integer MIN_OBJECT_WIDTH     = 48,
    parameter integer MIN_OBJECT_HEIGHT    = 48,
    parameter integer MIN_OBJECT_EDGES     = 96,
    parameter integer BOX_THICKNESS        = 3,
    parameter integer RUN_CONNECT_MARGIN   = 2,
    parameter integer MERGE_MARGIN         = 6,
    parameter integer BORDER_REJECT_MARGIN = 4,
    parameter integer TRACK_ENABLE = 0,
    parameter integer ROI_X_MIN = IMAGE_WIDTH / 4,
    parameter integer ROI_X_MAX = IMAGE_WIDTH * 3 / 4 - 1,
    parameter integer ROI_Y_MIN = IMAGE_HEIGHT / 4,
    parameter integer ROI_Y_MAX = IMAGE_HEIGHT * 3 / 4 - 1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_roi_enable,
    input  wire        i_track_clear,

    input  wire        i_canny_sof,
    input  wire        i_canny_sol,
    input  wire        i_canny_valid,
    input  wire [15:0] i_canny_binary,
    input  wire [3:0]  i_edge_direction,
    input  wire [1:0]  i_direction_valid,

    input  wire        i_raw_sof,
    input  wire        i_raw_sol,
    input  wire        i_raw_valid,
    input  wire [47:0] i_raw_rgb,

    output wire        o_overlay_valid,
    output reg  [47:0] o_overlay_rgb,
    output reg  [5:0]  o_overlay_tag,
    output wire [3:0]  o_object_count,
    output wire [4:0]  o_shape_mask,
    output wire        o_tracks_stale,
    output wire        o_ccl_overflow
);

    localparam [2:0] SHAPE_RECTANGLE = 3'd1;
    localparam [2:0] SHAPE_TRIANGLE  = 3'd2;
    localparam [2:0] SHAPE_CIRCLE    = 3'd3;
    localparam [2:0] SHAPE_ELLIPSE   = 3'd4;
    localparam [2:0] SHAPE_TRAPEZOID = 3'd5;
    localparam [2:0] SHAPE_UNKNOWN   = 3'd7;

    localparam integer PAIRS_PER_LINE = IMAGE_WIDTH / 2;
    localparam integer LABEL_WIDTH = (MAX_LABELS <= 2) ? 1 : $clog2(MAX_LABELS);
    localparam integer RUN_COUNT_WIDTH = (MAX_RUNS_PER_ROW <= 1) ? 1 :
                                         $clog2(MAX_RUNS_PER_ROW + 1);
    localparam integer OBJECT_INDEX_WIDTH = (MAX_OBJECTS <= 2) ? 1 :
                                            $clog2(MAX_OBJECTS);

    localparam [3:0] ST_WAIT_ROW   = 4'd0;
    localparam [3:0] ST_PROC_INIT  = 4'd1;
    localparam [3:0] ST_RUN_INIT   = 4'd2;
    localparam [3:0] ST_RUN_SCAN   = 4'd3;
    localparam [3:0] ST_RUN_APPLY  = 4'd4;
    localparam [3:0] ST_ROW_ACCUM  = 4'd5;
    localparam [3:0] ST_FINALIZE   = 4'd6;
    localparam [3:0] ST_SWAP       = 4'd7;
    localparam [3:0] ST_PUBLISH    = 4'd8;
    localparam [3:0] ST_RUN_FETCH  = 4'd9;
    localparam [3:0] ST_SWAP_FETCH = 4'd10;
    localparam integer RUN_ADDR_WIDTH = (MAX_RUNS_PER_ROW<=2) ? 1 : $clog2(MAX_RUNS_PER_ROW);

    // -------------------------------------------------------------------------
    // Run capture.  Two banks allow row N+1 to be captured while row N is
    // labelled.  Processing therefore has a complete 1100-clock video line,
    // rather than only the 140-clock horizontal blanking interval.
    // -------------------------------------------------------------------------
    reg [PAIR_ADDR_WIDTH-1:0] canny_next_pair;
    reg [ROW_COUNT_WIDTH-1:0] canny_next_row;
    wire canny_line_start = i_canny_sof || i_canny_sol;
    wire [PAIR_ADDR_WIDTH-1:0] canny_pair = canny_line_start ?
        {PAIR_ADDR_WIDTH{1'b0}} : canny_next_pair;
    wire [ROW_COUNT_WIDTH-1:0] canny_row = i_canny_sof ?
        {ROW_COUNT_WIDTH{1'b0}} : canny_next_row;
    wire [11:0] canny_x0 = {canny_pair, 1'b0};
    wire [11:0] canny_x1 = canny_x0 + 1'b1;
    wire canny_last_pair = (canny_pair == PAIRS_PER_LINE - 1);
    wire canny_last_row = (canny_row == IMAGE_HEIGHT - 1);
    reg roi_active;
    wire capture_roi = i_canny_sof ? (i_roi_enable === 1'b1) : roi_active;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) roi_active <= 1'b0;
        else if (i_canny_sof) roi_active <= (i_roi_enable === 1'b1);
    wire roi_y_inside = canny_row >= ROI_Y_MIN && canny_row <= ROI_Y_MAX;
    wire edge0 = (|i_canny_binary[15:8]) && (!capture_roi ||
        (roi_y_inside && canny_x0 >= ROI_X_MIN && canny_x0 <= ROI_X_MAX));
    wire edge1 = (|i_canny_binary[7:0]) && (!capture_roi ||
        (roi_y_inside && canny_x1 >= ROI_X_MIN && canny_x1 <= ROI_X_MAX));
    wire [1:0] direction0 = i_edge_direction[3:2];
    wire [1:0] direction1 = i_edge_direction[1:0];

    reg run_open;
    reg [11:0] run_start;
    reg [11:0] run_dir0_count;
    reg [11:0] run_dir1_count;
    reg [11:0] run_dir2_count;
    reg [11:0] run_dir3_count;
    wire base_run_open = canny_line_start ? 1'b0 : run_open;
    wire [11:0] base_run_start = canny_line_start ? 12'b0 : run_start;

    reg parsed_run_open;
    reg [11:0] parsed_run_start;
    reg [11:0] parsed_dir0_count;
    reg [11:0] parsed_dir1_count;
    reg [11:0] parsed_dir2_count;
    reg [11:0] parsed_dir3_count;
    reg close0_valid;
    reg close1_valid;
    reg [11:0] close0_start;
    reg [11:0] close0_end;
    reg [11:0] close1_start;
    reg [11:0] close1_end;
    reg [11:0] close0_dir0;
    reg [11:0] close0_dir1;
    reg [11:0] close0_dir2;
    reg [11:0] close0_dir3;
    reg [11:0] close1_dir0;
    reg [11:0] close1_dir1;
    reg [11:0] close1_dir2;
    reg [11:0] close1_dir3;
    reg lane_open;
    reg [11:0] lane_start;
    reg [11:0] lane_dir0;
    reg [11:0] lane_dir1;
    reg [11:0] lane_dir2;
    reg [11:0] lane_dir3;

    always @(*) begin
        close0_valid = 1'b0;
        close1_valid = 1'b0;
        close0_start = 12'b0;
        close0_end = 12'b0;
        close1_start = 12'b0;
        close1_end = 12'b0;
        close0_dir0 = 12'b0;
        close0_dir1 = 12'b0;
        close0_dir2 = 12'b0;
        close0_dir3 = 12'b0;
        close1_dir0 = 12'b0;
        close1_dir1 = 12'b0;
        close1_dir2 = 12'b0;
        close1_dir3 = 12'b0;
        lane_open = base_run_open;
        lane_start = base_run_start;
        lane_dir0 = canny_line_start ? 12'b0 : run_dir0_count;
        lane_dir1 = canny_line_start ? 12'b0 : run_dir1_count;
        lane_dir2 = canny_line_start ? 12'b0 : run_dir2_count;
        lane_dir3 = canny_line_start ? 12'b0 : run_dir3_count;

        if (edge0) begin
            if (!lane_open) begin
                lane_start = canny_x0;
                lane_dir0 = 12'b0;
                lane_dir1 = 12'b0;
                lane_dir2 = 12'b0;
                lane_dir3 = 12'b0;
            end
            lane_open = 1'b1;
            if (i_direction_valid[1]) begin
                case (direction0)
                    2'd0: lane_dir0 = lane_dir0 + 1'b1;
                    2'd1: lane_dir1 = lane_dir1 + 1'b1;
                    2'd2: lane_dir2 = lane_dir2 + 1'b1;
                    default: lane_dir3 = lane_dir3 + 1'b1;
                endcase
            end
        end else if (lane_open) begin
            close0_valid = 1'b1;
            close0_start = lane_start;
            close0_end = canny_x0 - 1'b1;
            close0_dir0 = lane_dir0;
            close0_dir1 = lane_dir1;
            close0_dir2 = lane_dir2;
            close0_dir3 = lane_dir3;
            lane_open = 1'b0;
        end

        if (edge1) begin
            if (!lane_open) begin
                lane_start = canny_x1;
                lane_dir0 = 12'b0;
                lane_dir1 = 12'b0;
                lane_dir2 = 12'b0;
                lane_dir3 = 12'b0;
            end
            lane_open = 1'b1;
            if (i_direction_valid[0]) begin
                case (direction1)
                    2'd0: lane_dir0 = lane_dir0 + 1'b1;
                    2'd1: lane_dir1 = lane_dir1 + 1'b1;
                    2'd2: lane_dir2 = lane_dir2 + 1'b1;
                    default: lane_dir3 = lane_dir3 + 1'b1;
                endcase
            end
        end else if (lane_open) begin
            if (!close0_valid) begin
                close0_valid = 1'b1;
                close0_start = lane_start;
                close0_end = canny_x0;
                close0_dir0 = lane_dir0;
                close0_dir1 = lane_dir1;
                close0_dir2 = lane_dir2;
                close0_dir3 = lane_dir3;
            end else begin
                close1_valid = 1'b1;
                close1_start = lane_start;
                close1_end = canny_x0;
                close1_dir0 = lane_dir0;
                close1_dir1 = lane_dir1;
                close1_dir2 = lane_dir2;
                close1_dir3 = lane_dir3;
            end
            lane_open = 1'b0;
        end

        if (canny_last_pair && lane_open) begin
            if (!close0_valid) begin
                close0_valid = 1'b1;
                close0_start = lane_start;
                close0_end = canny_x1;
                close0_dir0 = lane_dir0;
                close0_dir1 = lane_dir1;
                close0_dir2 = lane_dir2;
                close0_dir3 = lane_dir3;
            end else begin
                close1_valid = 1'b1;
                close1_start = lane_start;
                close1_end = canny_x1;
                close1_dir0 = lane_dir0;
                close1_dir1 = lane_dir1;
                close1_dir2 = lane_dir2;
                close1_dir3 = lane_dir3;
            end
            lane_open = 1'b0;
        end

        parsed_run_open = lane_open;
        parsed_run_start = lane_start;
        parsed_dir0_count = lane_dir0;
        parsed_dir1_count = lane_dir1;
        parsed_dir2_count = lane_dir2;
        parsed_dir3_count = lane_dir3;
    end

    reg [RUN_COUNT_WIDTH-1:0] capture0_count;
    reg [RUN_COUNT_WIDTH-1:0] capture1_count;
    reg [ROW_COUNT_WIDTH-1:0] capture0_row;
    reg [ROW_COUNT_WIDTH-1:0] capture1_row;
    reg capture0_last_row;
    reg capture1_last_row;
    reg capture0_ready;
    reg capture1_ready;
    reg capture_bank;
    reg capture_overflow;
    reg processing_overflow;

    reg consume_capture0;
    reg consume_capture1;
    reg processing_bank0_busy;
    reg processing_bank1_busy;

    wire active_capture_bank = i_canny_sof ? 1'b0 : capture_bank;
    wire [RUN_COUNT_WIDTH-1:0] active_capture_count = canny_line_start ?
        {RUN_COUNT_WIDTH{1'b0}} :
        (active_capture_bank ? capture1_count : capture0_count);
    wire [RUN_COUNT_WIDTH:0] capture_count_sum =
        {1'b0, active_capture_count} + close0_valid + close1_valid;
    wire [RUN_COUNT_WIDTH-1:0] capture_count_clamped =
        (capture_count_sum > MAX_RUNS_PER_ROW) ? MAX_RUNS_PER_ROW :
        capture_count_sum[RUN_COUNT_WIDTH-1:0];
    wire close0_fits = close0_valid && (active_capture_count < MAX_RUNS_PER_ROW);
    wire close1_fits = close1_valid &&
        (active_capture_count + close0_valid < MAX_RUNS_PER_ROW);
    wire capture_write = i_canny_valid &&
        (i_canny_sof || !(capture_overflow || processing_overflow));
    wire [71:0] capture_record0 = {close0_start,close0_end,
        close0_dir0,close0_dir1,close0_dir2,close0_dir3};
    wire [71:0] capture_record1 = {close1_start,close1_end,
        close1_dir0,close1_dir1,close1_dir2,close1_dir3};
    wire [RUN_ADDR_WIDTH-1:0] second_write_addr = active_capture_count + close0_valid;
    wire [71:0] capture_read0, capture_read1;
    genvar run_bank;
    generate for (run_bank=0; run_bank<2; run_bank=run_bank+1) begin : run_tables
        wire write0 = capture_write && (active_capture_bank==run_bank) && close0_fits;
        wire write1 = capture_write && (active_capture_bank==run_bank) && close1_fits;
        wire [71:0] read_record;
        // The second port writes a possible second closure on the capture bank;
        // on the other bank it synchronously reads the current processing run.
        true_dual_port_ram #(.DATA_WIDTH(72),.ADDR_WIDTH(RUN_ADDR_WIDTH),
            .WRITE_MODE_1("READ_FIRST"),.WRITE_MODE_2("READ_FIRST"),
            .OUTPUT_REG_1("FALSE"),.OUTPUT_REG_2("FALSE"),.RAM_INIT_FILE("")) table_ram (
            .clka(clk),.clkb(clk),.we1(write0),.we2(write1),
            .din1(capture_record0),.din2(capture_record1),
            .addr1(active_capture_count[RUN_ADDR_WIDTH-1:0]),
            .addr2(write1 ? second_write_addr : current_run_index[RUN_ADDR_WIDTH-1:0]),
            .dout1(),.dout2(read_record));
        if (run_bank==0) assign capture_read0=read_record;
        else assign capture_read1=read_record;
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            canny_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
            canny_next_row <= {ROW_COUNT_WIDTH{1'b0}};
            run_open <= 1'b0;
            run_start <= 12'b0;
            run_dir0_count <= 12'b0;
            run_dir1_count <= 12'b0;
            run_dir2_count <= 12'b0;
            run_dir3_count <= 12'b0;
            capture0_count <= {RUN_COUNT_WIDTH{1'b0}};
            capture1_count <= {RUN_COUNT_WIDTH{1'b0}};
            capture0_row <= {ROW_COUNT_WIDTH{1'b0}};
            capture1_row <= {ROW_COUNT_WIDTH{1'b0}};
            capture0_last_row <= 1'b0;
            capture1_last_row <= 1'b0;
            capture0_ready <= 1'b0;
            capture1_ready <= 1'b0;
            capture_bank <= 1'b0;
            capture_overflow <= 1'b0;
        end else begin
            if (consume_capture0)
                capture0_ready <= 1'b0;
            if (consume_capture1)
                capture1_ready <= 1'b0;

            if (i_canny_sof) begin
                capture0_ready <= 1'b0;
                capture1_ready <= 1'b0;
                capture_bank <= 1'b0;
                capture_overflow <= 1'b0;
            end

            // An over-budget frame cannot produce a valid result.  Stop
            // writing the large CCL memories until the next SOF; the raw
            // overlay path remains independent and continues to display.
            if (!i_canny_sof && (capture_overflow || processing_overflow)) begin
                capture0_ready <= 1'b0;
                capture1_ready <= 1'b0;
                run_open <= 1'b0;
            end

            if (i_canny_valid &&
                (i_canny_sof || !(capture_overflow || processing_overflow))) begin
                run_open <= parsed_run_open;
                run_start <= parsed_run_start;
                run_dir0_count <= parsed_dir0_count;
                run_dir1_count <= parsed_dir1_count;
                run_dir2_count <= parsed_dir2_count;
                run_dir3_count <= parsed_dir3_count;

                if (canny_last_pair) begin
                    canny_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
                    canny_next_row <= canny_row + 1'b1;
                end else begin
                    canny_next_pair <= canny_pair + 1'b1;
                    canny_next_row <= canny_row;
                end

                if (canny_line_start && !i_canny_sof) begin
                    if ((!active_capture_bank &&
                         (capture0_ready || processing_bank0_busy)) ||
                        (active_capture_bank &&
                         (capture1_ready || processing_bank1_busy)))
                        capture_overflow <= 1'b1;
                end
                if (capture_count_sum > MAX_RUNS_PER_ROW)
                    capture_overflow <= 1'b1;

                if (!active_capture_bank) begin
                    capture0_count <= capture_count_clamped;
                end else begin
                    capture1_count <= capture_count_clamped;
                end

                if (canny_last_pair) begin
                    run_open <= 1'b0;
                    if (!active_capture_bank) begin
                        capture0_row <= canny_row;
                        capture0_last_row <= canny_last_row;
                        capture0_ready <= 1'b1;
                    end else begin
                        capture1_row <= canny_row;
                        capture1_last_row <= canny_last_row;
                        capture1_ready <= 1'b1;
                    end
                    capture_bank <= ~active_capture_bank;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Connected-component labelling and per-component feature statistics.
    // -------------------------------------------------------------------------
    reg [3:0] state;
    reg expected_processing_bank;
    reg processing_bank;
    reg [ROW_COUNT_WIDTH-1:0] processing_row;
    reg processing_last_row;
    reg [RUN_COUNT_WIDTH-1:0] processing_run_count;

    reg [LABEL_WIDTH-1:0] curr_run_label [0:MAX_RUNS_PER_ROW-1];
    reg curr_run_label_valid [0:MAX_RUNS_PER_ROW-1];
    reg [11:0] prev_run_start [0:MAX_RUNS_PER_ROW-1];
    reg [11:0] prev_run_end [0:MAX_RUNS_PER_ROW-1];
    reg [LABEL_WIDTH-1:0] prev_run_label [0:MAX_RUNS_PER_ROW-1];
    reg [RUN_COUNT_WIDTH-1:0] prev_run_count;

    reg [MAX_LABELS-1:0] component_active;
    reg [MAX_LABELS-1:0] component_touched;
    reg [LABEL_WIDTH-1:0] canonical_label [0:MAX_LABELS-1];
    reg [11:0] component_x_min [0:MAX_LABELS-1];
    reg [11:0] component_x_max [0:MAX_LABELS-1];
    reg [11:0] component_y_min [0:MAX_LABELS-1];
    reg [11:0] component_y_max [0:MAX_LABELS-1];
    reg [21:0] component_edge_count [0:MAX_LABELS-1];
    reg [21:0] component_span_area [0:MAX_LABELS-1];
    reg [21:0] component_dir0_count [0:MAX_LABELS-1];
    reg [21:0] component_dir1_count [0:MAX_LABELS-1];
    reg [21:0] component_dir2_count [0:MAX_LABELS-1];
    reg [21:0] component_dir3_count [0:MAX_LABELS-1];
    reg [11:0] component_first_span [0:MAX_LABELS-1];
    reg [11:0] component_last_span [0:MAX_LABELS-1];
    reg [11:0] component_max_span [0:MAX_LABELS-1];
    reg [12:0] component_first_center2 [0:MAX_LABELS-1];
    reg [12:0] component_last_center2 [0:MAX_LABELS-1];
    reg [11:0] component_row_count [0:MAX_LABELS-1];
    reg [11:0] component_row_x_min [0:MAX_LABELS-1];
    reg [11:0] component_row_x_max [0:MAX_LABELS-1];

    reg [RUN_COUNT_WIDTH-1:0] current_run_index;
    reg [RUN_COUNT_WIDTH-1:0] previous_base_index;
    reg [RUN_COUNT_WIDTH-1:0] previous_scan_index;
    reg [RUN_COUNT_WIDTH-1:0] swap_valid_count;
    reg selected_label_valid;
    reg [LABEL_WIDTH-1:0] selected_label;
    reg [LABEL_WIDTH-1:0] label_sweep_index;

    wire [71:0] processing_record = processing_bank ? capture_read1 : capture_read0;
    wire [11:0] processing_run_start = processing_record[71:60];
    wire [11:0] processing_run_end = processing_record[59:48];
    wire [11:0] processing_run_dir0 = processing_record[47:36];
    wire [11:0] processing_run_dir1 = processing_record[35:24];
    wire [11:0] processing_run_dir2 = processing_record[23:12];
    wire [11:0] processing_run_dir3 = processing_record[11:0];

    reg free_label_valid;
    reg [LABEL_WIDTH-1:0] free_label;
    integer free_index;
    always @(*) begin
        free_label_valid = 1'b0;
        free_label = {LABEL_WIDTH{1'b0}};
        for (free_index = 0; free_index < MAX_LABELS; free_index = free_index + 1) begin
            if (!free_label_valid && !component_active[free_index]) begin
                free_label_valid = 1'b1;
                free_label = free_index[LABEL_WIDTH-1:0];
            end
        end
    end

    reg [3:0] work_object_count;
    reg [2:0] work_object_class [0:MAX_OBJECTS-1];
    reg [7:0] work_object_confidence [0:MAX_OBJECTS-1];
    reg [11:0] work_object_x_min [0:MAX_OBJECTS-1];
    reg [11:0] work_object_x_max [0:MAX_OBJECTS-1];
    reg [11:0] work_object_y_min [0:MAX_OBJECTS-1];
    reg [11:0] work_object_y_max [0:MAX_OBJECTS-1];
    reg [4:0] work_shape_mask;
    integer mask_index;

    always @(*) begin
        work_shape_mask = 5'b00000;
        for (mask_index = 0; mask_index < MAX_OBJECTS;
             mask_index = mask_index + 1) begin
            if (mask_index < work_object_count) begin
                case (work_object_class[mask_index])
                    SHAPE_RECTANGLE: work_shape_mask[0] = 1'b1;
                    SHAPE_TRIANGLE:  work_shape_mask[1] = 1'b1;
                    SHAPE_CIRCLE:    work_shape_mask[2] = 1'b1;
                    SHAPE_ELLIPSE:   work_shape_mask[3] = 1'b1;
                    SHAPE_TRAPEZOID: work_shape_mask[4] = 1'b1;
                    default:         ;
                endcase
            end
        end
    end

    reg [2:0] published_object_class [0:MAX_OBJECTS-1];
    reg [11:0] published_object_x_min [0:MAX_OBJECTS-1];
    reg [11:0] published_object_x_max [0:MAX_OBJECTS-1];
    reg [11:0] published_object_y_min [0:MAX_OBJECTS-1];
    reg [11:0] published_object_y_max [0:MAX_OBJECTS-1];
    reg [3:0] detected_count;
    reg [4:0] detected_mask;
    reg publish_valid;
    reg overflow_published;
    reg track_flush_pending;
    // Context changes occur on RAW SOF, ahead of the delayed Canny SOF.
    // Discard any old-frame publication still draining through that pipeline.
    always @(posedge clk or negedge rst_n)
        if (!rst_n) track_flush_pending <= 1'b0;
        else if (i_track_clear) track_flush_pending <= 1'b1;
        else if (i_canny_sof) track_flush_pending <= 1'b0;
    wire [MAX_OBJECTS*3-1:0] detected_class, rendered_class;
    wire [MAX_OBJECTS*12-1:0] detected_x0, detected_x1, detected_y0, detected_y1;
    wire [MAX_OBJECTS*12-1:0] rendered_x0, rendered_x1, rendered_y0, rendered_y1;
    genvar descriptor_index;
    generate
        for (descriptor_index=0; descriptor_index<MAX_OBJECTS; descriptor_index=descriptor_index+1) begin : descriptors
            assign detected_class[descriptor_index*3 +: 3] = published_object_class[descriptor_index];
            assign detected_x0[descriptor_index*12 +: 12] = published_object_x_min[descriptor_index];
            assign detected_x1[descriptor_index*12 +: 12] = published_object_x_max[descriptor_index];
            assign detected_y0[descriptor_index*12 +: 12] = published_object_y_min[descriptor_index];
            assign detected_y1[descriptor_index*12 +: 12] = published_object_y_max[descriptor_index];
        end
        if (TRACK_ENABLE) begin : temporal_confirmation
            shape_track_filter #(.MAX_OBJECTS(MAX_OBJECTS)) tracks (
                .clk(clk), .rst_n(rst_n), .i_clear(i_track_clear || track_flush_pending),
                .i_update(publish_valid), .i_overflow(overflow_published),
                .i_count(detected_count), .i_class(detected_class),
                .i_x_min(detected_x0), .i_x_max(detected_x1),
                .i_y_min(detected_y0), .i_y_max(detected_y1),
                .o_count(o_object_count), .o_shape_mask(o_shape_mask),
                .o_class(rendered_class), .o_x_min(rendered_x0), .o_x_max(rendered_x1),
                .o_y_min(rendered_y0), .o_y_max(rendered_y1),
                .o_stale(o_tracks_stale), .o_busy()
            );
        end else begin : single_frame_result
            assign o_object_count = detected_count;
            assign o_shape_mask = detected_mask;
            assign o_tracks_stale = 1'b0;
            assign rendered_class = detected_class;
            assign rendered_x0 = detected_x0;
            assign rendered_x1 = detected_x1;
            assign rendered_y0 = detected_y0;
            assign rendered_y1 = detected_y1;
        end
    endgenerate

    wire [11:0] sweep_row_span =
        component_row_x_max[label_sweep_index] -
        component_row_x_min[label_sweep_index] + 12'd1;
    wire [12:0] sweep_row_center2 =
        {1'b0, component_row_x_min[label_sweep_index]} +
        {1'b0, component_row_x_max[label_sweep_index]};
    wire [11:0] final_width =
        component_x_max[label_sweep_index] -
        component_x_min[label_sweep_index] + 12'd1;
    wire [11:0] final_height =
        component_y_max[label_sweep_index] -
        component_y_min[label_sweep_index] + 12'd1;
    wire [23:0] final_bbox_area = final_width * final_height;
    wire [31:0] final_span_area_ext = {10'b0, component_span_area[label_sweep_index]};
    wire [31:0] final_bbox_area_ext = {8'b0, final_bbox_area};
    wire [31:0] final_span_area_100 =
        (final_span_area_ext << 6) + (final_span_area_ext << 5) +
        (final_span_area_ext << 2);
    wire [31:0] final_bbox_area_34 =
        (final_bbox_area_ext << 5) + (final_bbox_area_ext << 1);
    wire [31:0] final_bbox_area_38 =
        (final_bbox_area_ext << 5) + (final_bbox_area_ext << 2) +
        (final_bbox_area_ext << 1);
    wire [31:0] final_bbox_area_64 = final_bbox_area_ext << 6;
    wire [31:0] final_bbox_area_74 =
        (final_bbox_area_ext << 6) + (final_bbox_area_ext << 3) +
        (final_bbox_area_ext << 1);
    wire [31:0] final_bbox_area_85 =
        (final_bbox_area_ext << 6) + (final_bbox_area_ext << 4) +
        (final_bbox_area_ext << 2) + final_bbox_area_ext;
    wire [31:0] final_bbox_area_92 =
        (final_bbox_area_ext << 6) + (final_bbox_area_ext << 4) +
        (final_bbox_area_ext << 3) + (final_bbox_area_ext << 2);

    wire [11:0] final_dim_max = (final_width >= final_height) ? final_width : final_height;
    wire [11:0] final_dim_min = (final_width >= final_height) ? final_height : final_width;
    wire [11:0] final_dim_diff = final_dim_max - final_dim_min;
    wire [15:0] final_dim_diff_x10 =
        ({4'b0, final_dim_diff} << 3) + ({4'b0, final_dim_diff} << 1);
    // A bbox axis ratio below 0.8 separates visibly elongated ellipses from circles.
    wire [15:0] final_dim_max_x2 = {4'b0, final_dim_max} << 1;
    wire final_aspect_near_square = final_dim_diff_x10 <= final_dim_max_x2;

    wire [11:0] final_first_span = component_first_span[label_sweep_index];
    wire [11:0] final_last_span = component_last_span[label_sweep_index];
    wire [11:0] final_span_difference = (final_first_span >= final_last_span) ?
        final_first_span - final_last_span : final_last_span - final_first_span;
    wire [14:0] final_span_difference_x5 =
        ({3'b0, final_span_difference} << 2) + {3'b0, final_span_difference};
    wire [12:0] final_max_span_x2 =
        {1'b0, component_max_span[label_sweep_index]} << 1;
    wire [16:0] final_max_span_x9 =
        ({5'b0, component_max_span[label_sweep_index]} << 3) +
        {5'b0, component_max_span[label_sweep_index]};
    // Forty-percent tolerance keeps a slightly blurred or moving symmetric
    // contour from changing class because only one end row lost a few pixels.
    wire final_span_symmetric = final_span_difference_x5 <= final_max_span_x2;

    wire [13:0] final_center_sum =
        {1'b0, component_first_center2[label_sweep_index]} +
        {1'b0, component_last_center2[label_sweep_index]};
    wire [13:0] final_bbox_center_twice =
        ({2'b0, component_x_min[label_sweep_index]} +
         {2'b0, component_x_max[label_sweep_index]}) << 1;
    wire [13:0] final_center_difference =
        (final_center_sum >= final_bbox_center_twice) ?
        final_center_sum - final_bbox_center_twice :
        final_bbox_center_twice - final_center_sum;
    wire [16:0] final_center_difference_x5 =
        ({3'b0, final_center_difference} << 2) + {3'b0, final_center_difference};
    wire [15:0] final_width_x2 = {4'b0, final_width} << 1;
    wire final_center_symmetric = final_center_difference_x5 <= final_width_x2;
    wire final_central_symmetric = final_span_symmetric && final_center_symmetric;

    wire [12:0] final_bbox_center2 =
        {1'b0, component_x_min[label_sweep_index]} +
        {1'b0, component_x_max[label_sweep_index]};
    wire [12:0] final_first_center_difference =
        (component_first_center2[label_sweep_index] >= final_bbox_center2) ?
        component_first_center2[label_sweep_index] - final_bbox_center2 :
        final_bbox_center2 - component_first_center2[label_sweep_index];
    wire [12:0] final_last_center_difference =
        (component_last_center2[label_sweep_index] >= final_bbox_center2) ?
        component_last_center2[label_sweep_index] - final_bbox_center2 :
        final_bbox_center2 - component_last_center2[label_sweep_index];
    wire final_end_centers_near_middle =
        (({1'b0, final_first_center_difference} << 1) <= {1'b0, final_width}) &&
        (({1'b0, final_last_center_difference} << 1) <= {1'b0, final_width});
    wire [16:0] final_first_span_x20 =
        ({5'b0, final_first_span} << 4) + ({5'b0, final_first_span} << 2);
    wire [16:0] final_last_span_x20 =
        ({5'b0, final_last_span} << 4) + ({5'b0, final_last_span} << 2);
    wire final_circle_narrow_ends =
        (final_first_span_x20 <= final_max_span_x9) &&
        (final_last_span_x20 <= final_max_span_x9);

    wire [23:0] final_dir0 = {2'b0, component_dir0_count[label_sweep_index]};
    wire [23:0] final_dir1 = {2'b0, component_dir1_count[label_sweep_index]};
    wire [23:0] final_dir2 = {2'b0, component_dir2_count[label_sweep_index]};
    wire [23:0] final_dir3 = {2'b0, component_dir3_count[label_sweep_index]};
    wire [23:0] final_direction_total = final_dir0 + final_dir1 + final_dir2 + final_dir3;
    wire final_dir0_significant = ({4'b0, final_dir0} << 4) >= {4'b0, final_direction_total};
    wire final_dir1_significant = ({4'b0, final_dir1} << 4) >= {4'b0, final_direction_total};
    wire final_dir2_significant = ({4'b0, final_dir2} << 4) >= {4'b0, final_direction_total};
    wire final_dir3_significant = ({4'b0, final_dir3} << 4) >= {4'b0, final_direction_total};
    wire [2:0] final_significant_directions =
        final_dir0_significant + final_dir1_significant +
        final_dir2_significant + final_dir3_significant;
    wire [23:0] final_axis_direction_sum = final_dir0 + final_dir2;
    wire [23:0] final_diagonal_direction_sum = final_dir1 + final_dir3;
    wire [27:0] final_direction_total_x7 =
        ({4'b0, final_direction_total} << 2) +
        ({4'b0, final_direction_total} << 1) +
        {4'b0, final_direction_total};
    wire [27:0] final_axis_direction_x10 =
        ({4'b0, final_axis_direction_sum} << 3) +
        ({4'b0, final_axis_direction_sum} << 1);
    wire [27:0] final_diagonal_direction_x10 =
        ({4'b0, final_diagonal_direction_sum} << 3) +
        ({4'b0, final_diagonal_direction_sum} << 1);
    wire final_rectangle_direction =
        (final_axis_direction_x10 >= final_direction_total_x7) ||
        (final_diagonal_direction_x10 >= final_direction_total_x7);
    // Circular geometry is decided primarily by extent and tapered end rows.
    // Direction bins are only a validity check: motion blur can temporarily
    // collapse a circle from three bins to two and must not turn it into a box.
    wire final_circle_direction = final_significant_directions >= 2;
    wire final_triangle_direction = final_significant_directions >= 2;

    wire final_touches_border =
        (component_x_min[label_sweep_index] <= BORDER_REJECT_MARGIN) ||
        (component_y_min[label_sweep_index] <= BORDER_REJECT_MARGIN) ||
        (component_x_max[label_sweep_index] >= IMAGE_WIDTH - 1 - BORDER_REJECT_MARGIN) ||
        (component_y_max[label_sweep_index] >= IMAGE_HEIGHT - 1 - BORDER_REJECT_MARGIN) ||
        (roi_active &&
         ((component_x_min[label_sweep_index] <= ROI_X_MIN + BORDER_REJECT_MARGIN) ||
          (component_x_max[label_sweep_index] >= ROI_X_MAX - BORDER_REJECT_MARGIN) ||
          (component_y_min[label_sweep_index] <= ROI_Y_MIN + BORDER_REJECT_MARGIN) ||
          (component_y_max[label_sweep_index] >= ROI_Y_MAX - BORDER_REJECT_MARGIN)));
    wire final_valid_size =
        (final_width >= MIN_OBJECT_WIDTH) &&
        (final_height >= MIN_OBJECT_HEIGHT) &&
        (component_edge_count[label_sweep_index] >= MIN_OBJECT_EDGES) &&
        (final_direction_total >= (MIN_OBJECT_EDGES >> 2)) &&
        ((component_row_count[label_sweep_index] << 1) >= final_height) &&
        !final_touches_border;
    wire final_circle = final_central_symmetric && final_aspect_near_square &&
                        final_circle_narrow_ends && final_end_centers_near_middle &&
                        final_circle_direction &&
                        (final_span_area_100 >= final_bbox_area_64) &&
                        (final_span_area_100 <= final_bbox_area_92);
    // A rotated rectangle/rhombus has two dominant gradient bins. Ellipse
    // requires at least three plus tapered, centered ends and curved-shape fill.
    wire final_ellipse = final_central_symmetric && !final_aspect_near_square &&
                         final_circle_narrow_ends && final_end_centers_near_middle &&
                         (final_significant_directions >= 3) &&
                         (final_span_area_100 >= final_bbox_area_64) &&
                         (final_span_area_100 <= final_bbox_area_92);
    wire [31:0] final_bbox_area_60 = (final_bbox_area_ext << 6) - (final_bbox_area_ext << 2);
    wire [31:0] final_bbox_area_95 = (final_bbox_area_ext << 6) +
        (final_bbox_area_ext << 5) - final_bbox_area_ext;
    wire [11:0] final_end_min = final_first_span < final_last_span ? final_first_span : final_last_span;
    // Aligned trapezoid: two finite bases; rotation turns those rows into corner
    // tips, so use their center imbalance instead. Area rejects pointed triangles.
    // These are bounded coarse features, not arbitrary quadrilateral fitting.
    wire final_finite_unequal_bases =
        ({2'b0, final_end_min} << 2) >= {2'b0, final_width} &&
        ({3'b0, final_span_difference} << 3) >= {3'b0, final_width};
    wire final_unequal_end_centers =
        (({3'b0, final_center_difference} << 2) + {3'b0, final_center_difference}) >
        {5'b0, final_width};
    wire final_trapezoid = !final_circle && !final_ellipse && final_triangle_direction &&
                          (final_finite_unequal_bases || final_unequal_end_centers) &&
                          (final_span_area_100 >= final_bbox_area_60) &&
                          (final_span_area_100 <= final_bbox_area_95);
    wire final_triangle = !final_central_symmetric && final_triangle_direction &&
                          (final_span_area_100 >= final_bbox_area_34) &&
                          (final_span_area_100 <= final_bbox_area_74);
    wire [12:0] final_height_x3 =
        ({1'b0, final_height} << 1) + {1'b0, final_height};
    wire [12:0] final_component_rows_x2 =
        {1'b0, component_row_count[label_sweep_index]} << 1;
    wire final_parallel_branch_merge =
        final_component_rows_x2 >= final_height_x3;
    // A dense rectangular contour remains a rectangle when motion damages
    // only its first or last edge row.  Two long sides that merge late at the
    // surviving opposite edge are detected by their accumulated row count.
    // Circle and triangle are evaluated first with stricter geometry checks.
    wire final_rectangle =
        (final_span_area_100 >= final_bbox_area_85) ||
        (final_central_symmetric &&
         (final_span_area_100 >= final_bbox_area_38) &&
         final_rectangle_direction) ||
        (final_parallel_branch_merge && final_rectangle_direction);
    wire [2:0] final_shape_class = final_circle ? SHAPE_CIRCLE :
                                   final_ellipse ? SHAPE_ELLIPSE :
                                   final_trapezoid ? SHAPE_TRAPEZOID :
                                   final_triangle ? SHAPE_TRIANGLE :
                                   final_rectangle ? SHAPE_RECTANGLE : SHAPE_UNKNOWN;
    wire [7:0] final_shape_confidence = final_circle ? 8'd92 :
                                        final_ellipse ? 8'd88 :
                                        final_trapezoid ? 8'd84 :
                                        final_triangle ? 8'd84 :
                                        final_rectangle ?
                                            ((final_span_area_100 >= final_bbox_area_85) ?
                                             8'd94 : 8'd86) : 8'd0;

    reg dedup_match_valid;
    reg [OBJECT_INDEX_WIDTH-1:0] dedup_match_index;
    integer dedup_index;
    always @(*) begin
        dedup_match_valid = 1'b0;
        dedup_match_index = {OBJECT_INDEX_WIDTH{1'b0}};
        for (dedup_index = 0; dedup_index < MAX_OBJECTS; dedup_index = dedup_index + 1) begin
            if (!dedup_match_valid && (dedup_index < work_object_count) &&
                ((({1'b0, component_x_min[label_sweep_index]} <=
                    {1'b0, work_object_x_min[dedup_index]} + MERGE_MARGIN) &&
                  ({1'b0, component_x_max[label_sweep_index]} + MERGE_MARGIN >=
                    {1'b0, work_object_x_max[dedup_index]}) &&
                  ({1'b0, component_y_min[label_sweep_index]} <=
                    {1'b0, work_object_y_min[dedup_index]} + MERGE_MARGIN) &&
                  ({1'b0, component_y_max[label_sweep_index]} + MERGE_MARGIN >=
                    {1'b0, work_object_y_max[dedup_index]})) ||
                 (({1'b0, work_object_x_min[dedup_index]} <=
                    {1'b0, component_x_min[label_sweep_index]} + MERGE_MARGIN) &&
                  ({1'b0, work_object_x_max[dedup_index]} + MERGE_MARGIN >=
                    {1'b0, component_x_max[label_sweep_index]}) &&
                  ({1'b0, work_object_y_min[dedup_index]} <=
                    {1'b0, component_y_min[label_sweep_index]} + MERGE_MARGIN) &&
                  ({1'b0, work_object_y_max[dedup_index]} + MERGE_MARGIN >=
                    {1'b0, component_y_max[label_sweep_index]})))) begin
                dedup_match_valid = 1'b1;
                dedup_match_index = dedup_index[OBJECT_INDEX_WIDTH-1:0];
            end
        end
    end

    integer reset_index;
    integer merge_index;
    integer run_merge_index;
    integer publish_index;
    reg [LABEL_WIDTH-1:0] overlap_label;
    reg [11:0] applied_run_length;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_WAIT_ROW;
            expected_processing_bank <= 1'b0;
            processing_bank <= 1'b0;
            processing_row <= {ROW_COUNT_WIDTH{1'b0}};
            processing_last_row <= 1'b0;
            processing_run_count <= {RUN_COUNT_WIDTH{1'b0}};
            processing_overflow <= 1'b0;
            consume_capture0 <= 1'b0;
            consume_capture1 <= 1'b0;
            processing_bank0_busy <= 1'b0;
            processing_bank1_busy <= 1'b0;
            prev_run_count <= {RUN_COUNT_WIDTH{1'b0}};
            current_run_index <= {RUN_COUNT_WIDTH{1'b0}};
            previous_base_index <= {RUN_COUNT_WIDTH{1'b0}};
            previous_scan_index <= {RUN_COUNT_WIDTH{1'b0}};
            swap_valid_count <= {RUN_COUNT_WIDTH{1'b0}};
            selected_label_valid <= 1'b0;
            selected_label <= {LABEL_WIDTH{1'b0}};
            label_sweep_index <= {LABEL_WIDTH{1'b0}};
            component_active <= {MAX_LABELS{1'b0}};
            component_touched <= {MAX_LABELS{1'b0}};
            work_object_count <= 4'b0;
            detected_count <= 4'b0;
            detected_mask <= 5'b00000;
            publish_valid <= 1'b0;
            overflow_published <= 1'b0;
            overlap_label <= {LABEL_WIDTH{1'b0}};
            applied_run_length <= 12'b0;
            for (reset_index = 0; reset_index < MAX_LABELS; reset_index = reset_index + 1) begin
                canonical_label[reset_index] <= reset_index[LABEL_WIDTH-1:0];
                component_x_min[reset_index] <= 12'b0;
                component_x_max[reset_index] <= 12'b0;
                component_y_min[reset_index] <= 12'b0;
                component_y_max[reset_index] <= 12'b0;
                component_edge_count[reset_index] <= 22'b0;
                component_span_area[reset_index] <= 22'b0;
                component_dir0_count[reset_index] <= 22'b0;
                component_dir1_count[reset_index] <= 22'b0;
                component_dir2_count[reset_index] <= 22'b0;
                component_dir3_count[reset_index] <= 22'b0;
                component_first_span[reset_index] <= 12'b0;
                component_last_span[reset_index] <= 12'b0;
                component_max_span[reset_index] <= 12'b0;
                component_first_center2[reset_index] <= 13'b0;
                component_last_center2[reset_index] <= 13'b0;
                component_row_count[reset_index] <= 12'b0;
                component_row_x_min[reset_index] <= 12'b0;
                component_row_x_max[reset_index] <= 12'b0;
            end
            for (reset_index = 0; reset_index < MAX_RUNS_PER_ROW; reset_index = reset_index + 1) begin
                curr_run_label[reset_index] <= {LABEL_WIDTH{1'b0}};
                curr_run_label_valid[reset_index] <= 1'b0;
                prev_run_start[reset_index] <= 12'b0;
                prev_run_end[reset_index] <= 12'b0;
                prev_run_label[reset_index] <= {LABEL_WIDTH{1'b0}};
            end
            for (reset_index = 0; reset_index < MAX_OBJECTS; reset_index = reset_index + 1) begin
                work_object_class[reset_index] <= SHAPE_UNKNOWN;
                work_object_confidence[reset_index] <= 8'b0;
                work_object_x_min[reset_index] <= 12'b0;
                work_object_x_max[reset_index] <= 12'b0;
                work_object_y_min[reset_index] <= 12'b0;
                work_object_y_max[reset_index] <= 12'b0;
                published_object_class[reset_index] <= SHAPE_UNKNOWN;
                published_object_x_min[reset_index] <= 12'b0;
                published_object_x_max[reset_index] <= 12'b0;
                published_object_y_min[reset_index] <= 12'b0;
                published_object_y_max[reset_index] <= 12'b0;
            end
        end else begin
            consume_capture0 <= 1'b0;
            consume_capture1 <= 1'b0;
            publish_valid <= 1'b0;

            // Even an aborted frame produces one result event, so stale boxes
            // expire after a bounded number of failed frames, not indefinitely.
            if (i_canny_sof) begin
                overflow_published <= capture_overflow || processing_overflow;
                if ((capture_overflow || processing_overflow) && !track_flush_pending)
                    publish_valid <= 1'b1;
            end

            if (i_canny_sof) begin
                state <= ST_WAIT_ROW;
                expected_processing_bank <= 1'b0;
                processing_bank0_busy <= 1'b0;
                processing_bank1_busy <= 1'b0;
                processing_overflow <= 1'b0;
                prev_run_count <= {RUN_COUNT_WIDTH{1'b0}};
                component_active <= {MAX_LABELS{1'b0}};
                component_touched <= {MAX_LABELS{1'b0}};
                work_object_count <= 4'b0;
            end else if (capture_overflow || processing_overflow) begin
                // Abort work that would be discarded at publish time anyway.
                // This bounds switching activity on dense, unsupported scenes.
                state <= ST_WAIT_ROW;
                processing_bank0_busy <= 1'b0;
                processing_bank1_busy <= 1'b0;
                prev_run_count <= {RUN_COUNT_WIDTH{1'b0}};
                component_active <= {MAX_LABELS{1'b0}};
                component_touched <= {MAX_LABELS{1'b0}};
                work_object_count <= 4'b0;
                detected_count <= 4'b0;
                detected_mask <= 5'b00000;
            end else begin
                case (state)
                    ST_WAIT_ROW: begin
                        if (!expected_processing_bank && capture0_ready) begin
                            consume_capture0 <= 1'b1;
                            processing_bank0_busy <= 1'b1;
                            processing_bank <= 1'b0;
                            processing_row <= capture0_row;
                            processing_last_row <= capture0_last_row;
                            processing_run_count <= capture0_count;
                            expected_processing_bank <= 1'b1;
                            state <= ST_PROC_INIT;
                        end else if (expected_processing_bank && capture1_ready) begin
                            consume_capture1 <= 1'b1;
                            processing_bank1_busy <= 1'b1;
                            processing_bank <= 1'b1;
                            processing_row <= capture1_row;
                            processing_last_row <= capture1_last_row;
                            processing_run_count <= capture1_count;
                            expected_processing_bank <= 1'b0;
                            state <= ST_PROC_INIT;
                        end else if ((!expected_processing_bank && capture1_ready) ||
                                     (expected_processing_bank && capture0_ready)) begin
                            processing_overflow <= 1'b1;
                        end
                    end

                    ST_PROC_INIT: begin
                        current_run_index <= {RUN_COUNT_WIDTH{1'b0}};
                        previous_base_index <= {RUN_COUNT_WIDTH{1'b0}};
                        if (processing_run_count == 0) begin
                            label_sweep_index <= {LABEL_WIDTH{1'b0}};
                            state <= ST_ROW_ACCUM;
                        end else begin
                            state <= ST_RUN_FETCH;
                        end
                    end

                    ST_RUN_FETCH: state <= ST_RUN_INIT;
                    ST_SWAP_FETCH: state <= ST_SWAP;

                    ST_RUN_INIT: begin
                        curr_run_label_valid[current_run_index] <= 1'b0;
                        selected_label_valid <= 1'b0;
                        selected_label <= {LABEL_WIDTH{1'b0}};
                        previous_scan_index <= previous_base_index;
                        state <= ST_RUN_SCAN;
                    end

                    ST_RUN_SCAN: begin
                        if (previous_scan_index >= prev_run_count) begin
                            state <= ST_RUN_APPLY;
                        end else if ({1'b0, prev_run_end[previous_scan_index]} +
                                     RUN_CONNECT_MARGIN < {1'b0, processing_run_start}) begin
                            previous_scan_index <= previous_scan_index + 1'b1;
                            previous_base_index <= previous_scan_index + 1'b1;
                        end else if ({1'b0, prev_run_start[previous_scan_index]} >
                                     {1'b0, processing_run_end} + RUN_CONNECT_MARGIN) begin
                            state <= ST_RUN_APPLY;
                        end else begin
                            overlap_label = canonical_label[prev_run_label[previous_scan_index]];
                            if (!selected_label_valid) begin
                                selected_label_valid <= 1'b1;
                                selected_label <= overlap_label;
                            end else if (overlap_label != selected_label) begin
                                component_x_min[selected_label] <=
                                    (component_x_min[selected_label] <= component_x_min[overlap_label]) ?
                                    component_x_min[selected_label] : component_x_min[overlap_label];
                                component_x_max[selected_label] <=
                                    (component_x_max[selected_label] >= component_x_max[overlap_label]) ?
                                    component_x_max[selected_label] : component_x_max[overlap_label];
                                component_y_min[selected_label] <=
                                    (component_y_min[selected_label] <= component_y_min[overlap_label]) ?
                                    component_y_min[selected_label] : component_y_min[overlap_label];
                                component_y_max[selected_label] <=
                                    (component_y_max[selected_label] >= component_y_max[overlap_label]) ?
                                    component_y_max[selected_label] : component_y_max[overlap_label];
                                component_edge_count[selected_label] <=
                                    component_edge_count[selected_label] + component_edge_count[overlap_label];
                                component_span_area[selected_label] <=
                                    component_span_area[selected_label] + component_span_area[overlap_label];
                                component_dir0_count[selected_label] <=
                                    component_dir0_count[selected_label] + component_dir0_count[overlap_label];
                                component_dir1_count[selected_label] <=
                                    component_dir1_count[selected_label] + component_dir1_count[overlap_label];
                                component_dir2_count[selected_label] <=
                                    component_dir2_count[selected_label] + component_dir2_count[overlap_label];
                                component_dir3_count[selected_label] <=
                                    component_dir3_count[selected_label] + component_dir3_count[overlap_label];
                                component_row_count[selected_label] <=
                                    component_row_count[selected_label] + component_row_count[overlap_label];
                                component_first_span[selected_label] <=
                                    (component_y_min[selected_label] < component_y_min[overlap_label]) ?
                                    component_first_span[selected_label] :
                                    (component_y_min[selected_label] > component_y_min[overlap_label]) ?
                                    component_first_span[overlap_label] :
                                    ((component_first_span[selected_label] >= component_first_span[overlap_label]) ?
                                     component_first_span[selected_label] : component_first_span[overlap_label]);
                                component_first_center2[selected_label] <=
                                    (component_y_min[selected_label] <= component_y_min[overlap_label]) ?
                                    component_first_center2[selected_label] :
                                    component_first_center2[overlap_label];
                                component_last_span[selected_label] <=
                                    (component_y_max[selected_label] > component_y_max[overlap_label]) ?
                                    component_last_span[selected_label] :
                                    (component_y_max[selected_label] < component_y_max[overlap_label]) ?
                                    component_last_span[overlap_label] :
                                    ((component_last_span[selected_label] >= component_last_span[overlap_label]) ?
                                     component_last_span[selected_label] : component_last_span[overlap_label]);
                                component_last_center2[selected_label] <=
                                    (component_y_max[selected_label] >= component_y_max[overlap_label]) ?
                                    component_last_center2[selected_label] :
                                    component_last_center2[overlap_label];
                                component_max_span[selected_label] <=
                                    (component_max_span[selected_label] >= component_max_span[overlap_label]) ?
                                    component_max_span[selected_label] : component_max_span[overlap_label];
                                if (component_touched[overlap_label]) begin
                                    if (!component_touched[selected_label]) begin
                                        component_row_x_min[selected_label] <= component_row_x_min[overlap_label];
                                        component_row_x_max[selected_label] <= component_row_x_max[overlap_label];
                                    end else begin
                                        if (component_row_x_min[overlap_label] < component_row_x_min[selected_label])
                                            component_row_x_min[selected_label] <= component_row_x_min[overlap_label];
                                        if (component_row_x_max[overlap_label] > component_row_x_max[selected_label])
                                            component_row_x_max[selected_label] <= component_row_x_max[overlap_label];
                                    end
                                    component_touched[selected_label] <= 1'b1;
                                end
                                component_active[overlap_label] <= 1'b0;
                                component_touched[overlap_label] <= 1'b0;
                                for (merge_index = 0; merge_index < MAX_LABELS;
                                     merge_index = merge_index + 1) begin
                                    if (canonical_label[merge_index] == overlap_label)
                                        canonical_label[merge_index] <= selected_label;
                                end
                                for (run_merge_index = 0; run_merge_index < MAX_RUNS_PER_ROW;
                                     run_merge_index = run_merge_index + 1) begin
                                    if (prev_run_label[run_merge_index] == overlap_label)
                                        prev_run_label[run_merge_index] <= selected_label;
                                    if (curr_run_label_valid[run_merge_index] &&
                                        (curr_run_label[run_merge_index] == overlap_label))
                                        curr_run_label[run_merge_index] <= selected_label;
                                end
                                canonical_label[overlap_label] <= selected_label;
                            end
                            previous_scan_index <= previous_scan_index + 1'b1;
                        end
                    end

                    ST_RUN_APPLY: begin
                        applied_run_length = processing_run_end -
                                             processing_run_start + 12'd1;
                        if (selected_label_valid) begin
                            curr_run_label[current_run_index] <= selected_label;
                            curr_run_label_valid[current_run_index] <= 1'b1;
                            if (processing_run_start < component_x_min[selected_label])
                                component_x_min[selected_label] <= processing_run_start;
                            if (processing_run_end > component_x_max[selected_label])
                                component_x_max[selected_label] <= processing_run_end;
                            component_y_max[selected_label] <= processing_row;
                            component_edge_count[selected_label] <=
                                component_edge_count[selected_label] + applied_run_length;
                            component_dir0_count[selected_label] <=
                                component_dir0_count[selected_label] + processing_run_dir0;
                            component_dir1_count[selected_label] <=
                                component_dir1_count[selected_label] + processing_run_dir1;
                            component_dir2_count[selected_label] <=
                                component_dir2_count[selected_label] + processing_run_dir2;
                            component_dir3_count[selected_label] <=
                                component_dir3_count[selected_label] + processing_run_dir3;
                            if (!component_touched[selected_label]) begin
                                component_touched[selected_label] <= 1'b1;
                                component_row_x_min[selected_label] <= processing_run_start;
                                component_row_x_max[selected_label] <= processing_run_end;
                            end else begin
                                if (processing_run_start < component_row_x_min[selected_label])
                                    component_row_x_min[selected_label] <= processing_run_start;
                                if (processing_run_end > component_row_x_max[selected_label])
                                    component_row_x_max[selected_label] <= processing_run_end;
                            end
                        end else if (free_label_valid) begin
                            curr_run_label[current_run_index] <= free_label;
                            curr_run_label_valid[current_run_index] <= 1'b1;
                            component_active[free_label] <= 1'b1;
                            component_touched[free_label] <= 1'b1;
                            canonical_label[free_label] <= free_label;
                            component_x_min[free_label] <= processing_run_start;
                            component_x_max[free_label] <= processing_run_end;
                            component_y_min[free_label] <= processing_row;
                            component_y_max[free_label] <= processing_row;
                            component_edge_count[free_label] <= applied_run_length;
                            component_span_area[free_label] <= 22'b0;
                            component_dir0_count[free_label] <= processing_run_dir0;
                            component_dir1_count[free_label] <= processing_run_dir1;
                            component_dir2_count[free_label] <= processing_run_dir2;
                            component_dir3_count[free_label] <= processing_run_dir3;
                            component_first_span[free_label] <= 12'b0;
                            component_last_span[free_label] <= 12'b0;
                            component_max_span[free_label] <= 12'b0;
                            component_first_center2[free_label] <= 13'b0;
                            component_last_center2[free_label] <= 13'b0;
                            component_row_count[free_label] <= 12'b0;
                            component_row_x_min[free_label] <= processing_run_start;
                            component_row_x_max[free_label] <= processing_run_end;
                        end else begin
                            curr_run_label_valid[current_run_index] <= 1'b0;
                            processing_overflow <= 1'b1;
                        end

                        if (current_run_index + 1'b1 >= processing_run_count) begin
                            label_sweep_index <= {LABEL_WIDTH{1'b0}};
                            state <= ST_ROW_ACCUM;
                        end else begin
                            current_run_index <= current_run_index + 1'b1;
                            state <= ST_RUN_FETCH;
                        end
                    end

                    ST_ROW_ACCUM: begin
                        if (component_active[label_sweep_index] &&
                            component_touched[label_sweep_index]) begin
                            component_span_area[label_sweep_index] <=
                                component_span_area[label_sweep_index] + sweep_row_span;
                            component_last_span[label_sweep_index] <= sweep_row_span;
                            component_last_center2[label_sweep_index] <= sweep_row_center2;
                            if (component_row_count[label_sweep_index] == 0) begin
                                component_first_span[label_sweep_index] <= sweep_row_span;
                                component_first_center2[label_sweep_index] <= sweep_row_center2;
                            end
                            if (sweep_row_span > component_max_span[label_sweep_index])
                                component_max_span[label_sweep_index] <= sweep_row_span;
                            component_row_count[label_sweep_index] <=
                                component_row_count[label_sweep_index] + 1'b1;
                        end
                        if (label_sweep_index == MAX_LABELS - 1) begin
                            label_sweep_index <= {LABEL_WIDTH{1'b0}};
                            state <= ST_FINALIZE;
                        end else begin
                            label_sweep_index <= label_sweep_index + 1'b1;
                        end
                    end

                    ST_FINALIZE: begin
                        if (component_active[label_sweep_index] &&
                            (!component_touched[label_sweep_index] || processing_last_row)) begin
                            if (final_valid_size && (final_shape_class != SHAPE_UNKNOWN)) begin
                                if (dedup_match_valid) begin
                                    if (component_x_min[label_sweep_index] <
                                        work_object_x_min[dedup_match_index])
                                        work_object_x_min[dedup_match_index] <=
                                            component_x_min[label_sweep_index];
                                    if (component_x_max[label_sweep_index] >
                                        work_object_x_max[dedup_match_index])
                                        work_object_x_max[dedup_match_index] <=
                                            component_x_max[label_sweep_index];
                                    if (component_y_min[label_sweep_index] <
                                        work_object_y_min[dedup_match_index])
                                        work_object_y_min[dedup_match_index] <=
                                            component_y_min[label_sweep_index];
                                    if (component_y_max[label_sweep_index] >
                                        work_object_y_max[dedup_match_index])
                                        work_object_y_max[dedup_match_index] <=
                                            component_y_max[label_sweep_index];
                                    if (final_shape_confidence >
                                        work_object_confidence[dedup_match_index]) begin
                                        work_object_class[dedup_match_index] <= final_shape_class;
                                        work_object_confidence[dedup_match_index] <=
                                            final_shape_confidence;
                                    end
                                end else if (work_object_count < MAX_OBJECTS) begin
                                    work_object_class[work_object_count] <= final_shape_class;
                                    work_object_confidence[work_object_count] <= final_shape_confidence;
                                    work_object_x_min[work_object_count] <=
                                        component_x_min[label_sweep_index];
                                    work_object_x_max[work_object_count] <=
                                        component_x_max[label_sweep_index];
                                    work_object_y_min[work_object_count] <=
                                        component_y_min[label_sweep_index];
                                    work_object_y_max[work_object_count] <=
                                        component_y_max[label_sweep_index];
                                    work_object_count <= work_object_count + 1'b1;
                                end else begin
                                    processing_overflow <= 1'b1;
                                end
                            end
                            component_active[label_sweep_index] <= 1'b0;
                            component_touched[label_sweep_index] <= 1'b0;
                            canonical_label[label_sweep_index] <= label_sweep_index;
                        end else if (component_active[label_sweep_index]) begin
                            component_touched[label_sweep_index] <= 1'b0;
                        end

                        if (label_sweep_index == MAX_LABELS - 1) begin
                            label_sweep_index <= {LABEL_WIDTH{1'b0}};
                            if (processing_last_row) begin
                                state <= ST_PUBLISH;
                            end else if (processing_run_count == 0) begin
                                prev_run_count <= {RUN_COUNT_WIDTH{1'b0}};
                                if (processing_bank) processing_bank1_busy <= 1'b0;
                                else processing_bank0_busy <= 1'b0;
                                state <= ST_WAIT_ROW;
                            end else begin
                                current_run_index <= {RUN_COUNT_WIDTH{1'b0}};
                                swap_valid_count <= {RUN_COUNT_WIDTH{1'b0}};
                                state <= ST_SWAP_FETCH;
                            end
                        end else begin
                            label_sweep_index <= label_sweep_index + 1'b1;
                        end
                    end

                    ST_SWAP: begin
                        if (curr_run_label_valid[current_run_index]) begin
                            prev_run_start[swap_valid_count] <= processing_run_start;
                            prev_run_end[swap_valid_count] <= processing_run_end;
                            prev_run_label[swap_valid_count] <= curr_run_label[current_run_index];
                            swap_valid_count <= swap_valid_count + 1'b1;
                        end
                        if (current_run_index + 1'b1 >= processing_run_count) begin
                            prev_run_count <= swap_valid_count +
                                              curr_run_label_valid[current_run_index];
                            if (processing_bank) processing_bank1_busy <= 1'b0;
                            else processing_bank0_busy <= 1'b0;
                            state <= ST_WAIT_ROW;
                        end else begin
                            current_run_index <= current_run_index + 1'b1;
                            state <= ST_SWAP_FETCH;
                        end
                    end

                    ST_PUBLISH: begin
                        publish_valid <= 1'b1;
                        overflow_published <= capture_overflow || processing_overflow;
                        if (capture_overflow || processing_overflow) begin
                            detected_count <= 4'b0;
                            detected_mask <= 5'b00000;
                        end else begin
                            detected_count <= work_object_count;
                            detected_mask <= work_shape_mask;
                            for (publish_index = 0; publish_index < MAX_OBJECTS;
                                 publish_index = publish_index + 1) begin
                                published_object_class[publish_index] <=
                                    work_object_class[publish_index];
                                published_object_x_min[publish_index] <=
                                    work_object_x_min[publish_index];
                                published_object_x_max[publish_index] <=
                                    work_object_x_max[publish_index];
                                published_object_y_min[publish_index] <=
                                    work_object_y_min[publish_index];
                                published_object_y_max[publish_index] <=
                                    work_object_y_max[publish_index];
                            end
                        end
                        prev_run_count <= {RUN_COUNT_WIDTH{1'b0}};
                        if (processing_bank) processing_bank1_busy <= 1'b0;
                        else processing_bank0_busy <= 1'b0;
                        state <= ST_WAIT_ROW;
                    end

                    default: begin
                        processing_overflow <= 1'b1;
                        processing_bank0_busy <= 1'b0;
                        processing_bank1_busy <= 1'b0;
                        state <= ST_WAIT_ROW;
                    end
                endcase
            end
        end
    end

    assign o_ccl_overflow = capture_overflow || processing_overflow;
    // Simulation-visible compatibility aliases used by the pipeline diagnostics.
    wire [2:0] overflow_reason = capture_overflow ? 3'd1 :
                                 processing_overflow ? 3'd3 : 3'd0;
    wire [RUN_COUNT_WIDTH-1:0] curr_run_count = processing_run_count;

    // -------------------------------------------------------------------------
    // Draw the previous completed CCL result on the live raw stream.  Bounding
    // boxes inherently describe the preceding frame; framebuffer alignment is
    // deliberately outside this module.
    // -------------------------------------------------------------------------
    reg [PAIR_ADDR_WIDTH-1:0] raw_next_pair;
    reg [ROW_COUNT_WIDTH-1:0] raw_next_row;
    wire raw_line_start = i_raw_sof || i_raw_sol;
    wire [PAIR_ADDR_WIDTH-1:0] raw_pair = raw_line_start ?
        {PAIR_ADDR_WIDTH{1'b0}} : raw_next_pair;
    wire [ROW_COUNT_WIDTH-1:0] raw_row = i_raw_sof ?
        {ROW_COUNT_WIDTH{1'b0}} : raw_next_row;
    wire [11:0] raw_x0 = {raw_pair, 1'b0};
    wire [11:0] raw_x1 = raw_x0 + 1'b1;
    wire [11:0] raw_y = {{(12-ROW_COUNT_WIDTH){1'b0}}, raw_row};

    reg [3:0] display_object_count;
    reg [2:0] display_object_class [0:MAX_OBJECTS-1];
    reg [11:0] display_object_x_min [0:MAX_OBJECTS-1];
    reg [11:0] display_object_x_max [0:MAX_OBJECTS-1];
    reg [11:0] display_object_y_min [0:MAX_OBJECTS-1];
    reg [11:0] display_object_y_max [0:MAX_OBJECTS-1];
    integer display_index;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
            raw_next_row <= {ROW_COUNT_WIDTH{1'b0}};
            display_object_count <= 4'b0;
            for (display_index = 0; display_index < MAX_OBJECTS;
                 display_index = display_index + 1) begin
                display_object_class[display_index] <= SHAPE_UNKNOWN;
                display_object_x_min[display_index] <= 12'b0;
                display_object_x_max[display_index] <= 12'b0;
                display_object_y_min[display_index] <= 12'b0;
                display_object_y_max[display_index] <= 12'b0;
            end
        end else begin
            if (TRACK_ENABLE && i_track_clear)
                display_object_count <= 4'd0;
            else if (i_raw_sof) begin
                display_object_count <= o_object_count;
                for (display_index = 0; display_index < MAX_OBJECTS;
                     display_index = display_index + 1) begin
                    display_object_class[display_index] <= rendered_class[display_index*3 +: 3];
                    display_object_x_min[display_index] <= rendered_x0[display_index*12 +: 12];
                    display_object_x_max[display_index] <= rendered_x1[display_index*12 +: 12];
                    display_object_y_min[display_index] <= rendered_y0[display_index*12 +: 12];
                    display_object_y_max[display_index] <= rendered_y1[display_index*12 +: 12];
                end
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

    function [23:0] class_color;
        input [2:0] shape_class;
        begin
            case (shape_class)
                SHAPE_RECTANGLE: class_color = 24'h0000ff;
                SHAPE_TRIANGLE:  class_color = 24'h00ff00;
                SHAPE_CIRCLE:    class_color = 24'hff0000;
                SHAPE_ELLIPSE:   class_color = 24'hc0c000;
                SHAPE_TRAPEZOID: class_color = 24'h00ffff;
                default:         class_color = 24'h000000;
            endcase
        end
    endfunction

    function [2:0] class_tag;
        input [2:0] shape_class;
        begin
            case (shape_class)
                SHAPE_RECTANGLE: class_tag = 3'd4;
                SHAPE_TRIANGLE:  class_tag = 3'd5;
                SHAPE_CIRCLE:    class_tag = 3'd3;
                SHAPE_ELLIPSE:   class_tag = 3'd6;
                SHAPE_TRAPEZOID: class_tag = 3'd1;
                default:         class_tag = 3'd7;
            endcase
        end
    endfunction

    function roi_dash_pixel;
        input [11:0] x,y;
        reg [11:0] relative_x,relative_y;
        begin
            relative_x=x-ROI_X_MIN; relative_y=y-ROI_Y_MIN;
            roi_dash_pixel=x>=ROI_X_MIN && x<=ROI_X_MAX &&
                y>=ROI_Y_MIN && y<=ROI_Y_MAX &&
                (((y<ROI_Y_MIN+2 || y>ROI_Y_MAX-2) && !relative_x[4]) ||
                 ((x<ROI_X_MIN+2 || x>ROI_X_MAX-2) && !relative_y[4]));
        end
    endfunction

    function [7:0] label_char;
        input [2:0] shape_class;
        input [3:0] char_index;
        begin
            label_char=" ";
            case(shape_class)
                SHAPE_RECTANGLE: case(char_index)
                    0: label_char="R"; 1: label_char="E"; 2: label_char="C";
                    3: label_char="T"; 4: label_char="A"; 5: label_char="N";
                    6: label_char="G"; 7: label_char="L"; 8: label_char="E";
                endcase
                SHAPE_TRIANGLE: case(char_index)
                    0: label_char="T"; 1: label_char="R"; 2: label_char="I";
                    3: label_char="A"; 4: label_char="N"; 5: label_char="G";
                    6: label_char="L"; 7: label_char="E";
                endcase
                SHAPE_CIRCLE: case(char_index)
                    0: label_char="C"; 1: label_char="I"; 2: label_char="R";
                    3: label_char="C"; 4: label_char="L"; 5: label_char="E";
                endcase
                SHAPE_ELLIPSE: case(char_index)
                    0: label_char="E"; 1: label_char="L"; 2: label_char="L";
                    3: label_char="I"; 4: label_char="P"; 5: label_char="S";
                    6: label_char="E";
                endcase
                SHAPE_TRAPEZOID: case(char_index)
                    0: label_char="T"; 1: label_char="R"; 2: label_char="A";
                    3: label_char="P"; 4: label_char="E"; 5: label_char="Z";
                    6: label_char="O"; 7: label_char="I"; 8: label_char="D";
                endcase
            endcase
        end
    endfunction
    function [4:0] label_glyph;
        input [7:0] char_code;
        input [2:0] glyph_row;
        reg [34:0] rows;
        begin
            // Same 5x7 glyphs as the status OSD; only shape-name letters.
            case(char_code)
                "A": rows={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "C": rows={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "D": rows={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E": rows={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "G": rows={5'b01110,5'b10001,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110};
                "I": rows={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
                "L": rows={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "N": rows={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O": rows={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P": rows={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "R": rows={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S": rows={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T": rows={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "Z": rows={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b11111};
                default: rows=0;
            endcase
            label_glyph=rows[34-glyph_row*5 -: 5];
        end
    endfunction
    function label_pixel;
        input [2:0] shape_class;
        input [7:0] relative_x;
        input [3:0] relative_y;
        reg [4:0] glyph_bits;
        begin
            glyph_bits=label_glyph(label_char(shape_class,relative_x[7:4]),relative_y[3:1]);
            label_pixel=relative_x[3:0]<10 && glyph_bits[4-relative_x[3:1]];
        end
    endfunction

    integer overlay_index;
    reg [23:0] overlay_pixel0;
    reg [23:0] overlay_pixel1;
    reg [2:0] overlay_class;
    reg [11:0] overlay_x_min;
    reg [11:0] overlay_x_max;
    reg [11:0] overlay_y_min;
    reg [11:0] overlay_y_max;
    reg overlay_hit0;
    reg overlay_hit1;
    reg [7:0] label_width;
    reg [11:0] label_x,label_y;
    reg [2:0] label_class0,label_class1;
    reg [7:0] label_dx0,label_dx1;
    reg [3:0] label_dy0,label_dy1;
    always @(*) begin
        overlay_pixel0 = i_raw_rgb[47:24];
        overlay_pixel1 = i_raw_rgb[23:0];
        overlay_hit0 = 1'b0;
        overlay_hit1 = 1'b0;
        label_width=0; label_x=0; label_y=0;
        label_class0=SHAPE_UNKNOWN; label_class1=SHAPE_UNKNOWN;
        label_dx0=0; label_dx1=0; label_dy0=0; label_dy1=0;
        o_overlay_tag = 6'b0;
        if (i_roi_enable === 1'b1) begin
            if (roi_dash_pixel(raw_x0,raw_y)) begin
                o_overlay_tag[5:3] = 3'd6; overlay_pixel0 = 24'hc0c000;
            end
            if (roi_dash_pixel(raw_x1,raw_y)) begin
                o_overlay_tag[2:0] = 3'd6; overlay_pixel1 = 24'hc0c000;
            end
        end
        overlay_class = SHAPE_UNKNOWN;
        overlay_x_min = 12'b0;
        overlay_x_max = 12'b0;
        overlay_y_min = 12'b0;
        overlay_y_max = 12'b0;
        for (overlay_index = 0; overlay_index < MAX_OBJECTS;
             overlay_index = overlay_index + 1) begin
            if (!(TRACK_ENABLE && (i_track_clear || track_flush_pending)) &&
                overlay_index < (i_raw_sof ? o_object_count : display_object_count)) begin
                overlay_class = i_raw_sof ? rendered_class[overlay_index*3 +: 3] :
                                            display_object_class[overlay_index];
                overlay_x_min = i_raw_sof ? rendered_x0[overlay_index*12 +: 12] :
                                            display_object_x_min[overlay_index];
                overlay_x_max = i_raw_sof ? rendered_x1[overlay_index*12 +: 12] :
                                            display_object_x_max[overlay_index];
                overlay_y_min = i_raw_sof ? rendered_y0[overlay_index*12 +: 12] :
                                            display_object_y_min[overlay_index];
                overlay_y_max = i_raw_sof ? rendered_y1[overlay_index*12 +: 12] :
                                            display_object_y_max[overlay_index];

                label_width=(overlay_class==SHAPE_RECTANGLE || overlay_class==SHAPE_TRAPEZOID) ? 8'd144 :
                            (overlay_class==SHAPE_TRIANGLE) ? 8'd128 :
                            (overlay_class==SHAPE_ELLIPSE) ? 8'd112 : 8'd96;
                label_x=(overlay_x_max+12'd1>=label_width) ?
                         overlay_x_max+12'd1-label_width : 12'd0;
                label_y=(overlay_y_min>=16) ? overlay_y_min-12'd16 : overlay_y_min+12'd3;
                if(overlay_class>=SHAPE_RECTANGLE && overlay_class<=SHAPE_TRAPEZOID &&
                   raw_y>=label_y && raw_y<label_y+14) begin
                    // Select an object first; share one glyph lookup per lane.
                    if(raw_x0>=label_x && raw_x0<label_x+label_width) begin
                        label_class0=overlay_class; label_dx0=raw_x0-label_x;
                        label_dy0=raw_y-label_y;
                    end
                    if(raw_x1>=label_x && raw_x1<label_x+label_width) begin
                        label_class1=overlay_class; label_dx1=raw_x1-label_x;
                        label_dy1=raw_y-label_y;
                    end
                end

                overlay_hit0 =
                    (raw_x0 >= overlay_x_min) && (raw_x0 <= overlay_x_max) &&
                    (raw_y >= overlay_y_min) && (raw_y <= overlay_y_max) &&
                    (((raw_x0 - overlay_x_min) < BOX_THICKNESS) ||
                     ((overlay_x_max - raw_x0) < BOX_THICKNESS) ||
                     ((raw_y - overlay_y_min) < BOX_THICKNESS) ||
                     ((overlay_y_max - raw_y) < BOX_THICKNESS));
                overlay_hit1 =
                    (raw_x1 >= overlay_x_min) && (raw_x1 <= overlay_x_max) &&
                    (raw_y >= overlay_y_min) && (raw_y <= overlay_y_max) &&
                    (((raw_x1 - overlay_x_min) < BOX_THICKNESS) ||
                     ((overlay_x_max - raw_x1) < BOX_THICKNESS) ||
                     ((raw_y - overlay_y_min) < BOX_THICKNESS) ||
                     ((overlay_y_max - raw_y) < BOX_THICKNESS));
                if (overlay_hit0) begin
                    overlay_pixel0 = class_color(overlay_class);
                    o_overlay_tag[5:3] = class_tag(overlay_class);
                end
                if (overlay_hit1) begin
                    overlay_pixel1 = class_color(overlay_class);
                    o_overlay_tag[2:0] = class_tag(overlay_class);
                end
            end
        end
        if(label_pixel(label_class0,label_dx0,label_dy0)) begin
            overlay_pixel0=class_color(label_class0);
            o_overlay_tag[5:3]=class_tag(label_class0);
        end
        if(label_pixel(label_class1,label_dx1,label_dy1)) begin
            overlay_pixel1=class_color(label_class1);
            o_overlay_tag[2:0]=class_tag(label_class1);
        end
        o_overlay_rgb = {overlay_pixel0, overlay_pixel1};
    end

    assign o_overlay_valid = i_raw_valid;

endmodule
