module window_3x3_2ppc #(
    parameter integer IMAGE_WIDTH     = 1920,
    parameter integer IMAGE_HEIGHT    = 1080,
    parameter integer PAIR_ADDR_WIDTH = 10,
    parameter integer ROW_COUNT_WIDTH = 11,
    parameter integer PIXEL_WIDTH     = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_sof,
    input  wire        i_sol,
    input  wire        i_valid,
    input  wire [(2*PIXEL_WIDTH)-1:0] i_gray,

    output reg         o_sof,
    output reg         o_sol,
    output reg         o_valid,
    output reg  [1:0]  o_border,
    output reg  [(9*PIXEL_WIDTH)-1:0] o_window0,
    output reg  [(9*PIXEL_WIDTH)-1:0] o_window1
);

    localparam integer PAIRS_PER_LINE = IMAGE_WIDTH / 2;
    localparam integer PAIR_WIDTH     = 2 * PIXEL_WIDTH;
    localparam integer WINDOW_WIDTH   = 9 * PIXEL_WIDTH;

    reg [PAIR_ADDR_WIDTH-1:0] next_pair;
    reg [ROW_COUNT_WIDTH-1:0] next_row;
    wire [PAIR_ADDR_WIDTH-1:0] current_pair = (i_sof || i_sol) ?
                                                  {PAIR_ADDR_WIDTH{1'b0}} : next_pair;
    wire [ROW_COUNT_WIDTH-1:0] current_row  = i_sof ? {ROW_COUNT_WIDTH{1'b0}} : next_row;

    wire [PAIR_WIDTH-1:0] line1_q;
    wire [PAIR_WIDTH-1:0] line2_q;

    reg                         stage0_valid;
    reg [PAIR_ADDR_WIDTH-1:0]   stage0_pair;
    reg [ROW_COUNT_WIDTH-1:0]   stage0_row;
    reg [PAIR_WIDTH-1:0]        stage0_bottom;
    reg                         stage1_valid;
    reg [PAIR_ADDR_WIDTH-1:0]   stage1_pair;
    reg [ROW_COUNT_WIDTH-1:0]   stage1_row;
    reg [PAIR_WIDTH-1:0]        stage1_middle;
    reg [PAIR_WIDTH-1:0]        stage1_bottom;

    reg [PAIR_WIDTH-1:0] top_prev2;
    reg [PAIR_WIDTH-1:0] top_prev1;
    reg [PAIR_WIDTH-1:0] middle_prev2;
    reg [PAIR_WIDTH-1:0] middle_prev1;
    reg [PAIR_WIDTH-1:0] bottom_prev2;
    reg [PAIR_WIDTH-1:0] bottom_prev1;

    reg                       line_flush_pending;
    reg [ROW_COUNT_WIDTH-1:0] pending_center_row;
    reg                       pending_is_last_input_row;
    reg                       bottom_flush_active;
    reg [PAIR_ADDR_WIDTH-1:0] bottom_flush_pair;

    wire [PAIR_WIDTH-1:0] current_top = (stage1_row >= 2) ?
                                            line2_q : {PAIR_WIDTH{1'b0}};
    wire row_is_border = (stage1_row <= 1) || (stage1_row >= IMAGE_HEIGHT);
    wire pending_row_is_border = (pending_center_row == 0) ||
                                 (pending_center_row == IMAGE_HEIGHT - 1);

    true_dual_port_ram #(
        .DATA_WIDTH(PAIR_WIDTH),
        .ADDR_WIDTH(PAIR_ADDR_WIDTH),
        .WRITE_MODE_1("READ_FIRST"),
        .WRITE_MODE_2("READ_FIRST"),
        .OUTPUT_REG_1("FALSE"),
        .OUTPUT_REG_2("FALSE"),
        .RAM_INIT_FILE("")
    ) line_buffer_1 (
        .we1(i_valid),
        .we2(1'b0),
        .clka(clk),
        .clkb(clk),
        .din1(i_gray),
        .din2({PAIR_WIDTH{1'b0}}),
        .addr1(current_pair),
        .addr2({PAIR_ADDR_WIDTH{1'b0}}),
        .dout1(line1_q),
        .dout2()
    );

    true_dual_port_ram #(
        .DATA_WIDTH(PAIR_WIDTH),
        .ADDR_WIDTH(PAIR_ADDR_WIDTH),
        .WRITE_MODE_1("READ_FIRST"),
        .WRITE_MODE_2("READ_FIRST"),
        .OUTPUT_REG_1("FALSE"),
        .OUTPUT_REG_2("FALSE"),
        .RAM_INIT_FILE("")
    ) line_buffer_2 (
        .we1(stage0_valid),
        .we2(1'b0),
        .clka(clk),
        .clkb(clk),
        .din1(line1_q),
        .din2({PAIR_WIDTH{1'b0}}),
        .addr1(stage0_pair),
        .addr2({PAIR_ADDR_WIDTH{1'b0}}),
        .dout1(line2_q),
        .dout2()
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
            next_row  <= {ROW_COUNT_WIDTH{1'b0}};
        end else if (i_valid) begin
            if (current_pair == PAIRS_PER_LINE - 1) begin
                next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
                next_row  <= current_row + 1'b1;
            end else begin
                next_pair <= current_pair + 1'b1;
                next_row  <= current_row;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage0_valid  <= 1'b0;
            stage0_pair   <= {PAIR_ADDR_WIDTH{1'b0}};
            stage0_row    <= {ROW_COUNT_WIDTH{1'b0}};
            stage0_bottom <= {PAIR_WIDTH{1'b0}};
            stage1_valid  <= 1'b0;
            stage1_pair   <= {PAIR_ADDR_WIDTH{1'b0}};
            stage1_row    <= {ROW_COUNT_WIDTH{1'b0}};
            stage1_middle <= {PAIR_WIDTH{1'b0}};
            stage1_bottom <= {PAIR_WIDTH{1'b0}};
        end else begin
            stage0_valid <= i_valid;
            if (i_valid) begin
                stage0_pair   <= current_pair;
                stage0_row    <= current_row;
                stage0_bottom <= i_gray;
            end

            stage1_valid <= stage0_valid;
            if (stage0_valid) begin
                stage1_pair   <= stage0_pair;
                stage1_row    <= stage0_row;
                stage1_middle <= (stage0_row >= 1) ?
                                     line1_q : {PAIR_WIDTH{1'b0}};
                stage1_bottom <= stage0_bottom;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_sof                     <= 1'b0;
            o_sol                     <= 1'b0;
            o_valid                   <= 1'b0;
            o_border                  <= 2'b11;
            o_window0                 <= {WINDOW_WIDTH{1'b0}};
            o_window1                 <= {WINDOW_WIDTH{1'b0}};
            top_prev2                 <= {PAIR_WIDTH{1'b0}};
            top_prev1                 <= {PAIR_WIDTH{1'b0}};
            middle_prev2              <= {PAIR_WIDTH{1'b0}};
            middle_prev1              <= {PAIR_WIDTH{1'b0}};
            bottom_prev2              <= {PAIR_WIDTH{1'b0}};
            bottom_prev1              <= {PAIR_WIDTH{1'b0}};
            line_flush_pending        <= 1'b0;
            pending_center_row        <= {ROW_COUNT_WIDTH{1'b0}};
            pending_is_last_input_row <= 1'b0;
            bottom_flush_active       <= 1'b0;
            bottom_flush_pair         <= {PAIR_ADDR_WIDTH{1'b0}};
        end else begin
            o_sof    <= 1'b0;
            o_sol    <= 1'b0;
            o_valid  <= 1'b0;
            o_border <= 2'b11;

            if (bottom_flush_active) begin
                o_valid   <= 1'b1;
                o_sol     <= (bottom_flush_pair == 0);
                o_border  <= 2'b11;
                o_window0 <= {WINDOW_WIDTH{1'b0}};
                o_window1 <= {WINDOW_WIDTH{1'b0}};
                if (bottom_flush_pair == PAIRS_PER_LINE - 1) begin
                    bottom_flush_active <= 1'b0;
                    bottom_flush_pair   <= {PAIR_ADDR_WIDTH{1'b0}};
                end else begin
                    bottom_flush_pair <= bottom_flush_pair + 1'b1;
                end
            end else if (line_flush_pending) begin
                o_valid   <= 1'b1;
                o_border  <= {1'b1, pending_row_is_border};
                o_window0 <= pending_row_is_border ? {WINDOW_WIDTH{1'b0}} : {
                    top_prev2[PIXEL_WIDTH-1:0],
                    top_prev1[PAIR_WIDTH-1:PIXEL_WIDTH],
                    top_prev1[PIXEL_WIDTH-1:0],
                    middle_prev2[PIXEL_WIDTH-1:0],
                    middle_prev1[PAIR_WIDTH-1:PIXEL_WIDTH],
                    middle_prev1[PIXEL_WIDTH-1:0],
                    bottom_prev2[PIXEL_WIDTH-1:0],
                    bottom_prev1[PAIR_WIDTH-1:PIXEL_WIDTH],
                    bottom_prev1[PIXEL_WIDTH-1:0]
                };
                o_window1          <= {WINDOW_WIDTH{1'b0}};
                line_flush_pending <= 1'b0;
                if (pending_is_last_input_row) begin
                    bottom_flush_active <= 1'b1;
                    bottom_flush_pair   <= {PAIR_ADDR_WIDTH{1'b0}};
                end
            end else if (stage1_valid) begin
                if (stage1_pair == 0) begin
                    top_prev2    <= {PAIR_WIDTH{1'b0}};
                    top_prev1    <= current_top;
                    middle_prev2 <= {PAIR_WIDTH{1'b0}};
                    middle_prev1 <= stage1_middle;
                    bottom_prev2 <= {PAIR_WIDTH{1'b0}};
                    bottom_prev1 <= stage1_bottom;
                end else begin
                    if (stage1_row >= 1) begin
                        o_sof    <= (stage1_row == 1) && (stage1_pair == 1);
                        o_sol    <= (stage1_pair == 1);
                        o_valid  <= 1'b1;
                        o_border <= {row_is_border, row_is_border || (stage1_pair == 1)};
                        o_window0 <= (row_is_border || (stage1_pair == 1)) ?
                            {WINDOW_WIDTH{1'b0}} : {
                            top_prev2[PIXEL_WIDTH-1:0],
                            top_prev1[PAIR_WIDTH-1:PIXEL_WIDTH],
                            top_prev1[PIXEL_WIDTH-1:0],
                            middle_prev2[PIXEL_WIDTH-1:0],
                            middle_prev1[PAIR_WIDTH-1:PIXEL_WIDTH],
                            middle_prev1[PIXEL_WIDTH-1:0],
                            bottom_prev2[PIXEL_WIDTH-1:0],
                            bottom_prev1[PAIR_WIDTH-1:PIXEL_WIDTH],
                            bottom_prev1[PIXEL_WIDTH-1:0]
                        };
                        o_window1 <= row_is_border ? {WINDOW_WIDTH{1'b0}} : {
                            top_prev1[PAIR_WIDTH-1:PIXEL_WIDTH],
                            top_prev1[PIXEL_WIDTH-1:0],
                            current_top[PAIR_WIDTH-1:PIXEL_WIDTH],
                            middle_prev1[PAIR_WIDTH-1:PIXEL_WIDTH],
                            middle_prev1[PIXEL_WIDTH-1:0],
                            stage1_middle[PAIR_WIDTH-1:PIXEL_WIDTH],
                            bottom_prev1[PAIR_WIDTH-1:PIXEL_WIDTH],
                            bottom_prev1[PIXEL_WIDTH-1:0],
                            stage1_bottom[PAIR_WIDTH-1:PIXEL_WIDTH]
                        };
                    end

                    top_prev2    <= top_prev1;
                    top_prev1    <= current_top;
                    middle_prev2 <= middle_prev1;
                    middle_prev1 <= stage1_middle;
                    bottom_prev2 <= bottom_prev1;
                    bottom_prev1 <= stage1_bottom;

                    if ((stage1_pair == PAIRS_PER_LINE - 1) && (stage1_row >= 1)) begin
                        line_flush_pending        <= 1'b1;
                        pending_center_row        <= stage1_row - 1'b1;
                        pending_is_last_input_row <= (stage1_row == IMAGE_HEIGHT - 1);
                    end
                end
            end
        end
    end

endmodule
