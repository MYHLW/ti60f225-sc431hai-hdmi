module rgb2gray_2ppc
(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_sof,
    input  wire        i_sol,
    input  wire        i_valid,
    input  wire [47:0] i_rgb,

    output reg         o_sof,
    output reg         o_sol,
    output reg         o_valid,
    output reg  [15:0] o_gray
);

    reg        sof_1p;
    reg        sol_1p;
    reg        valid_1p;
    reg        sof_2p;
    reg        sol_2p;
    reg        valid_2p;

    reg [15:0] r0_1p;
    reg [15:0] g0_1p;
    reg [15:0] b0_1p;
    reg [15:0] r1_1p;
    reg [15:0] g1_1p;
    reg [15:0] b1_1p;
    reg [15:0] sum0_2p;
    reg [15:0] sum1_2p;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sof_1p   <= 1'b0;
            sol_1p   <= 1'b0;
            valid_1p <= 1'b0;
            sof_2p   <= 1'b0;
            sol_2p   <= 1'b0;
            valid_2p <= 1'b0;
            o_sof    <= 1'b0;
            o_sol    <= 1'b0;
            o_valid  <= 1'b0;
            o_gray   <= 16'b0;
            r0_1p    <= 16'b0;
            g0_1p    <= 16'b0;
            b0_1p    <= 16'b0;
            r1_1p    <= 16'b0;
            g1_1p    <= 16'b0;
            b1_1p    <= 16'b0;
            sum0_2p  <= 16'b0;
            sum1_2p  <= 16'b0;
        end else begin
            sof_1p   <= i_sof;
            sol_1p   <= i_sol;
            valid_1p <= i_valid;
            r0_1p    <= i_rgb[47:40] * 8'd77;
            g0_1p    <= i_rgb[39:32] * 8'd150;
            b0_1p    <= i_rgb[31:24] * 8'd29;
            r1_1p    <= i_rgb[23:16] * 8'd77;
            g1_1p    <= i_rgb[15:8]  * 8'd150;
            b1_1p    <= i_rgb[7:0]   * 8'd29;

            sof_2p   <= sof_1p;
            sol_2p   <= sol_1p;
            valid_2p <= valid_1p;
            sum0_2p  <= r0_1p + g0_1p + b0_1p;
            sum1_2p  <= r1_1p + g1_1p + b1_1p;

            o_sof    <= sof_2p;
            o_sol    <= sol_2p;
            o_valid  <= valid_2p;
            o_gray   <= {sum0_2p[15:8], sum1_2p[15:8]};
        end
    end

endmodule
