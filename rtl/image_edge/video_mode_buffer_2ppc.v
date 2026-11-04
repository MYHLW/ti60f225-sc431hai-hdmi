module video_mode_buffer_2ppc #(
    parameter integer H_TOTAL_PAIRS   = 1100,
    parameter integer ACTIVE_PAIRS    = 960,
    parameter integer SYNC_LINE_DELAY = 2,
    parameter integer SYNC_EXTRA_CLOCKS = 32,
    parameter integer FIFO_ADDR_WIDTH = 13
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  i_mode,
    input  wire [2:0]  i_compare_left, i_compare_right,
    input  wire        i_input_sof,
    input  wire        i_timing_vs,
    input  wire        i_timing_hs,
    input  wire        i_timing_de,
    input  wire        i_raw_valid,
    input  wire [47:0] i_raw_rgb,
    input  wire        i_gray_valid,
    input  wire [47:0] i_gray_rgb,
    input  wire        i_edge_valid,
    input  wire [47:0] i_edge_rgb,
    input  wire        i_canny_valid,
    input  wire [47:0] i_canny_rgb,
    input  wire        i_post_valid,
    input  wire [47:0] i_post_rgb,
    input  wire        i_post_sof, i_post_sol,
    input  wire [15:0] i_post_core,
    input  wire        i_shape_valid,
    input  wire [47:0] i_shape_rgb,
    input  wire [5:0]  i_shape_tag,

    output reg  [3:0]  o_active_mode,
    output reg  [2:0]  o_compare_left, o_compare_right,
    output reg         o_vs,
    output reg         o_hs,
    output reg         o_de,
    output reg  [47:0] o_rgb,
    output reg         o_overflow,
    output reg         o_underflow,
    output reg  [7:0]  o_overflow_count,
    output reg  [7:0]  o_underflow_count
);

    localparam integer SYNC_DELAY_CLOCKS = H_TOTAL_PAIRS * SYNC_LINE_DELAY + SYNC_EXTRA_CLOCKS;
    localparam integer SYNC_ADDR_WIDTH = (SYNC_DELAY_CLOCKS <= 1) ? 1 : $clog2(SYNC_DELAY_CLOCKS);
    wire [3:0] selected_mode = i_input_sof ? i_mode : o_active_mode;
    reg selected_valid;
    reg [5:0] selected_tag;

    // Compare mode reuses the aligned Canny/BOOST pair. Only Sobel's two
    // binary lanes need a narrow FIFO; RGB timing RAM keeps its original width.
    reg [FIFO_ADDR_WIDTH-1:0] compare_wr_ptr, compare_rd_ptr;
    wire compare_empty = compare_wr_ptr == compare_rd_ptr;
    wire compare_full = (compare_wr_ptr + 1'b1) == compare_rd_ptr;
    wire compare_read = selected_mode == 4'd6 && i_post_valid && !compare_empty;
    wire compare_write = selected_mode == 4'd6 && i_edge_valid &&
                         (!compare_full || compare_read);
    wire [1:0] compare_sobel;
    true_dual_port_ram #(
        .DATA_WIDTH(2), .ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .WRITE_MODE_1("READ_FIRST"), .WRITE_MODE_2("READ_FIRST"),
        .OUTPUT_REG_1("FALSE"), .OUTPUT_REG_2("FALSE"), .RAM_INIT_FILE("")
    ) compare_sobel_ram (
        .we1(compare_write), .we2(1'b0), .clka(clk), .clkb(clk),
        .din1({|i_edge_rgb[47:24], |i_edge_rgb[23:0]}), .din2(2'b0),
        .addr1(compare_wr_ptr), .addr2(compare_rd_ptr),
        .dout1(), .dout2(compare_sobel)
    );
    localparam integer PAIR_COUNT_WIDTH = (ACTIVE_PAIRS <= 1) ? 1 : $clog2(ACTIVE_PAIRS);
    reg [PAIR_COUNT_WIDTH-1:0] compare_pair;
    wire [PAIR_COUNT_WIDTH-1:0] compare_current_pair =
        (i_post_sof || i_post_sol) ? {PAIR_COUNT_WIDTH{1'b0}} : compare_pair;
    reg compare_valid_d, compare_read_d, compare_right_d;
    reg [47:0] compare_post_d;
    reg [15:0] compare_core_d;
    wire [2:0] compare_algorithm = compare_right_d ? o_compare_right : o_compare_left;
    function [2:0] compare_tag;
        input [2:0] algorithm;
        input sobel, canny;
        input [23:0] post;
        begin
            case (algorithm)
                3'd1: compare_tag = sobel ? 3'd3 : 3'd7;
                3'd2: compare_tag = canny ? 3'd3 : 3'd7;
                3'd3: compare_tag = post == 24'h0000c0 ? 3'd1 :
                                   post == 24'h00c000 ? 3'd2 : 3'd7;
                3'd5: compare_tag = canny ? 3'd4 : 3'd0;
                default: compare_tag = 3'd0;
            endcase
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compare_wr_ptr<=0; compare_rd_ptr<=0; compare_pair<=0;
            compare_valid_d<=0; compare_read_d<=0; compare_right_d<=0;
            compare_post_d<=0; compare_core_d<=0;
            o_compare_left<=2; o_compare_right<=3;
        end else begin
            if (i_input_sof) begin
                compare_wr_ptr<=0; compare_rd_ptr<=0; compare_pair<=0;
                o_compare_left<=i_compare_left; o_compare_right<=i_compare_right;
            end else begin
                if (compare_write) compare_wr_ptr<=compare_wr_ptr+1'b1;
                if (compare_read) compare_rd_ptr<=compare_rd_ptr+1'b1;
            end
            compare_valid_d<=selected_mode==4'd6 && i_post_valid;
            compare_read_d<=compare_read;
            compare_post_d<=i_post_rgb;
            compare_core_d<=i_post_core;
            compare_right_d<=compare_current_pair >= ACTIVE_PAIRS/2;
            if (selected_mode==4'd6 && i_post_valid)
                compare_pair <= compare_current_pair == ACTIVE_PAIRS-1 ?
                                {PAIR_COUNT_WIDTH{1'b0}} : compare_current_pair+1'b1;
        end
    end

    always @(*) begin
        case (selected_mode)
            4'd6: begin
                selected_valid = compare_valid_d;
                selected_tag = {
                    compare_tag(compare_algorithm, compare_read_d && compare_sobel[1],
                                |compare_core_d[15:8], compare_post_d[47:24]),
                    compare_tag(compare_algorithm, compare_read_d && compare_sobel[0],
                                |compare_core_d[7:0], compare_post_d[23:0])
                };
            end
            4'd1: begin
                selected_valid = i_edge_valid;
                selected_tag = {2'b0, |i_edge_rgb[47:24], 2'b0, |i_edge_rgb[23:0]};
            end
            4'd2,4'd7: begin
                selected_valid = i_canny_valid;
                selected_tag = {2'b0, |i_canny_rgb[47:24], 2'b0, |i_canny_rgb[23:0]};
            end
            4'd3: begin
                selected_valid = i_post_valid;
                selected_tag = {(i_post_rgb[47:24] == 24'h0000c0) ? 3'd1 :
                                 (i_post_rgb[47:24] == 24'h00c000) ? 3'd2 : 3'd0,
                                (i_post_rgb[23:0] == 24'h0000c0) ? 3'd1 :
                                 (i_post_rgb[23:0] == 24'h00c000) ? 3'd2 : 3'd0};
            end
            4'd4: begin
                selected_valid = i_shape_valid;
                selected_tag = i_shape_tag;
            end
            4'd5: begin
                selected_valid = i_canny_valid;
                selected_tag = {2'b0, |i_canny_rgb[47:24], 2'b0, |i_canny_rgb[23:0]};
            end
            default: begin
                selected_valid = i_raw_valid;
                selected_tag = 6'b0;
            end
        endcase
    end

    reg [SYNC_ADDR_WIDTH-1:0] sync_addr;
    reg [SYNC_ADDR_WIDTH:0] sync_fill_count;
    reg sync_primed;
    // Delay display RGB with the raster timing.  Mode 5 combines this aligned
    // image with the Canny mask read from pixel_fifo_ram.
    wire [54:0] delayed_video;
    wire [3:0] delayed_mode = delayed_video[54:51];
    wire [2:0] delayed_timing = delayed_video[50:48];
    wire [47:0] delayed_raw_rgb = delayed_video[47:0];

    true_dual_port_ram #(
        .DATA_WIDTH(55),
        .ADDR_WIDTH(SYNC_ADDR_WIDTH),
        .WRITE_MODE_1("READ_FIRST"),
        .WRITE_MODE_2("READ_FIRST"),
        .OUTPUT_REG_1("FALSE"),
        .OUTPUT_REG_2("FALSE"),
        .RAM_INIT_FILE("")
    ) timing_delay_ram (
        .we1(1'b1), .we2(1'b0),
        .clka(clk), .clkb(clk),
        .din1({selected_mode, i_timing_vs, i_timing_hs, i_timing_de, i_raw_rgb}),
        .din2(55'b0),
        .addr1(sync_addr), .addr2({SYNC_ADDR_WIDTH{1'b0}}),
        .dout1(delayed_video), .dout2()
    );

    reg [FIFO_ADDR_WIDTH-1:0] fifo_wr_ptr;
    reg [FIFO_ADDR_WIDTH-1:0] fifo_rd_ptr;
    wire fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
    wire fifo_full = ((fifo_wr_ptr + 1'b1) == fifo_rd_ptr);
    wire read_request = sync_primed && delayed_timing[0];
    wire read_enable = read_request && !fifo_empty;
    wire write_enable = selected_valid && (!fifo_full || read_enable);
    wire [5:0] fifo_read_data;

    true_dual_port_ram #(
        .DATA_WIDTH(6),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .WRITE_MODE_1("READ_FIRST"),
        .WRITE_MODE_2("READ_FIRST"),
        .OUTPUT_REG_1("FALSE"),
        .OUTPUT_REG_2("FALSE"),
        .RAM_INIT_FILE("")
    ) pixel_fifo_ram (
        .we1(write_enable), .we2(1'b0),
        .clka(clk), .clkb(clk),
        .din1(selected_tag), .din2(6'b0),
        .addr1(fifo_wr_ptr), .addr2(fifo_rd_ptr),
        .dout1(), .dout2(fifo_read_data)
    );

    reg read_enable_d;
    reg overflow_event_d, underflow_event_d;
    wire overflow_event = (selected_valid && fifo_full && !read_enable) ||
                          (selected_mode==4'd6 && i_edge_valid && compare_full && !compare_read);
    wire underflow_event = (read_request && fifo_empty) ||
                           (selected_mode==4'd6 && i_post_valid && compare_empty);
    reg [3:0] output_mode_r;
    reg output_vs_r;
    reg output_hs_r;
    reg output_de_r;
    reg [47:0] delayed_raw_rgb_r;
    wire [5:0] safe_fifo_tag = read_enable_d ? fifo_read_data : 6'b0;
    // Only render labels are queued. RAW/SHAPE backgrounds use the same RGB
    // raster delay as OVRLY; FIFO depth and read/write timing are unchanged.
    function [23:0] render_tag;
        input [2:0] tag;
        input [23:0] background;
        input [3:0] mode;
        begin
            case (tag)
                3'd1: render_tag = (mode==4'd4) ? 24'h00ffff : 24'h0000c0;
                3'd2: render_tag = 24'h00c000;
                3'd3: render_tag = mode == 4'd6 ? 24'hffffff : 24'hff0000;
                3'd4: render_tag = 24'h0000ff;
                3'd5: render_tag = 24'h00ff00;
                3'd6: render_tag = 24'hc0c000;
                3'd7: render_tag = 24'b0;
                default: render_tag = background;
            endcase
        end
    endfunction
    // The legacy HDMI top swaps R/B at the encoder. 0000ff here is red on screen.
    // Sobel/Canny render white; OVRLY and BOOST retain their existing colors.
    // In compare mode tag 3 is white, while SHAPE keeps its blue circle tag.
    wire [23:0] full_edge_pixel0 = (|safe_fifo_tag[5:3]) ? 24'hffffff : 24'b0;
    wire [23:0] full_edge_pixel1 = (|safe_fifo_tag[2:0]) ? 24'hffffff : 24'b0;
    wire [47:0] full_edge_rgb = {full_edge_pixel0, full_edge_pixel1};
    wire [23:0] overlay_pixel0 = (|safe_fifo_tag[5:3]) ?
                                  24'h0000ff : delayed_raw_rgb_r[47:24];
    wire [23:0] overlay_pixel1 = (|safe_fifo_tag[2:0]) ?
                                  24'h0000ff : delayed_raw_rgb_r[23:0];
    wire [47:0] overlay_rgb = {overlay_pixel0, overlay_pixel1};
    wire [47:0] tag_rgb = {
        render_tag(safe_fifo_tag[5:3], (output_mode_r == 4'd4 || output_mode_r == 4'd6) ? delayed_raw_rgb_r[47:24] : 24'b0, output_mode_r),
        render_tag(safe_fifo_tag[2:0], (output_mode_r == 4'd4 || output_mode_r == 4'd6) ? delayed_raw_rgb_r[23:0] : 24'b0, output_mode_r)
    };
    wire [47:0] output_rgb_next = (output_mode_r == 4'd0) ?
                                  (read_enable_d ? delayed_raw_rgb_r : 48'b0) :
                                  (output_mode_r <= 4'd2 || output_mode_r == 4'd7) ? full_edge_rgb :
                                  (output_mode_r == 4'd5) ? overlay_rgb :
                                  (output_mode_r == 4'd4 && !read_enable_d) ? 48'b0 : tag_rgb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_active_mode <= 4'd0;
            sync_addr <= {SYNC_ADDR_WIDTH{1'b0}};
            sync_fill_count <= {(SYNC_ADDR_WIDTH + 1){1'b0}};
            sync_primed <= 1'b0;
        end else begin
            if (i_input_sof)
                o_active_mode <= i_mode;

            if (sync_addr == SYNC_DELAY_CLOCKS - 1)
                sync_addr <= {SYNC_ADDR_WIDTH{1'b0}};
            else
                sync_addr <= sync_addr + 1'b1;

            if (!sync_primed) begin
                if (sync_fill_count == SYNC_DELAY_CLOCKS - 1)
                    sync_primed <= 1'b1;
                else
                    sync_fill_count <= sync_fill_count + 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= {FIFO_ADDR_WIDTH{1'b0}};
            fifo_rd_ptr <= {FIFO_ADDR_WIDTH{1'b0}};
            read_enable_d <= 1'b0;
            output_mode_r <= 4'b0;
            output_vs_r <= 1'b0;
            output_hs_r <= 1'b0;
            output_de_r <= 1'b0;
            delayed_raw_rgb_r <= 48'b0;
            o_overflow <= 1'b0;
            o_underflow <= 1'b0;
            o_overflow_count <= 8'd0;
            o_underflow_count <= 8'd0;
            overflow_event_d <= 1'b0;
            underflow_event_d <= 1'b0;
            o_vs <= 1'b0;
            o_hs <= 1'b0;
            o_de <= 1'b0;
            o_rgb <= 48'b0;
        end else begin
            o_vs <= output_vs_r;
            o_hs <= output_hs_r;
            o_de <= output_de_r;
            o_rgb <= output_rgb_next;
            output_mode_r <= sync_primed ? delayed_mode : 4'b0;
            output_vs_r <= sync_primed ? delayed_timing[2] : 1'b0;
            output_hs_r <= sync_primed ? delayed_timing[1] : 1'b0;
            output_de_r <= sync_primed ? delayed_timing[0] : 1'b0;
            read_enable_d <= read_enable;
            delayed_raw_rgb_r <= delayed_raw_rgb;

            if (write_enable)
                fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
            if (read_enable)
                fifo_rd_ptr <= fifo_rd_ptr + 1'b1;

            // Saturating counters count contiguous fault bursts, not each pixel.
            overflow_event_d <= overflow_event;
            underflow_event_d <= underflow_event;
            if (overflow_event && !overflow_event_d && o_overflow_count != 8'hff)
                o_overflow_count <= o_overflow_count + 1'b1;
            if (underflow_event && !underflow_event_d && o_underflow_count != 8'hff)
                o_underflow_count <= o_underflow_count + 1'b1;
            if (overflow_event)
                o_overflow <= 1'b1;
            if (underflow_event)
                o_underflow <= 1'b1;
        end
    end

endmodule
