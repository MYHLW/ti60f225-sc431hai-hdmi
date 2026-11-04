module display_tone_curve_2ppc #(
    // Compile-time A/B switch. Both settings keep the same three-clock latency.
    parameter ENABLE = 1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_vs,
    input  wire        i_hs,
    input  wire        i_de,
    input  wire [47:0] i_rgb,
    input  wire [47:0] i_original_rgb,

    output reg         o_vs,
    output reg         o_hs,
    output reg         o_de,
    output reg  [47:0] o_rgb
);

    function [7:0] pixel_maximum;
        input [23:0] pixel;
        reg [7:0] maximum;
        begin
            maximum = (pixel[23:16] > pixel[15:8]) ? pixel[23:16] : pixel[15:8];
            if (pixel[7:0] > maximum)
                maximum = pixel[7:0];
            pixel_maximum = maximum;
        end
    endfunction

    // Shared Q8 gain: stronger shadows, monotone shoulder, unchanged black.
    // Gray 32/64/128/224 maps to 80/128/192/251; only 255 reaches 255.
    function [9:0] pixel_gain;
        input [23:0] pixel;
        reg [9:0] maximum;
        begin
            maximum = {2'b0,pixel_maximum(pixel)};
            if (maximum<=64) pixel_gain=10'd768-(maximum<<2);
            else if (maximum<=128) pixel_gain=10'd640-(maximum<<1);
            else pixel_gain=10'd511-maximum;
        end
    endfunction

    // Judge near-clipping BEFORE WB, not from a green channel already reduced
    // by its fixed gain. Two continuous ramps avoid a hard on/off colour seam.
    // Strongly coloured lights (any channel <=160) are not neutralised.
    function [5:0] highlight_weight;
        input [23:0] original;
        reg [7:0] minimum, maximum;
        reg [5:0] bright_weight, clip_weight;
        begin
            minimum=(original[23:16]<original[15:8]) ? original[23:16] : original[15:8];
            if (original[7:0]<minimum) minimum=original[7:0];
            maximum=pixel_maximum(original);
            if (minimum<=160) bright_weight=0;
            else if (minimum>=224) bright_weight=32;
            else bright_weight=({1'b0,minimum}-9'd160)>>1;
            if (maximum<=240) clip_weight=0;
            else if (maximum>=248) clip_weight=32;
            else clip_weight=({1'b0,maximum}-9'd240)<<2;
            highlight_weight=(bright_weight<clip_weight) ? bright_weight : clip_weight;
        end
    endfunction

    function [7:0] neutral_channel;
        input [7:0] pixel, maximum;
        input [5:0] weight;
        reg [7:0] difference;
        reg [13:0] product;
        reg [8:0] result;
        begin
            difference=maximum-pixel;
            product=difference*weight+14'd16;
            result={1'b0,pixel}+(product>>5);
            neutral_channel=result[7:0];
        end
    endfunction

    function [7:0] apply_gain;
        input [7:0] pixel;
        input [9:0] gain;
        reg [17:0] product;
        begin
            product = pixel * gain;
            // The fixed curve never reaches this branch; keep safe saturation
            // if the curve is deliberately changed later, rather than wrapping.
            apply_gain = (|product[17:16]) ? 8'hff : product[15:8];
        end
    endfunction

    reg s1_vs, s1_hs, s1_de;
    reg [47:0] s1_rgb;
    reg [9:0] s1_gain0, s1_gain1;
    reg [7:0] s1_max0, s1_max1;
    reg [5:0] s1_weight0, s1_weight1;
    reg s2_vs, s2_hs, s2_de;
    reg [47:0] s2_rgb;
    reg [9:0] s2_gain0, s2_gain1;

    wire [47:0] neutral_rgb = {
        neutral_channel(s1_rgb[47:40],s1_max0,s1_weight0),
        neutral_channel(s1_rgb[39:32],s1_max0,s1_weight0),
        neutral_channel(s1_rgb[31:24],s1_max0,s1_weight0),
        neutral_channel(s1_rgb[23:16],s1_max1,s1_weight1),
        neutral_channel(s1_rgb[15:8],s1_max1,s1_weight1),
        neutral_channel(s1_rgb[7:0],s1_max1,s1_weight1)
    };

    wire [47:0] corrected_rgb = {
        apply_gain(s2_rgb[47:40], s2_gain0),
        apply_gain(s2_rgb[39:32], s2_gain0),
        apply_gain(s2_rgb[31:24], s2_gain0),
        apply_gain(s2_rgb[23:16], s2_gain1),
        apply_gain(s2_rgb[15:8],  s2_gain1),
        apply_gain(s2_rgb[7:0],   s2_gain1)
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_vs <= 1'b0;
            s1_hs <= 1'b0;
            s1_de <= 1'b0;
            s1_rgb <= 48'b0;
            s1_gain0 <= 10'd256;
            s1_gain1 <= 10'd256;
            s1_max0 <= 0; s1_max1 <= 0;
            s1_weight0 <= 0; s1_weight1 <= 0;
            s2_vs <= 0; s2_hs <= 0; s2_de <= 0; s2_rgb <= 0;
            s2_gain0 <= 10'd256; s2_gain1 <= 10'd256;
            o_vs <= 1'b0;
            o_hs <= 1'b0;
            o_de <= 1'b0;
            o_rgb <= 48'b0;
        end else begin
            s1_vs <= i_vs;
            s1_hs <= i_hs;
            s1_de <= i_de;
            s1_rgb <= i_rgb;
            s1_gain0 <= pixel_gain(i_rgb[47:24]);
            s1_gain1 <= pixel_gain(i_rgb[23:0]);
            s1_max0 <= pixel_maximum(i_rgb[47:24]);
            s1_max1 <= pixel_maximum(i_rgb[23:0]);
            s1_weight0 <= highlight_weight(i_original_rgb[47:24]);
            s1_weight1 <= highlight_weight(i_original_rgb[23:0]);
            s2_vs <= s1_vs; s2_hs <= s1_hs; s2_de <= s1_de;
            s2_rgb <= ENABLE ? neutral_rgb : s1_rgb;
            s2_gain0 <= s1_gain0; s2_gain1 <= s1_gain1;
            o_vs <= s2_vs;
            o_hs <= s2_hs;
            o_de <= s2_de;
            o_rgb <= ENABLE ? corrected_rgb : s2_rgb;
        end
    end

endmodule
