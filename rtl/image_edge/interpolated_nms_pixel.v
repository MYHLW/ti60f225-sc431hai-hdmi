// One lane of division-free interpolated NMS.  Latency is three clocks;
// both lanes run in parallel, so the enclosing Canny remains 2 PPC.
module interpolated_nms_pixel (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [314:0] i_window,
    input  wire         i_border,
    output wire [10:0]  o_magnitude,
    output wire [1:0]   o_direction
);
    // Pixel: {magnitude[10:0], major[9:0], minor[9:0], x_major,
    //         same_sign, direction[1:0]}. Sobel derivatives are <= 1020.
    function [10:0] mag;
        input [314:0] window;
        input integer index;
        begin
            mag = window[35 * (8 - index) + 24 +: 11];
        end
    endfunction

    wire [34:0] center = i_window[174:140];
    wire [9:0] major = center[23:14];
    wire [9:0] minor = center[13:4];
    reg [10:0] axial_a, axial_b, diagonal_a, diagonal_b;
    always @(*) begin
        if (center[3]) begin
            if (center[2] || minor == 0) begin
                axial_a = mag(i_window, 3);
                axial_b = mag(i_window, 5);
                diagonal_a = mag(i_window, 0);
                diagonal_b = mag(i_window, 8);
            end else begin
                axial_a = mag(i_window, 5);
                axial_b = mag(i_window, 3);
                diagonal_a = mag(i_window, 2);
                diagonal_b = mag(i_window, 6);
            end
        end else begin
            axial_a = mag(i_window, 1);
            axial_b = mag(i_window, 7);
            diagonal_a = center[2] ? mag(i_window, 0) : mag(i_window, 2);
            diagonal_b = center[2] ? mag(i_window, 8) : mag(i_window, 6);
        end
    end

    reg [10:0] center_s1, center_s2, center_s3;
    reg [1:0] direction_s1, direction_s2, direction_s3;
    reg [2:0] border_pipe;
    reg [9:0] major_s1, minor_s1, axial_weight_s1;
    reg [10:0] axial_a_s1, axial_b_s1, diagonal_a_s1, diagonal_b_s1;
    reg [20:0] center_product_s2;
    reg [20:0] axial_product_a_s2, axial_product_b_s2;
    reg [20:0] diagonal_product_a_s2, diagonal_product_b_s2;
    reg [21:0] center_product_s3, neighbor_a_s3, neighbor_b_s3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            center_s1 <= 0; center_s2 <= 0; center_s3 <= 0;
            direction_s1 <= 0; direction_s2 <= 0; direction_s3 <= 0;
            border_pipe <= 3'b111;
            major_s1 <= 0; minor_s1 <= 0; axial_weight_s1 <= 0;
            axial_a_s1 <= 0; axial_b_s1 <= 0;
            diagonal_a_s1 <= 0; diagonal_b_s1 <= 0;
            center_product_s2 <= 0;
            axial_product_a_s2 <= 0; axial_product_b_s2 <= 0;
            diagonal_product_a_s2 <= 0; diagonal_product_b_s2 <= 0;
            center_product_s3 <= 0; neighbor_a_s3 <= 0; neighbor_b_s3 <= 0;
        end else begin
            // Select interpolation endpoints and unsigned coefficients.
            center_s1 <= center[34:24];
            direction_s1 <= center[1:0];
            border_pipe <= {border_pipe[1:0], i_border};
            major_s1 <= major;
            minor_s1 <= minor;
            axial_weight_s1 <= major - minor;
            axial_a_s1 <= axial_a; axial_b_s1 <= axial_b;
            diagonal_a_s1 <= diagonal_a; diagonal_b_s1 <= diagonal_b;

            // DSP-friendly registered products; no division or angle rounding.
            center_product_s2 <= center_s1 * major_s1;
            axial_product_a_s2 <= axial_a_s1 * axial_weight_s1;
            axial_product_b_s2 <= axial_b_s1 * axial_weight_s1;
            diagonal_product_a_s2 <= diagonal_a_s1 * minor_s1;
            diagonal_product_b_s2 <= diagonal_b_s1 * minor_s1;
            center_s2 <= center_s1;
            direction_s2 <= direction_s1;

            center_product_s3 <= {1'b0, center_product_s2};
            neighbor_a_s3 <= {1'b0, axial_product_a_s2} + {1'b0, diagonal_product_a_s2};
            neighbor_b_s3 <= {1'b0, axial_product_b_s2} + {1'b0, diagonal_product_b_s2};
            center_s3 <= center_s2;
            direction_s3 <= direction_s2;
        end
    end

    // >= on A and > on B selects one side of a flat ridge deterministically.
    assign o_magnitude = (!border_pipe[2] && center_s3 != 0 &&
                          center_product_s3 >= neighbor_a_s3 &&
                          center_product_s3 > neighbor_b_s3) ? center_s3 : 11'b0;
    assign o_direction = direction_s3;
endmodule
