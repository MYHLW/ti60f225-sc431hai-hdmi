module video_color_probe_2ppc #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer IMAGE_HEIGHT = 1080
) (
    input wire clk,
    input wire rst_n,
    input wire i_vs,
    input wire i_de,
    input wire [47:0] i_rgb,
    input wire [4:0] i_source_context,
    output reg o_valid,
    output reg [4:0] o_source_context,
    output reg [35:0] o_mean_bcd,
    output reg [35:0] o_sat_bcd
);
    // Read-only 64x64 probe before display white balance. No pixel buffering.
    localparam integer X0 = (IMAGE_WIDTH-64)/2;
    localparam integer Y0 = (IMAGE_HEIGHT-64)/2;
    localparam integer XW = $clog2(IMAGE_WIDTH/2+1);
    localparam integer YW = $clog2(IMAGE_HEIGHT+1);
    reg de_d, vs_d, frame_pending, roi_done, frame_bad;
    reg [XW-1:0] next_pair;
    reg [YW-1:0] next_row, row;
    reg [4:0] frame_context, pending_context;
    wire sol = i_de && !de_d;
    wire sof = sol && frame_pending;
    wire [XW-1:0] pair_x = sol ? {XW{1'b0}} : next_pair;
    wire [YW-1:0] pixel_y = sol ? (sof ? {YW{1'b0}} : next_row) : row;
    wire [XW:0] x0 = {pair_x,1'b0};
    wire [XW:0] x1 = x0 + 1'b1;
    wire bad_line = (de_d && !i_de && next_pair!=IMAGE_WIDTH/2) ||
                    (i_de && pair_x>=IMAGE_WIDTH/2);
    wire hit0 = i_de && x0>=X0 && x0<X0+64 && pixel_y>=Y0 && pixel_y<Y0+64;
    wire hit1 = i_de && x1>=X0 && x1<X0+64 && pixel_y>=Y0 && pixel_y<Y0+64;
    wire roi_end = pixel_y==Y0+63 &&
                   ((hit0 && x0==X0+63) || (hit1 && x1==X0+63));
    wire [1:0] add_count = {1'b0,hit0}+{1'b0,hit1};
    wire [8:0] add_r = {1'b0,(hit0 ? i_rgb[47:40] : 8'd0)} +
                       {1'b0,(hit1 ? i_rgb[23:16] : 8'd0)};
    wire [8:0] add_g = {1'b0,(hit0 ? i_rgb[39:32] : 8'd0)} +
                       {1'b0,(hit1 ? i_rgb[15:8] : 8'd0)};
    wire [8:0] add_b = {1'b0,(hit0 ? i_rgb[31:24] : 8'd0)} +
                       {1'b0,(hit1 ? i_rgb[7:0] : 8'd0)};
    wire [1:0] add_sat_r = {1'b0,(hit0 && i_rgb[47:40]>=8'd250)} +
                           {1'b0,(hit1 && i_rgb[23:16]>=8'd250)};
    wire [1:0] add_sat_g = {1'b0,(hit0 && i_rgb[39:32]>=8'd250)} +
                           {1'b0,(hit1 && i_rgb[15:8]>=8'd250)};
    wire [1:0] add_sat_b = {1'b0,(hit0 && i_rgb[31:24]>=8'd250)} +
                           {1'b0,(hit1 && i_rgb[7:0]>=8'd250)};
    reg [19:0] sum_r, sum_g, sum_b;
    reg [12:0] sat_r, sat_g, sat_b, sample_count;
    wire [19:0] total_r = sum_r+add_r;
    wire [19:0] total_g = sum_g+add_g;
    wire [19:0] total_b = sum_b+add_b;

    function [7:0] percent;
        input [12:0] count;
        reg [19:0] wide_count, product;
        begin
            wide_count = {7'd0,count};
            // count*100/4096, floor to whole percent; no multiplier/divider.
            product = (wide_count<<6)+(wide_count<<5)+(wide_count<<2);
            percent = product[19:12];
        end
    endfunction
    function [11:0] bcd_step;
        input [11:0] digits;
        input bit_value;
        reg [11:0] adjusted;
        integer j;
        begin
            adjusted = digits;
            for (j=0;j<3;j=j+1)
                if (digits[j*4 +: 4]>=5)
                    adjusted[j*4 +: 4]=digits[j*4 +: 4]+4'd3;
            bcd_step = {adjusted[10:0],bit_value};
        end
    endfunction
    // One shared 3-digit converter handles six values in 48 clocks per frame.
    reg converting;
    reg [2:0] value_index, bit_index;
    reg [47:0] values;
    reg [7:0] shift_value;
    reg [11:0] digits;
    reg [71:0] result_bcd;
    wire [11:0] next_digits = bcd_step(digits,shift_value[7]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_d<=0; vs_d<=0; frame_pending<=0; roi_done<=0; frame_bad<=0;
            next_pair<=0; next_row<=0; row<=0; frame_context<=0; pending_context<=0;
            sum_r<=0; sum_g<=0; sum_b<=0; sat_r<=0; sat_g<=0; sat_b<=0; sample_count<=0;
            converting<=0; value_index<=0; bit_index<=0; values<=0;
            shift_value<=0; digits<=0; result_bcd<=0;
            o_valid<=0; o_source_context<=0; o_mean_bcd<=0; o_sat_bcd<=0;
        end else begin
            de_d<=i_de; vs_d<=i_vs;
            if (i_vs && !vs_d) begin
                if (!roi_done || frame_bad || bad_line || converting) o_valid<=0;
                frame_pending<=1; roi_done<=0; frame_bad<=0;
                next_pair<=0; next_row<=0; row<=0;
                sum_r<=0; sum_g<=0; sum_b<=0;
                sat_r<=0; sat_g<=0; sat_b<=0; sample_count<=0;
                converting<=0;
            end else begin
                if (sol) begin
                    row<=pixel_y; next_row<=pixel_y+1'b1;
                    if (sof) begin
                        frame_pending<=0;
                        frame_context<=i_source_context;
                        if (frame_context!=i_source_context) o_valid<=0;
                    end
                end
                if (bad_line) begin
                    frame_bad<=1; o_valid<=0;
                end
                if (i_de) begin
                    next_pair<=pair_x+1'b1;
                end
                if (hit0 || hit1) begin
                    sample_count<=sample_count+add_count;
                    sum_r<=total_r; sum_g<=total_g; sum_b<=total_b;
                    sat_r<=sat_r+add_sat_r; sat_g<=sat_g+add_sat_g; sat_b<=sat_b+add_sat_b;
                end
                if (roi_end) begin
                    roi_done<=1;
                    if (sample_count+add_count==13'd4096 && !frame_bad) begin
                        values<={total_r[19:12],total_g[19:12],total_b[19:12],
                                 percent(sat_r+add_sat_r),percent(sat_g+add_sat_g),percent(sat_b+add_sat_b)};
                        shift_value<=total_r[19:12];
                        pending_context<=frame_context;
                        converting<=1; value_index<=0; bit_index<=0;
                        digits<=0; result_bcd<=0;
                    end else o_valid<=0;
                end
                if (converting) begin
                    digits<=next_digits;
                    shift_value<={shift_value[6:0],1'b0};
                    if (bit_index==7) begin
                        result_bcd<={result_bcd[59:0],next_digits};
                        digits<=0; bit_index<=0;
                        values<={values[39:0],8'd0};
                        shift_value<=values[39:32];
                        value_index<=value_index+1'b1;
                        if (value_index==5) begin
                            converting<=0;
                            o_valid<=!(frame_bad || bad_line);
                            o_source_context<=pending_context;
                            o_mean_bcd<=result_bcd[59:24];
                            o_sat_bcd<={result_bcd[23:0],next_digits};
                        end
                    end else bit_index<=bit_index+1'b1;
                end
            end
        end
    end
endmodule
