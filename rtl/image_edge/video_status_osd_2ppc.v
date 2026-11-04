module video_status_osd_2ppc #(
    parameter integer IMAGE_WIDTH     = 1920,
    parameter integer IMAGE_HEIGHT    = 1080,
    parameter integer PAIR_ADDR_WIDTH = 10,
    parameter integer ROW_COUNT_WIDTH = 11,
    parameter integer COLOR_DIAGNOSTICS = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_enable,
    input  wire        i_vs,
    input  wire        i_hs,
    input  wire        i_de,
    input  wire [47:0] i_rgb,
    input  wire [7:0]  i_fps_bcd,
    input  wire [3:0]  i_mode,
    input  wire [2:0]  i_compare_left, i_compare_right,
    input  wire [3:0]  i_object_count,
    input  wire [4:0]  i_shape_mask,
    input  wire [1:0]  i_frame_state,
    input  wire        i_saved_valid,
    input  wire [2:0]  i_saved_count,
    input  wire [2:0]  i_saved_index,
    input  wire [10:0] i_high_threshold, i_low_threshold,
    input  wire        i_roi_active, i_ccl_limit, i_tracks_stale,
    input  wire        i_inspection_active,
    input  wire [1:0]  i_inspection_status,
    input  wire [3:0]  i_inspection_mask,
    input  wire [10:0] i_inspection_depth,
    input  wire        i_inspection_hold,
    input  wire [7:0]  i_overflow_count, i_underflow_count,
    input  wire        i_color_valid,
    input  wire [35:0] i_color_mean_bcd, i_color_sat_bcd,
    output reg         o_vs,
    output reg         o_hs,
    output reg         o_de,
    output reg  [47:0] o_rgb
);

    localparam [10:0] PANEL_X      = 11'd8;
    localparam [10:0] PANEL_Y      = 11'd8;
    localparam [10:0] PANEL_WIDTH  = 11'd416;
    localparam [10:0] PANEL_HEIGHT = 11'd104;
    localparam [10:0] TEXT_X       = 11'd16;
    localparam [10:0] TEXT_Y0      = 11'd14;
    localparam [10:0] TEXT_Y1      = 11'd38;
    localparam [10:0] TEXT_Y2      = 11'd62;
    localparam [10:0] TEXT_Y3      = 11'd86;
    // Only SHAPE needs the two extra category fields. CHECK/other panels stay unchanged.
    wire extended_shape_status = mode_latched==4'd4 && !inspection_latched;
    wire color_diagnostics_active = COLOR_DIAGNOSTICS && mode_latched==4'd0;
    wire [10:0] panel_width = extended_shape_status ? 11'd624 : PANEL_WIDTH;
    wire [10:0] text_width = extended_shape_status ? 11'd608 : 11'd400;

    reg de_d;
    reg vs_d;
    reg frame_pending;
    reg [PAIR_ADDR_WIDTH-1:0] next_pair;
    reg [ROW_COUNT_WIDTH-1:0] next_row;
    wire input_sol = i_de && !de_d;
    wire input_sof = input_sol && frame_pending;
    wire [PAIR_ADDR_WIDTH-1:0] current_pair = input_sol ?
        {PAIR_ADDR_WIDTH{1'b0}} : next_pair;
    wire [ROW_COUNT_WIDTH-1:0] current_row = input_sof ?
        {ROW_COUNT_WIDTH{1'b0}} : next_row;
    wire [PAIR_ADDR_WIDTH:0] current_x0 = {current_pair, 1'b0};
    wire [PAIR_ADDR_WIDTH:0] current_x1 = current_x0 + 1'b1;

    reg [7:0] fps_bcd_latched;
    reg enable_latched;
    reg [3:0] mode_latched;
    reg [2:0] compare_left_latched, compare_right_latched;
    reg [3:0] object_count_latched;
    reg [4:0] shape_mask_latched;
    reg [1:0] frame_state_latched;
    reg saved_valid_latched;
    reg [2:0] saved_count_latched;
    reg [2:0] saved_index_latched;
    reg [15:0] high_bcd, low_bcd;
    reg roi_latched, limit_latched, stale_latched;
    reg [7:0] overflow_latched, underflow_latched;
    reg inspection_latched;
    reg inspection_hold;
    reg [1:0] inspection_status;
    reg [3:0] inspection_mask;
    reg [15:0] inspection_depth_bcd;
    reg color_valid_latched;
    reg [35:0] color_mean_bcd, color_sat_bcd;
    // Conversion happens only when latching frame status, not in the pixel path.
    function [15:0] threshold_bcd;
        input [10:0] value;
        reg [15:0] digits;
        integer bit_index, digit_index;
        begin
            digits=0;
            for (bit_index=10; bit_index>=0; bit_index=bit_index-1) begin
                for (digit_index=0; digit_index<4; digit_index=digit_index+1)
                    if (digits[digit_index*4 +: 4]>=5)
                        digits[digit_index*4 +: 4]=digits[digit_index*4 +: 4]+4'd3;
                digits={digits[14:0],value[bit_index]};
            end
            threshold_bcd=digits;
        end
    endfunction
    function [7:0] hex_char;
        input [3:0] value;
        begin hex_char=value<10 ? 8'h30+value : 8'h41+value-4'd10; end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_d <= 1'b0;
            vs_d <= 1'b0;
            frame_pending <= 1'b0;
            next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
            next_row <= {ROW_COUNT_WIDTH{1'b0}};
            fps_bcd_latched <= 8'h00;
            enable_latched <= 1'b1;
            mode_latched <= 4'd0;
            compare_left_latched <= 3'd2; compare_right_latched <= 3'd3;
            object_count_latched <= 4'd0;
            shape_mask_latched <= 5'b00000;
            frame_state_latched <= 2'd0;
            saved_valid_latched <= 1'b0;
            saved_count_latched <= 3'd0;
            saved_index_latched <= 3'd0;
            high_bcd<=0; low_bcd<=0; roi_latched<=0; limit_latched<=0; stale_latched<=0;
            overflow_latched<=0; underflow_latched<=0;
            inspection_latched<=0; inspection_hold<=0; inspection_status<=0; inspection_mask<=0; inspection_depth_bcd<=0;
            color_valid_latched<=0; color_mean_bcd<=0; color_sat_bcd<=0;
        end else begin
            de_d <= i_de;
            vs_d <= i_vs;
            if (i_vs && !vs_d) begin
                frame_pending <= 1'b1;
                next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
                next_row <= {ROW_COUNT_WIDTH{1'b0}};
            end else if (input_sof) begin
                frame_pending <= 1'b0;
                enable_latched <= i_enable;
                fps_bcd_latched <= i_fps_bcd;
                mode_latched <= i_mode;
                compare_left_latched <= i_compare_left; compare_right_latched <= i_compare_right;
                object_count_latched <= i_object_count;
                shape_mask_latched <= i_shape_mask;
                frame_state_latched <= i_frame_state;
                saved_valid_latched <= i_saved_valid;
                saved_count_latched <= i_saved_count;
                saved_index_latched <= i_saved_index;
                high_bcd<=threshold_bcd(i_high_threshold);
                low_bcd<=threshold_bcd(i_low_threshold);
                roi_latched<=i_roi_active; limit_latched<=i_ccl_limit; stale_latched<=i_tracks_stale;
                overflow_latched<=i_overflow_count; underflow_latched<=i_underflow_count;
                inspection_latched<=(i_inspection_active === 1'b1);
                inspection_hold<=(i_inspection_hold === 1'b1);
                inspection_status<=i_inspection_status; inspection_mask<=i_inspection_mask;
                inspection_depth_bcd<=threshold_bcd(i_inspection_depth);
                color_valid_latched<=(i_color_valid === 1'b1);
                color_mean_bcd<=i_color_mean_bcd; color_sat_bcd<=i_color_sat_bcd;
            end

            if (i_de) begin
                if (current_pair == (IMAGE_WIDTH / 2) - 1) begin
                    next_pair <= {PAIR_ADDR_WIDTH{1'b0}};
                    next_row <= current_row + 1'b1;
                end else begin
                    next_pair <= current_pair + 1'b1;
                    next_row <= current_row;
                end
            end
        end
    end

    function [7:0] mode_char;
        input [3:0] mode_value;
        input [2:0] position;
        begin
            mode_char = 8'h20;
            if(mode_value==4 && inspection_latched) begin
                case(position)
                    0: mode_char="C"; 1: mode_char="H"; 2: mode_char="E";
                    3: mode_char="C"; 4: mode_char="K";
                endcase
            end else case (mode_value)
                4'd0: begin
                    case (position)
                        3'd0: mode_char = "R";
                        3'd1: mode_char = "A";
                        3'd2: mode_char = "W";
                        default: mode_char = 8'h20;
                    endcase
                end
                4'd1: begin
                    case (position)
                        3'd0: mode_char = "S";
                        3'd1: mode_char = "O";
                        3'd2: mode_char = "B";
                        3'd3: mode_char = "E";
                        3'd4: mode_char = "L";
                        default: mode_char = 8'h20;
                    endcase
                end
                4'd2: begin
                    case (position)
                        3'd0: mode_char = "C";
                        3'd1: mode_char = "A";
                        3'd2: mode_char = "N";
                        3'd3: mode_char = "N";
                        3'd4: mode_char = "Y";
                        default: mode_char = 8'h20;
                    endcase
                end
                4'd3: begin
                    case (position)
                        3'd0: mode_char = "B";
                        3'd1: mode_char = "O";
                        3'd2: mode_char = "O";
                        3'd3: mode_char = "S";
                        3'd4: mode_char = "T";
                        default: mode_char = 8'h20;
                    endcase
                end
                4'd4: begin
                    case (position)
                        3'd0: mode_char = "S";
                        3'd1: mode_char = "H";
                        3'd2: mode_char = "A";
                        3'd3: mode_char = "P";
                        3'd4: mode_char = "E";
                        default: mode_char = 8'h20;
                    endcase
                end
                4'd5: begin
                    case (position)
                        3'd0: mode_char = "O";
                        3'd1: mode_char = "V";
                        3'd2: mode_char = "R";
                        3'd3: mode_char = "L";
                        3'd4: mode_char = "Y";
                        default: mode_char = 8'h20;
                    endcase
                end
                4'd6: begin
                    case (position)
                        0: mode_char="S"; 1: mode_char="P"; 2: mode_char="L";
                        3: mode_char="I"; 4: mode_char="T";
                    endcase
                end
                4'd7: begin
                    case(position)
                        0:mode_char="C"; 1:mode_char="O"; 2:mode_char="L";
                        3:mode_char="O"; 4:mode_char="R";
                    endcase
                end
                default: begin
                    case (position)
                        3'd0: mode_char = "N";
                        3'd1: mode_char = "/";
                        3'd2: mode_char = "A";
                        default: mode_char = 8'h20;
                    endcase
                end
            endcase
        end
    endfunction

    function [7:0] frame_char;
        input [1:0] state;
        input valid;
        input [2:0] count;
        input [2:0] index;
        input [2:0] position;
        begin
            frame_char = 8'h20;
            case (state)
                2'd1: begin
                    case (position)
                        3'd0: frame_char = "F";
                        3'd1: frame_char = "R";
                        3'd2, 3'd3: frame_char = "E";
                        3'd4: frame_char = "Z";
                        3'd5: frame_char = "E";
                    endcase
                end
                2'd2: begin
                    case (position)
                        3'd0: frame_char = "S";
                        3'd1: frame_char = "A";
                        3'd2: frame_char = "V";
                        3'd3: frame_char = 8'h30 + index;
                        3'd4: frame_char = "/";
                        3'd5: frame_char = 8'h30 + count;
                    endcase
                end
                default: begin
                    case (position)
                        3'd0: frame_char = "L";
                        3'd1: frame_char = "I";
                        3'd2: frame_char = "V";
                        3'd3: frame_char = "E";
                        3'd4: frame_char = ":";
                        3'd5: frame_char = valid ? 8'h30 + count : "-";
                    endcase
                end
            endcase
        end
    endfunction

    function [7:0] status_char;
        input [2:0] line_select;
        input [5:0] char_index;
        reg shape_status_visible;
        reg [35:0] color_values;
        begin
            shape_status_visible = (mode_latched == 4'd4);
            color_values = line_select==1 ? color_mean_bcd : color_sat_bcd;
            status_char = 8'h20;
            if (line_select == 0) begin
                case (char_index)
                    6'd0:  status_char = "F";
                    6'd1:  status_char = "P";
                    6'd2:  status_char = "S";
                    6'd3:  status_char = ":";
                    6'd4:  status_char = {4'b0011, fps_bcd_latched[7:4]};
                    6'd5:  status_char = {4'b0011, fps_bcd_latched[3:0]};
                    6'd8:  status_char = "M";
                    6'd9:  status_char = "O";
                    6'd10: status_char = "D";
                    6'd11: status_char = "E";
                    6'd12: status_char = ":";
                    6'd13, 6'd14, 6'd15, 6'd16, 6'd17:
                        status_char = mode_char(mode_latched, char_index - 6'd13);
                    6'd19, 6'd20, 6'd21, 6'd22, 6'd23, 6'd24:
                        status_char = frame_char(frame_state_latched,
                                                 saved_valid_latched, saved_count_latched,
                                                 saved_index_latched, char_index - 6'd19);
                    default: status_char = 8'h20;
                endcase
            end else if (color_diagnostics_active && (line_select==1 || line_select==2)) begin
                case (char_index)
                    0: status_char=line_select==1 ? "R" : "S";
                    1: status_char=line_select==1 ? "G" : "A";
                    2: status_char=line_select==1 ? "B" : "T";
                    3: status_char=":";
                    4,5,6,8,9,10,12,13,14: begin
                        if (!color_valid_latched) status_char="-";
                        else case (char_index)
                            4: status_char=8'h30+color_values[35:32];
                            5: status_char=8'h30+color_values[31:28];
                            6: status_char=8'h30+color_values[27:24];
                            8: status_char=8'h30+color_values[23:20];
                            9: status_char=8'h30+color_values[19:16];
                            10: status_char=8'h30+color_values[15:12];
                            12: status_char=8'h30+color_values[11:8];
                            13: status_char=8'h30+color_values[7:4];
                            14: status_char=8'h30+color_values[3:0];
                        endcase
                    end
                    15: status_char=line_select==2 ? "%" : " ";
                endcase
            end else if (line_select == 1 && mode_latched==6) begin
                case (char_index)
                    0: status_char="L"; 1,9: status_char=":";
                    2,3,4,5,6: status_char=mode_char({1'b0,compare_left_latched},char_index-2);
                    8: status_char="R";
                    10,11,12,13,14: status_char=mode_char({1'b0,compare_right_latched},char_index-10);
                endcase
            end else if (line_select == 1 && mode_latched==4 && inspection_latched) begin
                case(char_index)
                    0: status_char="C"; 1: status_char="H"; 2: status_char="E";
                    3: status_char="C"; 4: status_char="K"; 5,15: status_char=":";
                    6: status_char=inspection_status==1 ? "O" : inspection_status==2 ? "N" :
                                   inspection_status==3 ? "I" : "W";
                    7: status_char=inspection_status==1 ? "K" : inspection_status==2 ? "G" :
                                   inspection_status==3 ? "N" : "A";
                    8: status_char=inspection_status==3 ? "V" : inspection_status==0 ? "I" : " ";
                    9: status_char=inspection_status==3 ? "A" : inspection_status==0 ? "T" : " ";
                    10: status_char=inspection_status==3 ? "L" : " ";
                    11: status_char=inspection_status==3 ? "I" : " ";
                    12: status_char=inspection_status==3 ? "D" : " ";
                    14: status_char="D";
                    16,17,18,19: status_char=8'h30+inspection_depth_bcd[(19-char_index)*4 +: 4];
                    21: status_char=inspection_mask[0] ? "L" : "-";
                    22: status_char=inspection_mask[1] ? "R" : "-";
                    23: status_char=inspection_mask[2] ? "T" : "-";
                    24: status_char=inspection_mask[3] ? "B" : "-";
                endcase
            end else if (line_select == 1) begin
                case (char_index)
                    6'd0:  status_char = "O";
                    6'd1:  status_char = "B";
                    6'd2:  status_char = "J";
                    6'd3:  status_char = ":";
                    6'd4:  status_char = shape_status_visible ?
                                           (8'h30 + object_count_latched) : "-";
                    6'd6:  status_char = "R";
                    6'd7:  status_char = "E";
                    6'd8:  status_char = "C";
                    6'd9:  status_char = "T";
                    6'd10: status_char = ":";
                    6'd11: status_char = shape_status_visible ?
                                           (shape_mask_latched[0] ? "Y" : "N") : "-";
                    6'd13: status_char = "T";
                    6'd14: status_char = "R";
                    6'd15: status_char = "I";
                    6'd16: status_char = ":";
                    6'd17: status_char = shape_status_visible ?
                                           (shape_mask_latched[1] ? "Y" : "N") : "-";
                    6'd19: status_char = "C";
                    6'd20: status_char = "I";
                    6'd21: status_char = "R";
                    6'd22: status_char = "C";
                    6'd23: status_char = ":";
                    6'd24: status_char = shape_status_visible ?
                                           (shape_mask_latched[2] ? "Y" : "N") : "-";
                    6'd26: status_char = shape_status_visible ? "E" : " ";
                    6'd27,6'd28: status_char = shape_status_visible ? "L" : " ";
                    6'd29: status_char = shape_status_visible ? ":" : " ";
                    6'd30: status_char = shape_status_visible ?
                                           (shape_mask_latched[3] ? "Y" : "N") : " ";
                    6'd32: status_char = shape_status_visible ? "T" : " ";
                    6'd33: status_char = shape_status_visible ? "R" : " ";
                    6'd34: status_char = shape_status_visible ? "A" : " ";
                    6'd35: status_char = shape_status_visible ? "P" : " ";
                    6'd36: status_char = shape_status_visible ? ":" : " ";
                    6'd37: status_char = shape_status_visible ?
                                           (shape_mask_latched[4] ? "Y" : "N") : " ";
                    default: status_char = 8'h20;
                endcase
            end else if (line_select == 2) begin
                case (char_index)
                    0: status_char="H"; 1,8,17: status_char=":";
                    2,3,4,5: status_char=8'h30+high_bcd[(5-char_index)*4 +: 4];
                    7: status_char="L";
                    9,10,11,12: status_char=8'h30+low_bcd[(12-char_index)*4 +: 4];
                    14: status_char="R"; 15: status_char="O"; 16: status_char="I";
                    18: status_char=roi_latched ? "1" : "0";
                endcase
            end else if (line_select == 3) begin
                case (char_index)
                    0: status_char="U"; 1,7: status_char="F";
                    2,8,15,22: status_char=":";
                    3: status_char=hex_char(underflow_latched[7:4]);
                    4: status_char=hex_char(underflow_latched[3:0]);
                    6,19: status_char="O";
                    9: status_char=hex_char(overflow_latched[7:4]);
                    10: status_char=hex_char(overflow_latched[3:0]);
                    12,20: status_char="L"; 13: status_char="I"; 14: status_char="M";
                    16: status_char=shape_status_visible && limit_latched ? "1" : "0";
                    18: status_char="H"; 21: status_char="D";
                    23: status_char=shape_status_visible && (inspection_latched ? inspection_hold : stale_latched) ? "1" : "0";
                endcase
            end
        end
    endfunction

    function [4:0] glyph5x7;
        input [7:0] char_code;
        input [2:0] glyph_row;
        reg [34:0] rows;
        begin
            case (char_code)
                "0": rows = {5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "1": rows = {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2": rows = {5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                "3": rows = {5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4": rows = {5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5": rows = {5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6": rows = {5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7": rows = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8": rows = {5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9": rows = {5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                "A": rows = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "B": rows = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
                "C": rows = {5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "D": rows = {5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E": rows = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F": rows = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "G": rows = {5'b01110,5'b10001,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110};
                "H": rows = {5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "I": rows = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
                "J": rows = {5'b00111,5'b00010,5'b00010,5'b00010,5'b00010,5'b10010,5'b01100};
                "K": rows = {5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "L": rows = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M": rows = {5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N": rows = {5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O": rows = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P": rows = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "R": rows = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S": rows = {5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T": rows = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U": rows = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "W": rows = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b01010};
                "Y": rows = {5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                "V": rows = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                "Z": rows = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b11111};
                ":": rows = {5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
                "-": rows = {5'b00000,5'b00000,5'b00000,5'b01110,5'b00000,5'b00000,5'b00000};
                "/": rows = {5'b00001,5'b00010,5'b00010,5'b00100,5'b01000,5'b01000,5'b10000};
                "%": rows = {5'b11001,5'b11010,5'b00010,5'b00100,5'b01000,5'b01011,5'b10011};
                default: rows = 35'b0;
            endcase
            glyph5x7 = rows[34 - (glyph_row * 5) -: 5];
        end
    endfunction

    function font_pixel;
        input [10:0] pixel_x;
        input [10:0] pixel_y;
        reg [2:0] line_select;
        reg [10:0] relative_x;
        reg [10:0] relative_y;
        reg [5:0] char_index;
        reg [3:0] cell_x;
        reg [2:0] glyph_column;
        reg [2:0] glyph_row;
        reg [7:0] char_code;
        reg [4:0] glyph_bits;
        begin
            font_pixel = 1'b0;
            line_select = 3'd0;
            relative_x = 11'b0;
            relative_y = 11'b0;
            char_index = 6'b0;
            cell_x = 4'b0;
            glyph_column = 3'b0;
            glyph_row = 3'b0;
            char_code = 8'h20;
            glyph_bits = 5'b0;
            if ((pixel_x >= TEXT_X) && (pixel_x < TEXT_X + text_width) &&
                (((pixel_y >= TEXT_Y0) && (pixel_y < TEXT_Y0 + 11'd14)) ||
                 ((pixel_y >= TEXT_Y1) && (pixel_y < TEXT_Y1 + 11'd14)) ||
                 ((pixel_y >= TEXT_Y2) && (pixel_y < TEXT_Y2 + 11'd14)) ||
                 ((pixel_y >= TEXT_Y3) && (pixel_y < TEXT_Y3 + 11'd14)))) begin
                line_select = pixel_y>=TEXT_Y3 ? 3'd3 :
                              pixel_y>=TEXT_Y2 ? 3'd2 : pixel_y>=TEXT_Y1 ? 3'd1 : 3'd0;
                relative_x = pixel_x - TEXT_X;
                case (line_select)
                    1: relative_y=pixel_y-TEXT_Y1;
                    2: relative_y=pixel_y-TEXT_Y2;
                    3: relative_y=pixel_y-TEXT_Y3;
                    default: relative_y=pixel_y-TEXT_Y0;
                endcase
                char_index = relative_x[9:4];
                cell_x = relative_x[3:0];
                if (cell_x < 4'd10) begin
                    glyph_column = cell_x[3:1];
                    glyph_row = relative_y[3:1];
                    char_code = status_char(line_select, char_index);
                    glyph_bits = glyph5x7(char_code, glyph_row);
                    font_pixel = glyph_bits[4 - glyph_column];
                end
            end
        end
    endfunction

    // Keep the output register active even when both overlay layers are hidden.
    wire panel_hit0 = i_de && enable_latched &&
        (current_x0 >= PANEL_X) && (current_x0 < PANEL_X + panel_width) &&
        (current_row >= PANEL_Y) && (current_row < PANEL_Y + PANEL_HEIGHT);
    wire panel_hit1 = i_de && enable_latched &&
        (current_x1 >= PANEL_X) && (current_x1 < PANEL_X + panel_width) &&
        (current_row >= PANEL_Y) && (current_row < PANEL_Y + PANEL_HEIGHT);
    wire text_hit0 = i_de && enable_latched && font_pixel(current_x0, current_row);
    wire text_hit1 = i_de && enable_latched && font_pixel(current_x1, current_row);
    // Green marker surrounds (not modifies) the pre-WB 64x64 sampling region.
    function color_marker;
        input [10:0] x, y;
        integer x0, y0;
        begin
            x0=(IMAGE_WIDTH-64)/2; y0=(IMAGE_HEIGHT-64)/2;
            color_marker=((x==x0-1 || x==x0+64) && y>=y0-1 && y<=y0+64) ||
                         ((y==y0-1 || y==y0+64) && x>=x0-1 && x<=x0+64);
        end
    endfunction
    wire marker_hit0 = i_de && enable_latched && color_diagnostics_active && color_marker(current_x0,current_row);
    wire marker_hit1 = i_de && enable_latched && color_diagnostics_active && color_marker(current_x1,current_row);
    wire [23:0] pixel0 = text_hit0 ? 24'hffffff :
                          panel_hit0 ? 24'h000000 : marker_hit0 ? 24'h00ff00 : i_rgb[47:24];
    wire [23:0] pixel1 = text_hit1 ? 24'hffffff :
                          panel_hit1 ? 24'h000000 : marker_hit1 ? 24'h00ff00 : i_rgb[23:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_vs <= 1'b0;
            o_hs <= 1'b0;
            o_de <= 1'b0;
            o_rgb <= 48'b0;
        end else begin
            o_vs <= i_vs;
            o_hs <= i_hs;
            o_de <= i_de;
            o_rgb <= {pixel0, pixel1};
        end
    end

endmodule
