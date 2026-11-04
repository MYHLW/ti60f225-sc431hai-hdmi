module manual_white_balance_2ppc #(
    // Board-validated fixed Q2.8 gains: 256 = 1.0.
    //parameter [9:0] GAIN_R = 10'd244,
    //parameter [9:0] GAIN_G = 10'd160,
    parameter [9:0] GAIN_R = 10'd228,
    parameter [9:0] GAIN_G = 10'd152,
    // parameter [9:0] GAIN_R = 10'd200,
    // parameter [9:0] GAIN_G = 10'd148,
    // parameter [9:0] GAIN_R = 10'd180,
    // parameter [9:0] GAIN_G = 10'd148,//太绿
    parameter [9:0] GAIN_B = 10'd256
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_vs,
    input  wire        i_hs,
    input  wire        i_de,
    input  wire [47:0] i_rgb,

    output reg         o_vs,
    output reg         o_hs,
    output reg         o_de,
    output reg  [47:0] o_algorithm_rgb,
    output reg  [47:0] o_display_rgb
);

    function [7:0] apply_gain;
        input [7:0] pixel;
        input [9:0] gain;
        reg [17:0] product;
        begin
            product = pixel * gain;
            if (|product[17:16])
                apply_gain = 8'hff;
            else
                apply_gain = product[15:8];
        end
    endfunction

    wire [47:0] corrected_rgb = {
        apply_gain(i_rgb[47:40], GAIN_R),
        apply_gain(i_rgb[39:32], GAIN_G),
        apply_gain(i_rgb[31:24], GAIN_B),
        apply_gain(i_rgb[23:16], GAIN_R),
        apply_gain(i_rgb[15:8],  GAIN_G),
        apply_gain(i_rgb[7:0],   GAIN_B)
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_vs <= 1'b0;
            o_hs <= 1'b0;
            o_de <= 1'b0;
            o_algorithm_rgb <= 48'b0;
            o_display_rgb <= 48'b0;
        end else begin
            o_vs <= i_vs;
            o_hs <= i_hs;
            o_de <= i_de;
            o_algorithm_rgb <= i_rgb;
            o_display_rgb <= corrected_rgb;
        end
    end

endmodule
