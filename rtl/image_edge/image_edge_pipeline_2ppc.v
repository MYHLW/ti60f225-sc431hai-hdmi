module image_edge_pipeline_2ppc #(
    parameter integer IMAGE_WIDTH     = 1920,
    parameter integer IMAGE_HEIGHT    = 1080,
    parameter integer H_TOTAL_PAIRS   = 1100,
    parameter integer PAIR_ADDR_WIDTH = 10,
    parameter integer ROW_COUNT_WIDTH = 11,
    parameter integer FIFO_ADDR_WIDTH = 13,
    parameter [10:0] MIN_THRESHOLD = 11'd32,
    // 0: low=high/4, 1: low=3*high/8, 2: low=high/2.
    parameter [1:0] CANNY_LOW_RATIO = 2'd1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  i_mode,
    input  wire [2:0]  i_compare_left, i_compare_right,
    input  wire [10:0] i_threshold,
    input  wire        i_roi_enable,
    input  wire        i_inspection_enable,
    input  wire [4:0]  i_source_context,
    input  wire        i_vs,
    input  wire        i_hs,
    input  wire        i_de,
    input  wire [47:0] i_rgb,
    input  wire [47:0] i_display_rgb,

    output wire [3:0]  o_active_mode,
    output wire [2:0]  o_compare_left, o_compare_right,
    output wire [10:0] o_active_threshold,
    output wire [3:0]  o_object_count,
    output wire [4:0]  o_shape_mask,
    output wire        o_roi_active,
    output wire        o_ccl_limit,
    output wire        o_tracks_stale,
    output wire        o_inspection_active,
    output wire [1:0]  o_inspection_status,
    output wire [3:0]  o_inspection_mask,
    output wire [10:0] o_inspection_depth,
    output wire        o_inspection_hold,
    output wire [10:0] o_low_threshold,
    output wire [7:0]  o_overflow_count,
    output wire [7:0]  o_underflow_count,
    output wire        o_vs,
    output wire        o_hs,
    output wire        o_de,
    output wire [47:0] o_rgb,
    output wire        o_overflow,
    output wire        o_underflow
);

    reg input_de_d;
    reg input_vs_d;
    reg frame_pending;
    reg [3:0] processing_mode;
    reg roi_latched;
    reg inspection_latched;
    reg [4:0] context_latched;
    wire input_sol = i_de && !input_de_d;
    wire input_sof = input_sol && frame_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_de_d <= 1'b0;
            input_vs_d <= 1'b0;
            frame_pending <= 1'b0;
            processing_mode <= 4'd0;
            roi_latched <= 1'b0;
            inspection_latched <= 1'b0;
            context_latched <= 5'd0;
        end else begin
            input_de_d <= i_de;
            input_vs_d <= i_vs;
            if (i_vs && !input_vs_d)
                frame_pending <= 1'b1;
            else if (input_sof)
                frame_pending <= 1'b0;
            if (input_sof) begin
                processing_mode <= i_mode;
                roi_latched <= (i_roi_enable === 1'b1);
                inspection_latched <= (i_inspection_enable === 1'b1);
                context_latched <= i_source_context;
            end
        end
    end

    wire [3:0] input_processing_mode = input_sof ? i_mode : processing_mode;
    wire need_display_sobel = (input_processing_mode == 4'd1) || (input_processing_mode == 4'd6);
    wire need_canny = (input_processing_mode >= 4'd2) &&
                      (input_processing_mode <= 4'd7);
    wire need_color = input_processing_mode == 4'd7;
    wire need_post = (input_processing_mode == 4'd3) || (input_processing_mode == 4'd6);
    wire frame_inspection = input_sof ? (i_inspection_enable === 1'b1) : inspection_latched;
    wire need_inspection = input_processing_mode == 4'd4 && frame_inspection;
    wire need_shape = input_processing_mode == 4'd4 && !frame_inspection;
    wire frame_roi = input_sof ? (i_roi_enable === 1'b1) : roi_latched;
    wire track_clear = !need_shape || (input_sof &&
        ((frame_roi != roi_latched) || (i_source_context != context_latched)));
    assign o_roi_active = roi_latched || (inspection_latched && processing_mode==4'd4);
    assign o_inspection_active = inspection_latched && processing_mode==4'd4;

    wire gray_sof, gray_sol, gray_valid;
    wire [15:0] gray_data;
    rgb2gray_2ppc gray_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(input_sof), .i_sol(input_sol),
        .i_valid(i_de), .i_rgb(i_rgb),
        .o_sof(gray_sof), .o_sol(gray_sol), .o_valid(gray_valid), .o_gray(gray_data)
    );

    // Preserve the original Y samples and timing; carry two 8-bit difference
    // chroma channels in the same line-buffer controllers, not three Cannys.
    function [15:0] difference_chroma;
        input [23:0] rgb;
        reg [8:0] u,v;
        begin
            u={1'b0,rgb[23:16]}-{1'b0,rgb[15:8]}+9'd256;
            v={1'b0,rgb[7:0]}-{1'b0,rgb[15:8]}+9'd256;
            difference_chroma={u[8:1],v[8:1]};
        end
    endfunction
    reg [31:0] chroma_delay0,chroma_delay1,chroma_delay2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin chroma_delay0<=0;chroma_delay1<=0;chroma_delay2<=0; end
        else begin
            chroma_delay0<={difference_chroma(i_rgb[47:24]),difference_chroma(i_rgb[23:0])};
            chroma_delay1<=chroma_delay0; chroma_delay2<=chroma_delay1;
        end
    end
    wire window_sof, window_sol, window_valid;
    wire [1:0] window_border;
    wire [71:0] window0, window1;
    wire [71:0] u_window0,u_window1,v_window0,v_window1;
    wire [215:0] feature_window0,feature_window1;
    window_3x3_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH), .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH),
        .PIXEL_WIDTH(24)
    ) window_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(gray_sof), .i_sol(gray_sol), .i_valid(gray_valid),
        .i_gray({gray_data[15:8],chroma_delay2[31:16],gray_data[7:0],chroma_delay2[15:0]}),
        .o_sof(window_sof), .o_sol(window_sol), .o_valid(window_valid),
        .o_border(window_border), .o_window0(feature_window0), .o_window1(feature_window1)
    );
    genvar tap;
    generate for(tap=0;tap<9;tap=tap+1) begin: feature_taps
        assign window0[tap*8 +: 8]=feature_window0[tap*24+16 +: 8];
        assign window1[tap*8 +: 8]=feature_window1[tap*24+16 +: 8];
        assign u_window0[tap*8 +: 8]=feature_window0[tap*24+8 +: 8];
        assign u_window1[tap*8 +: 8]=feature_window1[tap*24+8 +: 8];
        assign v_window0[tap*8 +: 8]=feature_window0[tap*24 +: 8];
        assign v_window1[tap*8 +: 8]=feature_window1[tap*24 +: 8];
    end endgenerate

    wire edge_sof, edge_sol, edge_valid;
    wire [15:0] edge_binary;
    reg [10:0] active_threshold;
    reg [10:0] active_low_threshold;

    function [10:0] low_threshold_from_high;
        input [10:0] high_threshold;
        reg [12:0] high_x3;
        begin
            high_x3 = {2'b0, high_threshold} +
                      {1'b0, high_threshold, 1'b0};
            case (CANNY_LOW_RATIO)
                2'd0: low_threshold_from_high = high_threshold >> 2;
                2'd2: low_threshold_from_high = high_threshold >> 1;
                default: low_threshold_from_high = high_x3 >> 3;
            endcase
        end
    endfunction

    wire [10:0] requested_high_threshold =
        (i_threshold < MIN_THRESHOLD) ? MIN_THRESHOLD : i_threshold;
    wire [10:0] requested_low_threshold =
        low_threshold_from_high(requested_high_threshold);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_threshold <= 11'd192;
            active_low_threshold <= 11'd72;
        end else if (input_sof) begin
            active_threshold <= requested_high_threshold;
            active_low_threshold <= requested_low_threshold;
        end
    end
    assign o_active_threshold = active_threshold;
    assign o_low_threshold = active_low_threshold;

    sobel_3x3_2ppc sobel_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(window_sof), .i_sol(window_sol),
        .i_valid(window_valid && need_display_sobel),
        .i_border(window_border), .i_window0(window0), .i_window1(window1),
        .i_threshold(active_threshold),
        .o_sof(edge_sof), .o_sol(edge_sol), .o_valid(edge_valid),
        .o_border(),
        .o_gx0(), .o_gy0(), .o_gx1(), .o_gy1(),
        .o_magnitude(), .o_binary(edge_binary)
    );

    wire median_sof, median_sol, median_valid;
    wire [1:0] median_border;
    wire [15:0] median_data;
    gaussian_3x3_2ppc gaussian_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(window_sof), .i_sol(window_sol),
        .i_valid(window_valid && need_canny),
        .i_border(window_border), .i_window0(window0), .i_window1(window1),
        .o_sof(median_sof), .o_sol(median_sol), .o_valid(median_valid),
        .o_border(median_border), .o_gray(median_data)
    );

    wire [15:0] u_filtered,v_filtered;
    gaussian_3x3_2ppc u_gaussian_core (
        .clk(clk),.rst_n(rst_n),.i_sof(window_sof),.i_sol(window_sol),
        .i_valid(window_valid && need_color),.i_border(window_border),
        .i_window0(u_window0),.i_window1(u_window1),.o_gray(u_filtered)
    );
    gaussian_3x3_2ppc v_gaussian_core (
        .clk(clk),.rst_n(rst_n),.i_sof(window_sof),.i_sol(window_sol),
        .i_valid(window_valid && need_color),.i_border(window_border),
        .i_window0(v_window0),.i_window1(v_window1),.o_gray(v_filtered)
    );
    wire median_window_sof, median_window_sol, median_window_valid;
    wire [1:0] median_window_border;
    wire [71:0] median_window0, median_window1;
    wire [215:0] filtered_feature_window0,filtered_feature_window1;
    wire [71:0] filtered_u_window0,filtered_u_window1,filtered_v_window0,filtered_v_window1;
    window_3x3_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH), .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH),
        .PIXEL_WIDTH(24)
    ) median_window_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(median_sof), .i_sol(median_sol),
        .i_valid(median_valid && need_canny),
        .i_gray({median_data[15:8],u_filtered[15:8],v_filtered[15:8],
                 median_data[7:0],u_filtered[7:0],v_filtered[7:0]}),
        .o_sof(median_window_sof), .o_sol(median_window_sol), .o_valid(median_window_valid),
        .o_border(median_window_border), .o_window0(filtered_feature_window0), .o_window1(filtered_feature_window1)
    );
    generate for(tap=0;tap<9;tap=tap+1) begin: filtered_feature_taps
        assign median_window0[tap*8 +: 8]=filtered_feature_window0[tap*24+16 +: 8];
        assign median_window1[tap*8 +: 8]=filtered_feature_window1[tap*24+16 +: 8];
        assign filtered_u_window0[tap*8 +: 8]=filtered_feature_window0[tap*24+8 +: 8];
        assign filtered_u_window1[tap*8 +: 8]=filtered_feature_window1[tap*24+8 +: 8];
        assign filtered_v_window0[tap*8 +: 8]=filtered_feature_window0[tap*24 +: 8];
        assign filtered_v_window1[tap*8 +: 8]=filtered_feature_window1[tap*24 +: 8];
    end endgenerate

    wire median_edge_sof, median_edge_sol, median_edge_valid;
    wire [1:0] median_edge_border;
    wire signed [11:0] median_edge_gx0, median_edge_gy0;
    wire signed [11:0] median_edge_gx1, median_edge_gy1;
    wire [21:0] median_edge_magnitude;
    wire [15:0] median_edge_binary;
    sobel_3x3_2ppc median_sobel_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(median_window_sof), .i_sol(median_window_sol),
        .i_valid(median_window_valid && need_canny),
        .i_border(median_window_border), .i_window0(median_window0), .i_window1(median_window1),
        .i_threshold(active_threshold),
        .o_sof(median_edge_sof), .o_sol(median_edge_sol), .o_valid(median_edge_valid),
        .o_border(median_edge_border),
        .o_gx0(median_edge_gx0), .o_gy0(median_edge_gy0),
        .o_gx1(median_edge_gx1), .o_gy1(median_edge_gy1),
        .o_magnitude(median_edge_magnitude), .o_binary(median_edge_binary)
    );

    wire signed [11:0] u_gx0,u_gy0,u_gx1,u_gy1,v_gx0,v_gy0,v_gx1,v_gy1;
    sobel_3x3_2ppc u_sobel_core (
        .clk(clk),.rst_n(rst_n),.i_sof(median_window_sof),.i_sol(median_window_sol),
        .i_valid(median_window_valid && need_color),.i_border(median_window_border),
        .i_window0(filtered_u_window0),.i_window1(filtered_u_window1),.i_threshold(active_threshold),
        .o_gx0(u_gx0),.o_gy0(u_gy0),.o_gx1(u_gx1),.o_gy1(u_gy1)
    );
    sobel_3x3_2ppc v_sobel_core (
        .clk(clk),.rst_n(rst_n),.i_sof(median_window_sof),.i_sol(median_window_sol),
        .i_valid(median_window_valid && need_color),.i_border(median_window_border),
        .i_window0(filtered_v_window0),.i_window1(filtered_v_window1),.i_threshold(active_threshold),
        .o_gx0(v_gx0),.o_gy0(v_gy0),.o_gx1(v_gx1),.o_gy1(v_gy1)
    );
    wire color_valid;
    wire [21:0] color_magnitude;
    wire signed [11:0] color_gx0,color_gy0,color_gx1,color_gy1;
    color_gradient_tensor_pixel color_lane0 (
        .clk(clk),.rst_n(rst_n),.i_valid(median_edge_valid && need_color),
        .i_gx({median_edge_gx0[10:0],u_gx0[10:0],v_gx0[10:0]}),
        .i_gy({median_edge_gy0[10:0],u_gy0[10:0],v_gy0[10:0]}),
        .o_valid(color_valid),.o_magnitude(color_magnitude[21:11]),.o_gx(color_gx0),.o_gy(color_gy0)
    );
    color_gradient_tensor_pixel color_lane1 (
        .clk(clk),.rst_n(rst_n),.i_valid(median_edge_valid && need_color),
        .i_gx({median_edge_gx1[10:0],u_gx1[10:0],v_gx1[10:0]}),
        .i_gy({median_edge_gy1[10:0],u_gy1[10:0],v_gy1[10:0]}),
        .o_valid(),.o_magnitude(color_magnitude[10:0]),.o_gx(color_gx1),.o_gy(color_gy1)
    );
    reg [3:0] color_control [0:5];
    integer color_stage;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(color_stage=0;color_stage<6;color_stage=color_stage+1) color_control[color_stage]<=4'b0011;
        end else begin
            color_control[0]<={median_edge_sof,median_edge_sol,median_edge_border};
            for(color_stage=1;color_stage<6;color_stage=color_stage+1)
                color_control[color_stage]<=color_control[color_stage-1];
        end
    end
    wire canny_sof, canny_sol, canny_valid;
    wire [1:0] canny_border;
    wire [15:0] canny_binary;
    wire [3:0] canny_direction;
    wire [1:0] canny_relaxed_candidate;
    canny_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH), .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH)
    ) canny_core (
        .clk(clk), .rst_n(rst_n),
        .i_sof(need_color ? color_control[5][3]:median_edge_sof),
        .i_sol(need_color ? color_control[5][2]:median_edge_sol),
        .i_valid(need_color ? color_valid:median_edge_valid),
        .i_border(need_color ? color_control[5][1:0]:median_edge_border),
        .i_gx0(need_color ? color_gx0:median_edge_gx0), .i_gy0(need_color ? color_gy0:median_edge_gy0),
        .i_gx1(need_color ? color_gx1:median_edge_gx1), .i_gy1(need_color ? color_gy1:median_edge_gy1),
        .i_magnitude(need_color ? color_magnitude:median_edge_magnitude),
        .i_high_threshold(active_threshold),
        .i_low_threshold(active_low_threshold),
        .o_sof(canny_sof), .o_sol(canny_sol), .o_valid(canny_valid),
        .o_border(canny_border), .o_binary(canny_binary),
        .o_direction(canny_direction),
        .o_relaxed_candidate(canny_relaxed_candidate)
    );

    wire [47:0] gray_rgb = {
        gray_data[15:8], gray_data[15:8], gray_data[15:8],
        gray_data[7:0],  gray_data[7:0],  gray_data[7:0]
    };
    wire [47:0] edge_rgb = {
        edge_binary[15:8], edge_binary[15:8], edge_binary[15:8],
        edge_binary[7:0],  edge_binary[7:0],  edge_binary[7:0]
    };
    reg [PAIR_ADDR_WIDTH-1:0] median_next_pair;
    reg [ROW_COUNT_WIDTH-1:0] median_next_row;
    wire [PAIR_ADDR_WIDTH-1:0] median_current_pair =
        (median_edge_sof || median_edge_sol) ? {PAIR_ADDR_WIDTH{1'b0}} : median_next_pair;
    wire [ROW_COUNT_WIDTH-1:0] median_current_row =
        median_edge_sof ? {ROW_COUNT_WIDTH{1'b0}} : median_next_row;
    wire median_guard_border = (median_current_pair == 0) ||
                               (median_current_pair == (IMAGE_WIDTH / 2) - 1) ||
                               (median_current_row < 2) ||
                               (median_current_row >= IMAGE_HEIGHT - 2);
    wire [15:0] median_edge_binary_guarded = median_guard_border ? 16'b0 : median_edge_binary;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            median_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
            median_next_row <= {ROW_COUNT_WIDTH{1'b0}};
        end else if (median_edge_valid) begin
            if (median_current_pair == (IMAGE_WIDTH / 2) - 1) begin
                median_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
                median_next_row <= median_current_row + 1'b1;
            end else begin
                median_next_pair <= median_current_pair + 1'b1;
                median_next_row <= median_current_row;
            end
        end
    end

    wire [47:0] median_edge_rgb = {
        median_edge_binary_guarded[15:8], median_edge_binary_guarded[15:8], median_edge_binary_guarded[15:8],
        median_edge_binary_guarded[7:0],  median_edge_binary_guarded[7:0],  median_edge_binary_guarded[7:0]
    };

    reg [PAIR_ADDR_WIDTH-1:0] canny_next_pair;
    reg [ROW_COUNT_WIDTH-1:0] canny_next_row;
    wire [PAIR_ADDR_WIDTH-1:0] canny_current_pair =
        (canny_sof || canny_sol) ? {PAIR_ADDR_WIDTH{1'b0}} : canny_next_pair;
    wire [ROW_COUNT_WIDTH-1:0] canny_current_row =
        canny_sof ? {ROW_COUNT_WIDTH{1'b0}} : canny_next_row;
    wire canny_guard_border = (canny_current_pair < 2) ||
                              (canny_current_pair >= (IMAGE_WIDTH / 2) - 2) ||
                              (canny_current_row < 4) ||
                              (canny_current_row >= IMAGE_HEIGHT - 4);
    wire [15:0] canny_binary_guarded = canny_guard_border ? 16'b0 : canny_binary;
    wire [3:0] canny_direction_guarded = canny_guard_border ? 4'b0 : canny_direction;
    wire [1:0] canny_relaxed_candidate_guarded =
        canny_guard_border ? 2'b0 : canny_relaxed_candidate;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            canny_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
            canny_next_row <= {ROW_COUNT_WIDTH{1'b0}};
        end else if (canny_valid) begin
            if (canny_current_pair == (IMAGE_WIDTH / 2) - 1) begin
                canny_next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
                canny_next_row <= canny_current_row + 1'b1;
            end else begin
                canny_next_pair <= canny_current_pair + 1'b1;
                canny_next_row <= canny_current_row;
            end
        end
    end

    wire [47:0] canny_rgb = {
        canny_binary_guarded[15:8], canny_binary_guarded[15:8], canny_binary_guarded[15:8],
        canny_binary_guarded[7:0],  canny_binary_guarded[7:0],  canny_binary_guarded[7:0]
    };

    wire post_sof, post_sol, post_valid;
    wire [1:0] post_border;
    wire [15:0] post_binary;
    wire [15:0] post_core_binary;
    wire [3:0] post_direction;
    edge_post_process_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH), .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH)
    ) edge_post_process (
        .clk(clk), .rst_n(rst_n),
        .i_sof(canny_sof), .i_sol(canny_sol),
        .i_valid(canny_valid && need_post),
        .i_binary(need_post ? canny_binary_guarded : 16'b0),
        .i_direction(need_post ? canny_direction_guarded : 4'b0),
        .i_relaxed_candidate(need_post ? canny_relaxed_candidate_guarded : 2'b0),
        .o_sof(post_sof), .o_sol(post_sol), .o_valid(post_valid),
        .o_border(post_border), .o_binary(post_binary),
        .o_core_binary(post_core_binary),
        .o_direction(post_direction)
    );

    // The legacy HDMI top swaps R/B: 0000c0 appears red, 00c000 green.
    // Red marks the aligned baseline Canny result. Green marks only pixels
    // added by relaxed weak linking or directional one-pixel gap repair.
    wire [23:0] post_pixel0 = (|post_core_binary[15:8]) ? 24'h0000c0 :
                                (|post_binary[15:8])      ? 24'h00c000 : 24'b0;
    wire [23:0] post_pixel1 = (|post_core_binary[7:0]) ? 24'h0000c0 :
                                (|post_binary[7:0])      ? 24'h00c000 : 24'b0;
    wire [47:0] post_rgb = {post_pixel0, post_pixel1};

    wire ccl_edge_sof, ccl_edge_sol, ccl_edge_valid;
    wire [15:0] ccl_edge_binary;
    wire [3:0] ccl_edge_direction;
    wire [1:0] ccl_edge_direction_valid;
    ccl_edge_conditioner_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH), .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH)
    ) ccl_edge_conditioner (
        .clk(clk), .rst_n(rst_n),
        .i_sof(canny_sof), .i_sol(canny_sol),
        .i_valid(canny_valid && need_shape),
        .i_binary(need_shape ? canny_binary_guarded : 16'b0),
        .i_direction(need_shape ? canny_direction : 4'b0),
        .o_sof(ccl_edge_sof), .o_sol(ccl_edge_sol), .o_valid(ccl_edge_valid),
        .o_binary(ccl_edge_binary), .o_direction(ccl_edge_direction),
        .o_direction_valid(ccl_edge_direction_valid)
    );

    wire shape_valid;
    wire [47:0] shape_rgb;
    wire [5:0] shape_tag;
    wire ccl_overflow;
    ccl_shape_recognizer_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PAIR_ADDR_WIDTH(PAIR_ADDR_WIDTH), .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH),
        .MAX_RUNS_PER_ROW(24), .MAX_LABELS(12), .MAX_OBJECTS(4), .TRACK_ENABLE(1)
    ) shape_core (
        .clk(clk), .rst_n(rst_n),
        .i_roi_enable(frame_roi), .i_track_clear(track_clear),
        .i_canny_sof(ccl_edge_sof), .i_canny_sol(ccl_edge_sol),
        .i_canny_valid(ccl_edge_valid), .i_canny_binary(ccl_edge_binary),
        .i_edge_direction(ccl_edge_direction),
        .i_direction_valid(ccl_edge_direction_valid),
        .i_raw_sof(input_sof && need_shape), .i_raw_sol(input_sol && need_shape),
        .i_raw_valid(i_de && need_shape), .i_raw_rgb(need_shape ? i_display_rgb : 48'b0),
        .o_overlay_valid(shape_valid), .o_overlay_rgb(shape_rgb),
        .o_overlay_tag(shape_tag),
        .o_object_count(o_object_count), .o_shape_mask(o_shape_mask),
        .o_tracks_stale(o_tracks_stale),
        .o_ccl_overflow(ccl_overflow)
    );

    wire video_overflow;
    wire inspection_valid;
    wire [5:0] inspection_tag;
    wire inspection_clear = !need_inspection || (input_sof &&
        ((frame_inspection != inspection_latched) ||
         (i_source_context != context_latched) ||
         (requested_high_threshold != active_threshold)));
    rect_inspector_2ppc #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) rectangle_inspector (
        .clk(clk), .rst_n(rst_n), .i_enable(need_inspection), .i_clear(inspection_clear),
        .i_sof(canny_sof), .i_sol(canny_sol), .i_valid(canny_valid),
        .i_binary(canny_binary_guarded),
        .i_raw_sof(input_sof), .i_raw_sol(input_sol), .i_raw_valid(i_de && need_inspection),
        .o_overlay_valid(inspection_valid), .o_overlay_tag(inspection_tag),
        .o_status(o_inspection_status), .o_defect_mask(o_inspection_mask),
        .o_max_depth(o_inspection_depth), .o_hold(o_inspection_hold)
    );

    video_mode_buffer_2ppc #(
        .H_TOTAL_PAIRS(H_TOTAL_PAIRS),
        .ACTIVE_PAIRS(IMAGE_WIDTH / 2),
        .SYNC_LINE_DELAY(7),
        .SYNC_EXTRA_CLOCKS(32),
        .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) output_buffer (
        .clk(clk), .rst_n(rst_n),
        .i_mode(i_mode), .i_input_sof(input_sof),
        .i_compare_left(i_compare_left), .i_compare_right(i_compare_right),
        .i_timing_vs(i_vs), .i_timing_hs(i_hs), .i_timing_de(i_de),
        .i_raw_valid(i_de), .i_raw_rgb(i_display_rgb),
        .i_gray_valid(gray_valid), .i_gray_rgb(gray_rgb),
        .i_edge_valid(edge_valid), .i_edge_rgb(edge_rgb),
        .i_canny_valid(canny_valid), .i_canny_rgb(canny_rgb),
        .i_post_valid(post_valid), .i_post_rgb(post_rgb),
        .i_post_sof(post_sof), .i_post_sol(post_sol), .i_post_core(post_core_binary),
        .i_shape_valid(need_inspection ? inspection_valid : shape_valid), .i_shape_rgb(shape_rgb),
        .i_shape_tag(need_inspection ? inspection_tag : shape_tag),
        .o_active_mode(o_active_mode),
        .o_compare_left(o_compare_left), .o_compare_right(o_compare_right),
        .o_vs(o_vs), .o_hs(o_hs), .o_de(o_de), .o_rgb(o_rgb),
        .o_overflow(video_overflow), .o_underflow(o_underflow),
        .o_overflow_count(o_overflow_count), .o_underflow_count(o_underflow_count)
    );

    // CCL capacity overflow now aborts only that recognition frame and falls
    // back to raw video.  Keep it separate from the HDMI FIFO diagnostic so
    // led[3] reports faults that can actually disturb the displayed raster.
    assign o_overflow = video_overflow;
    reg limit_latched;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) limit_latched <= 1'b0;
        else if (!need_shape) limit_latched <= 1'b0;
        else if (ccl_edge_sof) limit_latched <= ccl_overflow;
        else if (ccl_overflow) limit_latched <= 1'b1;
    assign o_ccl_limit = limit_latched;
endmodule
