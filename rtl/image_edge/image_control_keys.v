module image_control_keys #(
    parameter integer DEBOUNCE_CYCLES  = 742500,
    parameter integer FEEDBACK_CYCLES  = 7425000,
    parameter [3:0]   DEFAULT_MODE      = 4'd0,
    parameter [10:0]  DEFAULT_THRESHOLD = 11'd192,
    parameter [10:0]  THRESHOLD_STEP    = 11'd32,
    parameter [10:0]  MIN_THRESHOLD     = 11'd32
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_key_down_n,
    input  wire        i_key_up_n,
    input  wire        i_key_mode_n,
    input  wire        i_mode_select_valid,
    input  wire [3:0]  i_mode_select,
    output reg  [3:0]  o_mode,
    output reg  [10:0] o_threshold,
    output wire        o_feedback
);

    localparam integer DEBOUNCE_WIDTH = (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES);
    localparam integer FEEDBACK_WIDTH = (FEEDBACK_CYCLES <= 1) ? 1 : $clog2(FEEDBACK_CYCLES + 1);

    reg [2:0] key_meta;
    reg [2:0] key_sync;
    reg [2:0] key_state;
    reg [DEBOUNCE_WIDTH-1:0] down_count;
    reg [DEBOUNCE_WIDTH-1:0] up_count;
    reg [DEBOUNCE_WIDTH-1:0] mode_count;
    reg [FEEDBACK_WIDTH-1:0] feedback_count;
    reg down_press;
    reg up_press;
    reg mode_press;

    // Keep the original coarse range; use finer steps only below H=64.
    wire [10:0] down_step = (o_threshold <= 11'd64) ? 11'd8 : THRESHOLD_STEP;
    wire [10:0] up_step = (o_threshold < 11'd64) ? 11'd8 : THRESHOLD_STEP;

    assign o_feedback = (feedback_count != 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 3'b111;
            key_sync <= 3'b111;
        end else begin
            key_meta <= {i_key_mode_n, i_key_up_n, i_key_down_n};
            key_sync <= key_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_state <= 3'b111;
            down_count <= {DEBOUNCE_WIDTH{1'b0}};
            up_count <= {DEBOUNCE_WIDTH{1'b0}};
            mode_count <= {DEBOUNCE_WIDTH{1'b0}};
            down_press <= 1'b0;
            up_press <= 1'b0;
            mode_press <= 1'b0;
        end else begin
            down_press <= 1'b0;
            up_press <= 1'b0;
            mode_press <= 1'b0;

            if (key_sync[0] == key_state[0]) begin
                down_count <= {DEBOUNCE_WIDTH{1'b0}};
            end else if ((DEBOUNCE_CYCLES <= 1) || (down_count == DEBOUNCE_CYCLES - 1)) begin
                key_state[0] <= key_sync[0];
                down_count <= {DEBOUNCE_WIDTH{1'b0}};
                if (!key_sync[0]) down_press <= 1'b1;
            end else begin
                down_count <= down_count + 1'b1;
            end

            if (key_sync[1] == key_state[1]) begin
                up_count <= {DEBOUNCE_WIDTH{1'b0}};
            end else if ((DEBOUNCE_CYCLES <= 1) || (up_count == DEBOUNCE_CYCLES - 1)) begin
                key_state[1] <= key_sync[1];
                up_count <= {DEBOUNCE_WIDTH{1'b0}};
                if (!key_sync[1]) up_press <= 1'b1;
            end else begin
                up_count <= up_count + 1'b1;
            end

            if (key_sync[2] == key_state[2]) begin
                mode_count <= {DEBOUNCE_WIDTH{1'b0}};
            end else if ((DEBOUNCE_CYCLES <= 1) || (mode_count == DEBOUNCE_CYCLES - 1)) begin
                key_state[2] <= key_sync[2];
                mode_count <= {DEBOUNCE_WIDTH{1'b0}};
                if (!key_sync[2]) mode_press <= 1'b1;
            end else begin
                mode_count <= mode_count + 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_mode <= DEFAULT_MODE;
            o_threshold <= DEFAULT_THRESHOLD;
            feedback_count <= {FEEDBACK_WIDTH{1'b0}};
        end else begin
            if (down_press) begin
                if (o_threshold <= (MIN_THRESHOLD + down_step))
                    o_threshold <= MIN_THRESHOLD;
                else if ((o_threshold > 11'd64) &&
                         (o_threshold - down_step < 11'd64))
                    o_threshold <= 11'd64;
                else
                    o_threshold <= o_threshold - down_step;
            end else if (up_press) begin
                if (o_threshold > 11'd2040 - up_step)
                    o_threshold <= 11'd2040;
                else if ((o_threshold < 11'd64) &&
                         (o_threshold + up_step > 11'd64))
                    o_threshold <= 11'd64;
                else
                    o_threshold <= o_threshold + up_step;
            end

            if (i_mode_select_valid && (i_mode_select <= 4'd5 || i_mode_select == 4'd7)) begin
                o_mode <= i_mode_select;
            end else if (mode_press) begin
                if (o_mode >= 4'd5)
                    o_mode <= 4'd0;
                else
                    o_mode <= o_mode + 1'b1;
            end

            if (down_press || up_press || mode_press)
                feedback_count <= FEEDBACK_CYCLES;
            else if (feedback_count != 0)
                feedback_count <= feedback_count - 1'b1;
        end
    end

endmodule
