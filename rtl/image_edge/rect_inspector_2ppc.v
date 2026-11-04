// Single solid rectangle inside a fixed ROI, with bounded tilt/perspective.
// Two robust anchors in each boundary profile locate the ideal straight sides;
// no golden RGB frame, learned contour, BOOST repair, or CCL class is required.
// Inspect local excursions only: uniform changes of size are NOT defects here.
module rect_inspector_2ppc #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer IMAGE_HEIGHT = 1080,
    parameter integer ROI_X_MIN = IMAGE_WIDTH / 4,
    parameter integer ROI_X_MAX = IMAGE_WIDTH * 3 / 4 - 1,
    parameter integer ROI_Y_MIN = IMAGE_HEIGHT / 4,
    parameter integer ROI_Y_MAX = IMAGE_HEIGHT * 3 / 4 - 1,
    parameter integer MIN_WIDTH = 64,
    parameter integer MIN_HEIGHT = 64,
    parameter integer DEFECT_DEPTH = 5,
    parameter integer DEFECT_LENGTH = 6,
    parameter integer CONFIRM_FRAMES = 3,
    parameter integer CORNER_GUARD = 2,
    parameter integer FIT_TOLERANCE = 2,
    parameter integer MAX_SLOPE_Q8 = 128,
    parameter integer JITTER_PIXELS = 2,
    parameter integer RELEASE_FRAMES = 3
) (
    input wire clk, rst_n,
    input wire i_enable, i_clear,
    input wire i_sof, i_sol, i_valid,
    input wire [15:0] i_binary,
    input wire i_raw_sof, i_raw_sol, i_raw_valid,
    output wire o_overlay_valid,
    output wire [5:0] o_overlay_tag,
    // 0 WAIT, 1 OK, 2 NG, 3 INVALID. Mask order: bottom/top/right/left.
    output reg [1:0] o_status,
    output reg [3:0] o_defect_mask,
    output reg [10:0] o_max_depth,
    output reg o_hold
);
    localparam integer RW = ROI_X_MAX - ROI_X_MIN + 1;
    localparam integer RH = ROI_Y_MAX - ROI_Y_MIN + 1;
    localparam integer CW = (RW > RH ? RW : RH) <= 2 ? 1 : $clog2(RW > RH ? RW : RH);
    localparam integer RA = RH <= 2 ? 1 : $clog2(RH);
    localparam integer CA = RW / 2 <= 2 ? 1 : $clog2(RW / 2);
    localparam integer PW = 2 * CW + 1;
    localparam integer HD = 1 << CW;
    localparam integer F = 8;
    localparam integer LW = CW + F + 2;
    localparam integer SP = $clog2(MAX_SLOPE_Q8+1) + 1;
    localparam integer DW = LW + F - 1;
    localparam integer DEN_MAX = (1<<F) + ((MAX_SLOPE_Q8*MAX_SLOPE_Q8+(1<<F)-1)>>F);
    localparam integer DN = CW>$clog2(DEN_MAX+1) ? CW : $clog2(DEN_MAX+1);
    localparam integer SCW = $clog2((RW>RH ? RW : RH)+1);
    localparam integer ANC = CONFIRM_FRAMES<=1 ? 1 : $clog2(CONFIRM_FRAMES+1);
    localparam integer RLC = RELEASE_FRAMES<=1 ? 1 : $clog2(RELEASE_FRAMES+1);
    localparam integer DRAW_MARGIN = 16 * (RELEASE_FRAMES-1) + JITTER_PIXELS;
    localparam integer PAIR_TOLERANCE = 4 * FIT_TOLERANCE;
    localparam [CW:0] PAIR_PIXELS = PAIR_TOLERANCE, POSITION_MARGIN = 2 * JITTER_PIXELS;
    localparam signed [LW:0] PAIR_Q8 = PAIR_TOLERANCE << F;
    localparam [5:0] IDLE=0, CLEAR=1, FETCH=2, COUNT=3, HREAD=4,
        HWRITE=5, NEXT=6, HFETCH=7, HSCAN=8, SETUP=9,
        AFETCH=10, ACOUNT=11, ANEXT=12, ALOCATE=13,
        FITDIV=15, DIVIDE=16, FITBASE=17, FITSTORE=18,
        CSTART=19, CNUM=20, CDEN=21, CDIV=22, CY=23, CSTORE=24,
        VSETUP=25, VFETCH=26, VERIFY=27, VNEXT=28, FINISH=29, RSELECT=30,
        RFETCH=31, RVERIFY=32, RNEXT=33, RDECIDE=34;

    reg [11:0] next_x, next_y;
    wire [11:0] x0 = (i_sof || i_sol) ? 12'd0 : next_x;
    wire [11:0] x1 = x0 + 1'b1;
    wire [11:0] y = i_sof ? 12'd0 : next_y;
    wire roi_inside = i_valid && i_enable && x0 >= ROI_X_MIN &&
        x1 <= ROI_X_MAX && y >= ROI_Y_MIN && y <= ROI_Y_MAX;
    wire e0 = roi_inside && (|i_binary[15:8]);
    wire e1 = roi_inside && (|i_binary[7:0]);
    wire [CW-1:0] rx0 = x0 - ROI_X_MIN;
    wire [CW-1:0] rx1 = x1 - ROI_X_MIN;
    wire [CW-1:0] ry = y - ROI_Y_MIN;
    reg row_seen;
    reg [CW-1:0] row_lo, row_hi;
    wire row_base_seen = !(i_sof || i_sol) && row_seen;
    wire row_seen_now = row_base_seen || e0 || e1;
    wire [CW-1:0] row_lo_now = row_base_seen ? row_lo : e0 ? rx0 : rx1;
    wire [CW-1:0] row_hi_now = e1 ? rx1 : e0 ? rx0 : row_hi;
    wire row_write = roi_inside && x1 == ROI_X_MAX && !i_clear;
    wire [PW-1:0] row_data = {row_seen_now, row_hi_now, row_lo_now};
    reg capture_done;
    reg frame_armed;
    reg border_touched;
    wire capture_allowed = roi_inside && frame_armed && !i_clear;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_x<=0; next_y<=0; row_seen<=0; row_lo<=0; row_hi<=0;
            capture_done<=0; frame_armed<=0; border_touched<=0;
        end else begin
            capture_done<=0;
            if (i_sof) frame_armed<=i_enable && !i_clear;
            if (!i_enable || i_clear) frame_armed<=0;
            if(capture_allowed && y==ROI_Y_MIN && x0==ROI_X_MIN) border_touched<=0;
            if((e0 || e1) && (x0<=ROI_X_MIN+CORNER_GUARD ||
                x1>=ROI_X_MAX-CORNER_GUARD || y<=ROI_Y_MIN+CORNER_GUARD ||
                y>=ROI_Y_MAX-CORNER_GUARD)) border_touched<=1;
            if (i_valid) begin
                if (x1 == IMAGE_WIDTH-1) begin next_x<=0; next_y<=y+1'b1; end
                else begin next_x<=x0+2; next_y<=y; end
                row_seen<=row_seen_now;
                row_lo<=row_lo_now; row_hi<=row_hi_now;
                if (capture_allowed && x1==ROI_X_MAX && y==ROI_Y_MAX)
                    capture_done<=1;
            end
        end
    end

    reg [5:0] state;
    reg [1:0] side;
    reg [CW-1:0] index, hist_index, hist_coord;
    wire [CW:0] profile_count = side < 2 ? RH : RW;
    wire [PW-1:0] row_q, col_q0, col_q1;
    wire [PW-1:0] profile = side < 2 ? row_q : index[0] ? col_q1 : col_q0;
    wire [CW-1:0] p_lo = profile[CW-1:0];
    wire [CW-1:0] p_hi = profile[2*CW-1:CW];
    wire p_valid = profile[PW-1] && p_hi > p_lo;
    wire [CW-1:0] p_coord = side[0] ? p_hi : p_lo;
    true_dual_port_ram #(.DATA_WIDTH(PW), .ADDR_WIDTH(RA), .RAM_INIT_FILE("")) rows (
        .clka(clk), .clkb(clk), .we1(row_write && frame_armed), .we2(1'b0),
        .addr1(ry[RA-1:0]), .addr2(index[RA-1:0]),
        .din1(row_data), .din2({PW{1'b0}}), .dout1(), .dout2(row_q)
    );

    // Even/odd column banks accept both pixels every clock. Port 1 reads the
    // previous row; the following clock port 2 writes the updated extrema.
    // The first ROI row initializes EVERY column, including empty columns.
    wire [CA-1:0] col_read_addr = rx0 >> 1;
    reg cap_pending, cap_first;
    reg [CA-1:0] cap_addr;
    reg [CW-1:0] cap_y;
    reg [1:0] cap_edge;
    wire [PW-1:0] col_old0, col_old1;
    function [PW-1:0] update_column;
        input [PW-1:0] old;
        input first, edge_bit;
        input [CW-1:0] coord;
        reg seen;
        begin
            seen = !first && old[PW-1];
            update_column = first ? {PW{1'b0}} : old;
            if (edge_bit)
                update_column = {1'b1, coord, seen ? old[CW-1:0] : coord};
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_pending<=0; cap_first<=0; cap_addr<=0; cap_y<=0; cap_edge<=0;
        end else begin
            cap_pending<=capture_allowed;
            cap_first<=y==ROI_Y_MIN;
            cap_addr<=col_read_addr; cap_y<=ry; cap_edge<={e1,e0};
            if (!i_enable || i_clear) cap_pending<=0;
        end
    end
    wire [CA-1:0] col_port2_addr = cap_pending ? cap_addr : index >> 1;
    true_dual_port_ram #(.DATA_WIDTH(PW), .ADDR_WIDTH(CA), .RAM_INIT_FILE("")) columns_even (
        .clka(clk), .clkb(clk), .we1(1'b0), .we2(cap_pending),
        .addr1(col_read_addr), .addr2(col_port2_addr), .din1({PW{1'b0}}),
        .din2(update_column(col_old0,cap_first,cap_edge[0],cap_y)),
        .dout1(col_old0), .dout2(col_q0)
    );
    true_dual_port_ram #(.DATA_WIDTH(PW), .ADDR_WIDTH(CA), .RAM_INIT_FILE("")) columns_odd (
        .clka(clk), .clkb(clk), .we1(1'b0), .we2(cap_pending),
        .addr1(col_read_addr), .addr2(col_port2_addr), .din1({PW{1'b0}}),
        .din2(update_column(col_old1,cap_first,cap_edge[1],cap_y)),
        .dout1(col_old1), .dout2(col_q1)
    );

    // The same histogram serves the coarse location and eight robust anchors.
    // A shared serial divider/multiplier fits the four sides after ROI capture.
    // No additional profile or full-frame storage is required.
    wire hist_write = state==CLEAR || state==HWRITE;
    wire [CW-1:0] hist_addr = state==HREAD || state==HWRITE ? hist_coord : hist_index;
    wire [SCW-1:0] hist_q;
    true_dual_port_ram #(.DATA_WIDTH(SCW), .ADDR_WIDTH(CW), .RAM_INIT_FILE("")) histogram (
        .clka(clk), .clkb(clk), .we1(hist_write), .we2(1'b0),
        .addr1(hist_addr), .addr2({CW{1'b0}}),
        .din1(state==CLEAR ? {SCW{1'b0}} : hist_q+1'b1), .din2({SCW{1'b0}}),
        .dout1(hist_q), .dout2()
    );
    reg [SCW-1:0] samples, cumulative, locate_count;
    reg [CW-1:0] reference [0:3];
    reg [SCW-1:0] side_samples [0:3];
    reg fitting, anchor_second, prev_valid, retry_fit, retry_domain;
    reg [3:0] retry_mask;
    reg signed [SP-1:0] old_slope;
    reg signed [LW-1:0] old_base, old_prediction;
    reg [10:0] old_support, new_support;
    reg retry_model_valid;
    reg [CW-1:0] prev_coord, anchor_index, anchor_coord, median_coord;
    reg signed [SP-1:0] slope [0:3];
    reg signed [LW-1:0] base [0:3];
    reg [CW-1:0] side_begin [0:3], side_end [0:3];
    reg signed [SP-1:0] fit_slope;
    wire [SCW:0] cumulative_next = {1'b0,cumulative}+{1'b0,hist_q};
    wire [SCW:0] median_sum = {1'b0,samples}+1'b1;
    wire [SCW-1:0] median_rank = median_sum[SCW:1];
    wire [CW:0] rect_width = {1'b0,reference[1]}-{1'b0,reference[0]}+1'b1;
    wire [CW:0] rect_height = {1'b0,reference[3]}-{1'b0,reference[2]}+1'b1;
    wire geometry_valid = !border_touched && reference[1]>reference[0] && reference[3]>reference[2] &&
        rect_width>=MIN_WIDTH && rect_height>=MIN_HEIGHT &&
        reference[0]>CORNER_GUARD && reference[1]<RW-1-CORNER_GUARD &&
        reference[2]>CORNER_GUARD && reference[3]<RH-1-CORNER_GUARD &&
        (side_samples[0]<<2)>=(rect_height*3) &&
        (side_samples[2]<<2)>=(rect_width*3);
    wire use_side_domain = retry_fit && retry_domain && side_end[side]>side_begin[side]+3;
    wire [CW-1:0] axis_lo = use_side_domain ? side_begin[side] :
        side<2 ? reference[2] : reference[0];
    wire [CW:0] axis_span = use_side_domain ? side_end[side]-side_begin[side] :
        side<2 ? rect_height-1'b1 : rect_width-1'b1;
    wire [CW:0] fit_begin = axis_lo+(retry_fit ?
        (anchor_second ? ((axis_span*7)>>3) : 0) :
        (anchor_second ? ((axis_span*5)>>3) : (axis_span>>3)));
    wire [CW:0] fit_end = axis_lo+(retry_fit ?
        (anchor_second ? axis_span : (axis_span>>3)) :
        (anchor_second ? ((axis_span*7)>>3) : ((axis_span*3)>>3)));
    wire [CW-1:0] adjacent_delta = p_coord>=prev_coord ? p_coord-prev_coord : prev_coord-p_coord;
    wire fit_accept = p_valid && prev_valid && index>=fit_begin && index<=fit_end && adjacent_delta<=1;

    reg signed [SP-1:0] mult_a;
    reg signed [LW-1:0] mult_b;
    wire signed [SP+LW-1:0] mult_product = mult_a*mult_b;
    reg [DW-1:0] div_num, div_quot;
    reg [DN-1:0] div_den, div_rem;
    reg [$clog2(DW+1)-1:0] div_bit;
    reg div_negative;
    reg [5:0] div_return;
    wire [DN:0] div_shift = {div_rem,div_num[DW-1]};
    wire [DW-1:0] div_next_quot = {div_quot[DW-2:0],div_shift>={1'b0,div_den}};
    wire signed [DW-1:0] div_value = div_negative ? -$signed(div_quot) : $signed(div_quot);
    wire signed [CW+1:0] anchor_delta = $signed({1'b0,median_coord})-$signed({1'b0,anchor_coord});
    reg [1:0] corner;
    wire [1:0] corner_v = corner[0] ? 2'd1 : 2'd0;
    wire [1:0] corner_h = corner[1] ? 2'd3 : 2'd2;
    // Store rounded integers; CW+3 also covers rounding the full signed Q8 range.
    reg signed [CW+2:0] corner_x [0:3], corner_y [0:3];
    reg signed [LW-1:0] corner_num, corner_den, corner_result_x;
    wire signed [LW-1:0] corner_result_y = base[corner_h]+(mult_product>>>F);
    reg corners_valid;
    reg signed [LW-1:0] prediction, opposite_prediction;
    wire signed [LW:0] residual = $signed({1'b0,p_coord,{F{1'b0}}})-$signed(prediction);
    wire [LW:0] abs_residual = residual<0 ? -residual : residual;
    wire [10:0] distance = (abs_residual+(1<<(F-1)))>>F;
    wire signed [LW:0] old_residual = $signed({1'b0,p_coord,{F{1'b0}}})-$signed(old_prediction);
    wire [LW:0] old_abs_residual = old_residual<0 ? -old_residual : old_residual;
    wire [10:0] old_distance = (old_abs_residual+(1<<(F-1)))>>F;
    wire signed [LW-1:0] predicted_coord = (prediction+(1<<(F-1)))>>>F;
    // A single/doubled opposite edge is not evidence of this side. Do not
    // cap defect depth: a deep notch with two distinct boundaries stays valid.
    wire signed [LW:0] opposite_residual =
        $signed({1'b0,p_coord,{F{1'b0}}})-$signed(opposite_prediction);
    wire [CW:0] profile_span = {1'b0,p_hi}-{1'b0,p_lo};
    wire association_ambiguous = profile[PW-1] && profile_span<=PAIR_PIXELS &&
        (side[0] ? opposite_residual<=PAIR_Q8 : opposite_residual>= -PAIR_Q8);
    wire sample_valid = p_valid && !association_ambiguous;
    wire eligible = index>=side_begin[side] && index<=side_end[side];
    reg [10:0] run_length, run_depth;
    reg [10:0] missing_run_length;
    reg long_missing;
    reg [CW-1:0] run_start, run_lo, run_hi, run_coord;
    wire [CW:0] run_step = p_coord>=run_coord ?
        {1'b0,p_coord}-{1'b0,run_coord} : {1'b0,run_coord}-{1'b0,p_coord};
    // A remote contour point cannot inherit the length of a real local defect.
    // Stable deep notches start a new run and still qualify without a depth cap.
    wire run_restart = run_length==0 || run_step>PAIR_PIXELS;
    wire [10:0] run_length_next = run_restart ? 11'd1 : run_length+1'b1;
    wire [CW-1:0] sample_lo = $signed({1'b0,p_coord})<predicted_coord ? p_coord : predicted_coord[CW-1:0];
    wire [CW-1:0] sample_hi = $signed({1'b0,p_coord})>predicted_coord ? p_coord : predicted_coord[CW-1:0];
    wire [10:0] run_depth_next = distance>run_depth || run_restart ? distance : run_depth;
    wire [CW-1:0] run_lo_next = run_restart || sample_lo<run_lo ? sample_lo : run_lo;
    wire [CW-1:0] run_hi_next = run_restart || sample_hi>run_hi ? sample_hi : run_hi;
    reg [3:0] work_mask;
    reg [CW-1:0] work_start [0:3], work_end [0:3], work_lo [0:3], work_hi [0:3];
    reg [10:0] work_side_depth [0:3], work_length [0:3];
    reg [10:0] work_depth;
    reg [11:0] checked_count [0:3], missing_count [0:3], support_count [0:3];
    wire quality_valid = corners_valid && !long_missing &&
        checked_count[0]!=0 && checked_count[1]!=0 && checked_count[2]!=0 && checked_count[3]!=0 &&
        (missing_count[0]<<2)<=checked_count[0] && (missing_count[1]<<2)<=checked_count[1] &&
        (missing_count[2]<<2)<=checked_count[2] && (missing_count[3]<<2)<=checked_count[3] &&
        (support_count[0]*5)>=(checked_count[0]*3) && (support_count[1]*5)>=(checked_count[1]*3) &&
        (support_count[2]*5)>=(checked_count[2]*3) && (support_count[3]*5)>=(checked_count[3]*3);
    reg result_ready;
    reg result_hard_invalid;
    reg [1:0] result_status;
    integer s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; side<=0; index<=0; hist_index<=0; hist_coord<=0;
            samples<=0; cumulative<=0; locate_count<=0;
            fitting<=0; anchor_second<=0; prev_valid<=0; prev_coord<=0; retry_fit<=0; retry_domain<=0; retry_mask<=0;
            old_slope<=0; old_base<=0; old_prediction<=0; old_support<=0; new_support<=0; retry_model_valid<=0;
            anchor_index<=0; anchor_coord<=0; median_coord<=0; fit_slope<=0;
            mult_a<=0; mult_b<=0; div_num<=0; div_den<=1; div_quot<=0;
            div_rem<=0; div_bit<=0; div_negative<=0; div_return<=IDLE;
            corner<=0; corner_num<=0; corner_den<=1; corner_result_x<=0; corners_valid<=0;
            prediction<=0; opposite_prediction<=0;
            run_length<=0; run_depth<=0; run_start<=0; run_lo<=0; run_hi<=0; run_coord<=0;
            missing_run_length<=0; long_missing<=0;
            work_mask<=0; work_depth<=0; result_ready<=0; result_status<=0; result_hard_invalid<=1;
            for(s=0;s<4;s=s+1) begin
                reference[s]<=0; side_samples[s]<=0; slope[s]<=0; base[s]<=0;
                corner_x[s]<=0; corner_y[s]<=0; side_begin[s]<=0; side_end[s]<=0;
                work_start[s]<=0; work_end[s]<=0; work_lo[s]<=0; work_hi[s]<=0;
                work_side_depth[s]<=0; work_length[s]<=0;
                checked_count[s]<=0; missing_count[s]<=0; support_count[s]<=0;
            end
        end else if (!i_enable || i_clear) begin
            state<=IDLE; result_ready<=0;
        end else begin
            if (i_raw_sof) result_ready<=0;
            case(state)
                IDLE: if(capture_done) begin
                    side<=0; index<=0; hist_index<=0; samples<=0; cumulative<=0;
                    fitting<=0; anchor_second<=0; retry_fit<=0; retry_domain<=0; retry_mask<=0; work_mask<=0; work_depth<=0;
                    result_ready<=0; corners_valid<=1; long_missing<=0; state<=CLEAR;
                    for(s=0;s<4;s=s+1) begin
                        work_side_depth[s]<=0; work_length[s]<=0;
                        checked_count[s]<=0; missing_count[s]<=0; support_count[s]<=0;
                    end
                end
                CLEAR: begin
                    if(hist_index==HD-1) begin
                        hist_index<=0; index<=0; prev_valid<=0; state<=FETCH;
                    end else hist_index<=hist_index+1'b1;
                end
                FETCH: state<=COUNT;
                COUNT: begin
                    prev_coord<=p_coord; prev_valid<=p_valid;
                    if(p_valid && (!fitting || fit_accept)) begin
                        hist_coord<=p_coord; samples<=samples+1'b1; state<=HREAD;
                    end else state<=NEXT;
                end
                HREAD: state<=HWRITE;
                HWRITE: state<=NEXT;
                NEXT: if(index==profile_count-1) begin
                    if(!fitting) side_samples[side]<=samples;
                    hist_index<=0; cumulative<=0; state<=HFETCH;
                end else begin index<=index+1'b1; state<=FETCH; end
                HFETCH: state<=HSCAN;
                HSCAN: begin
                    cumulative<=cumulative_next[SCW-1:0];
                    if((samples!=0 && cumulative_next>=median_rank) || hist_index==HD-1) begin
                        if(fitting) begin
                            median_coord<=hist_index; index<=0; locate_count<=0; prev_valid<=0;
                            if(samples<2) begin
                                slope[side]<=0; base[side]<=$signed({1'b0,reference[side],{F{1'b0}}});
                                if(retry_fit) retry_model_valid<=0;
                                else corners_valid<=0;
                                state<=FITSTORE;
                            end else state<=AFETCH;
                        end else begin
                            reference[side]<=samples==0 ? {CW{1'b0}} : hist_index;
                            if(side==3) state<=SETUP;
                            else begin side<=side+1'b1; samples<=0; hist_index<=0; state<=CLEAR; end
                        end
                    end else begin hist_index<=hist_index+1'b1; state<=HFETCH; end
                end
                SETUP: begin
                    if(!geometry_valid) begin
                        result_status<=3; result_hard_invalid<=1; result_ready<=1; state<=IDLE;
                    end
                    else begin
                        fitting<=1; side<=0; anchor_second<=0; samples<=0; hist_index<=0; state<=CLEAR;
                    end
                end
                AFETCH: state<=ACOUNT;
                ACOUNT: begin
                    prev_coord<=p_coord; prev_valid<=p_valid;
                    if(fit_accept) begin
                        locate_count<=locate_count+1'b1;
                        if(locate_count+1>=median_rank) begin
                            if(!anchor_second) begin
                                anchor_index<=index; anchor_coord<=median_coord; anchor_second<=1;
                                samples<=0; hist_index<=0; state<=CLEAR;
                            end else state<=FITDIV;
                        end else state<=ANEXT;
                    end else state<=ANEXT;
                end
                ANEXT: begin index<=index+1'b1; state<=AFETCH; end
                FITDIV: begin
                    if(index<=anchor_index+1'b1) begin
                        slope[side]<=0; base[side]<=$signed({1'b0,reference[side],{F{1'b0}}});
                        if(retry_fit) retry_model_valid<=0;
                        else corners_valid<=0;
                        state<=FITSTORE;
                    end else begin
                        div_num<=anchor_delta<0 ? (-$signed(anchor_delta))<<F : $signed(anchor_delta)<<F;
                        div_den<=index-anchor_index; div_negative<=anchor_delta<0;
                        div_quot<=0; div_rem<=0; div_bit<=DW; div_return<=FITBASE; state<=DIVIDE;
                    end
                end
                DIVIDE: begin
                    div_num<=div_num<<1; div_quot<=div_next_quot;
                    div_rem<=div_shift>={1'b0,div_den} ? div_shift-{1'b0,div_den} : div_shift;
                    div_bit<=div_bit-1'b1;
                    if(div_bit==1) state<=div_return;
                end
                FITBASE: begin
                    if(div_value>MAX_SLOPE_Q8 || div_value< -MAX_SLOPE_Q8) begin
                        slope[side]<=0; base[side]<=$signed({1'b0,reference[side],{F{1'b0}}}); state<=FITSTORE;
                    end else begin
                        fit_slope<=div_value[SP-1:0]; mult_a<=div_value[SP-1:0];
                        mult_b<=$signed({1'b0,anchor_index}); state<=ALOCATE;
                    end
                end
                ALOCATE: begin
                    slope[side]<=fit_slope;
                    base[side]<=$signed({1'b0,anchor_coord,{F{1'b0}}})-mult_product;
                    state<=FITSTORE;
                end
                FITSTORE: begin
                    if(retry_fit) begin
                        index<=0; prediction<=base[side]; old_prediction<=old_base;
                        old_support<=0; new_support<=0; state<=RFETCH;
                    end else if(side==3) begin corner<=0; state<=CSTART; end
                    else begin
                        side<=side+1'b1; anchor_second<=0; samples<=0; hist_index<=0;
                        state<=retry_fit ? RSELECT : CLEAR;
                    end
                end
                RSELECT: begin
                    if(retry_mask[side]) begin
                        old_slope<=slope[side]; old_base<=base[side]; retry_model_valid<=1;
                        anchor_second<=0; samples<=0; hist_index<=0; state<=CLEAR;
                    end
                    else if(side==3) begin corner<=0; state<=CSTART; end
                    else side<=side+1'b1;
                end
                RFETCH: state<=RVERIFY;
                RVERIFY: begin
                    // Compare old/new lines on exactly the same complete side
                    // domain. Defect pixels remain in this score and in VERIFY.
                    if(eligible && p_valid) begin
                        if(distance<FIT_TOLERANCE) new_support<=new_support+1'b1;
                        if(old_distance<FIT_TOLERANCE) old_support<=old_support+1'b1;
                    end
                    state<=RNEXT;
                end
                RNEXT: if(index==profile_count-1) state<=RDECIDE;
                    else begin
                        index<=index+1'b1; prediction<=prediction+slope[side];
                        old_prediction<=old_prediction+old_slope; state<=RFETCH;
                    end
                RDECIDE: begin
                    if(use_side_domain && (!retry_model_valid || old_support>=new_support)) begin
                        slope[side]<=old_slope; base[side]<=old_base;
                    end else if(!retry_model_valid) corners_valid<=0;
                    if(side==3) begin corner<=0; state<=CSTART; end
                    else begin side<=side+1'b1; state<=RSELECT; end
                end
                CSTART: begin mult_a<=slope[corner_v]; mult_b<=base[corner_h]; state<=CNUM; end
                CNUM: begin
                    corner_num<=base[corner_v]+(mult_product>>>F);
                    mult_a<=slope[corner_v]; mult_b<=slope[corner_h]; state<=CDEN;
                end
                CDEN: begin corner_den<=(1<<F)-(mult_product>>>F); state<=CDIV; end
                CDIV: begin
                    if(corner_den<=(1<<(F-1)) || corner_num<0) begin
                        corners_valid<=0; corner_result_x<=0; mult_a<=0; mult_b<=0; state<=CSTORE;
                    end else begin
                        div_num<=$signed(corner_num)<<F; div_den<=corner_den;
                        div_negative<=0; div_quot<=0; div_rem<=0; div_bit<=DW; div_return<=CY; state<=DIVIDE;
                    end
                end
                CY: begin
                    corner_result_x<=div_value[LW-1:0];
                    mult_a<=slope[corner_h]; mult_b<=div_value[LW-1:0]; state<=CSTORE;
                end
                CSTORE: begin
                    corner_x[corner]<=(corner_result_x+(1<<(F-1)))>>>F;
                    corner_y[corner]<=(corner_result_y+(1<<(F-1)))>>>F;
                    if(corner_result_x<(CORNER_GUARD<<F) || corner_result_x>((RW-1-CORNER_GUARD)<<F) ||
                        base[corner_h]+(mult_product>>>F)<(CORNER_GUARD<<F) ||
                        base[corner_h]+(mult_product>>>F)>((RH-1-CORNER_GUARD)<<F)) corners_valid<=0;
                    if(corner==3) begin side<=0; state<=VSETUP; end
                    else begin corner<=corner+1'b1; state<=CSTART; end
                end
                VSETUP: begin
                    // Four fitted intersections delimit actual sides, including
                    // near-corner defects; only a 1-2 px raster guard is removed.
                    side_begin[0]<=corner_y[0]+CORNER_GUARD;
                    side_end[0]<=corner_y[2]-CORNER_GUARD;
                    side_begin[1]<=corner_y[1]+CORNER_GUARD;
                    side_end[1]<=corner_y[3]-CORNER_GUARD;
                    side_begin[2]<=corner_x[0]+CORNER_GUARD;
                    side_end[2]<=corner_x[1]-CORNER_GUARD;
                    side_begin[3]<=corner_x[2]+CORNER_GUARD;
                    side_end[3]<=corner_x[3]-CORNER_GUARD;
                    index<=0; prediction<=base[side]; opposite_prediction<=base[side^2'd1];
                    run_length<=0; run_depth<=0;
                    missing_run_length<=0; state<=VFETCH;
                end
                VFETCH: state<=VERIFY;
                VERIFY: begin
                    if(eligible) begin
                        checked_count[side]<=checked_count[side]+1'b1;
                        if(!sample_valid) missing_count[side]<=missing_count[side]+1'b1;
                        else if(distance<=FIT_TOLERANCE) support_count[side]<=support_count[side]+1'b1;
                    end
                    if(eligible && !sample_valid) begin
                        missing_run_length<=missing_run_length+1'b1;
                        // A missing interval as long as a detectable defect is
                        // insufficient evidence for OK, even if most of the side fits.
                        if(missing_run_length+1>=DEFECT_LENGTH) long_missing<=1;
                    end else missing_run_length<=0;
                    if(eligible && sample_valid && distance>=DEFECT_DEPTH) begin
                        if(run_restart) run_start<=index;
                        run_length<=run_length_next; run_depth<=run_depth_next; run_coord<=p_coord;
                        run_lo<=run_lo_next; run_hi<=run_hi_next;
                        if(run_length_next>=DEFECT_LENGTH &&
                            (run_depth_next>work_side_depth[side] ||
                             (run_depth_next==work_side_depth[side] && run_length_next>=work_length[side]))) begin
                            work_mask[side]<=1; work_start[side]<=run_restart ? index : run_start;
                            work_end[side]<=index; work_lo[side]<=run_lo_next; work_hi[side]<=run_hi_next;
                            work_side_depth[side]<=run_depth_next; work_length[side]<=run_length_next;
                            if(run_depth_next>work_depth) work_depth<=run_depth_next;
                        end
                    end else begin run_length<=0; run_depth<=0; end
                    state<=VNEXT;
                end
                VNEXT: if(index==profile_count-1) begin
                    if(side==3) state<=FINISH;
                    else begin side<=side+1'b1; state<=VSETUP; end
                end else begin
                    index<=index+1'b1; prediction<=prediction+slope[side];
                    opposite_prediction<=opposite_prediction+slope[side^2'd1]; state<=VFETCH;
                end
                FINISH: begin
                    if((!quality_valid || work_mask!=0) && !retry_fit && !long_missing) begin
                        // A defect may occupy most of one fitting bin. Retry
                        // with narrow outer bins, then recheck ALL side pixels.
                        // No fit is accepted merely because its anchors agree.
                        retry_fit<=1; retry_domain<=corners_valid;
                        side<=0; anchor_second<=0; samples<=0;
                        hist_index<=0; corners_valid<=1; work_mask<=0; work_depth<=0;
                        for(s=0;s<4;s=s+1) begin
                            retry_mask[s]<=work_mask[s] || !corners_valid || checked_count[s]==0 ||
                                (missing_count[s]<<2)>checked_count[s] ||
                                (support_count[s]*5)<(checked_count[s]*3);
                            work_side_depth[s]<=0; work_length[s]<=0;
                            checked_count[s]<=0; missing_count[s]<=0; support_count[s]<=0;
                        end
                        state<=RSELECT;
                    end else begin
                        result_status <= !quality_valid ? 2'd3 : work_mask!=0 ? 2'd2 : 2'd1;
                        result_hard_invalid <= !geometry_valid || !corners_valid;
                        result_ready<=1; state<=IDLE;
                    end
                end
                default: state<=IDLE;
            endcase
            // Never publish a result from profiles overwritten by new capture.
            if(capture_allowed && y==ROI_Y_MIN && x0==ROI_X_MIN && state!=IDLE) begin
                state<=IDLE; result_status<=3; result_hard_invalid<=1; result_ready<=1;
            end
        end
    end

    reg published_valid;
    reg signed [SP-1:0] pub_slope [0:3];
    reg signed [LW-1:0] pub_base [0:3];
    reg [11:0] pub_ref [0:3];
    reg [CW-1:0] pub_begin [0:3], pub_end [0:3];
    reg signed [CW+2:0] pub_corner_x [0:3], pub_corner_y [0:3];
    reg [11:0] pub_l [0:3], pub_r [0:3], pub_t [0:3], pub_b [0:3];
    reg [10:0] pub_depth [0:3];
    reg [ANC-1:0] assert_count [0:3];
    reg [RLC-1:0] release_count [0:3];
    reg [CW-1:0] candidate_start [0:3], candidate_end [0:3];
    reg [ANC-1:0] ok_count;
    reg [1:0] soft_loss_count;
    wire [3:0] next_confirmed_mask;
    wire [3:0] held_mask;
    wire [3:0] same_candidate;
    wire [11:0] next_l [0:3], next_r [0:3], next_t [0:3], next_b [0:3];
    wire [3:0] same_box;
    wire [11:0] current_ref [0:3];
    wire [11:0] moved_l [0:3], moved_r [0:3], moved_t [0:3], moved_b [0:3];
    wire [3:0] close_corners;
    // Translation is shared by all four drawing boxes; classification still
    // uses the fresh, unstabilized contour and both side-relative endpoints.
    wire signed [13:0] move_dx =
        ($signed({2'b0,current_ref[0]})+$signed({2'b0,current_ref[1]})-
         $signed({2'b0,pub_ref[0]})-$signed({2'b0,pub_ref[1]})) >>> 1;
    wire signed [13:0] move_dy =
        ($signed({2'b0,current_ref[2]})+$signed({2'b0,current_ref[3]})-
         $signed({2'b0,pub_ref[2]})-$signed({2'b0,pub_ref[3]})) >>> 1;
    function [11:0] moved_coord;
        input [11:0] coord;
        input signed [13:0] delta;
        input integer lower, upper;
        reg signed [14:0] value;
        begin
            value=$signed({3'b0,coord})+delta;
            // A central ROI has enough 12-bit headroom for the bounded hold
            // translation. Rendering already clips to ROI, so no 16 parallel
            // ROI clamp muxes are needed. Keep saturation for edge-adjacent ROI.
            if(lower>=DRAW_MARGIN && upper+DRAW_MARGIN<4096)
                moved_coord=value[11:0];
            else moved_coord=value<lower ? lower : value>upper ? upper : value[11:0];
        end
    endfunction
    function close_corner;
        input signed [CW+2:0] a,b;
        reg signed [CW+3:0] delta;
        begin
            delta=$signed(a)-$signed(b);
            close_corner=delta>= -JITTER_PIXELS && delta<=JITTER_PIXELS;
        end
    endfunction
    function close_endpoint;
        input [CW-1:0] a,b;
        reg signed [CW:0] delta;
        begin
            delta=$signed({1'b0,a})-$signed({1'b0,b});
            close_endpoint=delta>= -$signed(POSITION_MARGIN) && delta<=$signed(POSITION_MARGIN);
        end
    endfunction
    function close_box_coord;
        input [11:0] a,b;
        reg signed [12:0] delta;
        begin
            delta=$signed({1'b0,a})-$signed({1'b0,b});
            close_box_coord=delta>= -JITTER_PIXELS && delta<=JITTER_PIXELS;
        end
    endfunction
    genvar g;
    generate for(g=0;g<4;g=g+1) begin: confirmed_sides
        assign current_ref[g] = reference[g]+(g<2 ? ROI_X_MIN : ROI_Y_MIN);
        assign close_corners[g] = close_corner(corner_x[g],pub_corner_x[g]) &&
            close_corner(corner_y[g],pub_corner_y[g]);
        assign held_mask[g] = o_defect_mask[g] && release_count[g]<RELEASE_FRAMES-1;
        assign moved_l[g] = moved_coord(pub_l[g],move_dx,ROI_X_MIN,ROI_X_MAX);
        assign moved_r[g] = moved_coord(pub_r[g],move_dx,ROI_X_MIN,ROI_X_MAX);
        assign moved_t[g] = moved_coord(pub_t[g],move_dy,ROI_Y_MIN,ROI_Y_MAX);
        assign moved_b[g] = moved_coord(pub_b[g],move_dy,ROI_Y_MIN,ROI_Y_MAX);
        // Match both side-relative endpoints: a long interval overlapping a
        // short corner defect must not inherit its confirmed identity.
        wire [CW-1:0] current_start = work_start[g]-side_begin[g];
        wire [CW-1:0] current_end = work_end[g]-side_begin[g];
        assign same_candidate[g] = (assert_count[g]!=0 || o_defect_mask[g]) &&
            close_endpoint(current_start,candidate_start[g]) &&
            close_endpoint(current_end,candidate_end[g]);
        assign next_confirmed_mask[g] = (geometry_jump || (work_mask[g] && !same_candidate[g])) ?
            (work_mask[g] && CONFIRM_FRAMES<=1) : work_mask[g] ?
            (o_defect_mask[g] || CONFIRM_FRAMES<=1 || assert_count[g]>=CONFIRM_FRAMES-1) :
            (o_defect_mask[g] && release_count[g]<RELEASE_FRAMES-1);
        assign next_l[g] = g<2 ?
            (work_lo[g]>2 ? ROI_X_MIN+work_lo[g]-2 : ROI_X_MIN) :
            (work_start[g]>2 ? ROI_X_MIN+work_start[g]-2 : ROI_X_MIN);
        assign next_r[g] = g<2 ?
            (work_hi[g]+2<RW ? ROI_X_MIN+work_hi[g]+2 : ROI_X_MAX) :
            (work_end[g]+2<RW ? ROI_X_MIN+work_end[g]+2 : ROI_X_MAX);
        assign next_t[g] = g<2 ?
            (work_start[g]>2 ? ROI_Y_MIN+work_start[g]-2 : ROI_Y_MIN) :
            (work_lo[g]>2 ? ROI_Y_MIN+work_lo[g]-2 : ROI_Y_MIN);
        assign next_b[g] = g<2 ?
            (work_end[g]+2<RH ? ROI_Y_MIN+work_end[g]+2 : ROI_Y_MAX) :
            (work_hi[g]+2<RH ? ROI_Y_MIN+work_hi[g]+2 : ROI_Y_MAX);
        // Deadband after common translation: real movement follows the object,
        // while <=2-pixel local sizing jitter does not resize the drawing.
        assign same_box[g] = o_defect_mask[g] && same_candidate[g] && !geometry_jump &&
            close_box_coord(next_l[g],moved_l[g]) && close_box_coord(next_r[g],moved_r[g]) &&
            close_box_coord(next_t[g],moved_t[g]) && close_box_coord(next_b[g],moved_b[g]);
    end endgenerate
    function near_reference;
        input [11:0] a,b;
        begin near_reference = a>=b ? a-b<=16 : b-a<=16; end
    endfunction
    wire geometry_jump = published_valid &&
        (!near_reference(reference[0]+ROI_X_MIN,pub_ref[0]) ||
         !near_reference(reference[1]+ROI_X_MIN,pub_ref[1]) ||
         !near_reference(reference[2]+ROI_Y_MIN,pub_ref[2]) ||
         !near_reference(reference[3]+ROI_Y_MIN,pub_ref[3]) ||
         slope[0]-pub_slope[0]>26 || pub_slope[0]-slope[0]>26 ||
         slope[1]-pub_slope[1]>26 || pub_slope[1]-slope[1]>26 ||
         slope[2]-pub_slope[2]>26 || pub_slope[2]-slope[2]>26 ||
         slope[3]-pub_slope[3]>26 || pub_slope[3]-slope[3]>26);
    reg [10:0] confirmed_depth;
    reg [10:0] held_depth;
    integer d;
    always @* begin
        confirmed_depth=0;
        held_depth=0;
        for(d=0;d<4;d=d+1) begin
            if(held_mask[d] && pub_depth[d]>held_depth) held_depth=pub_depth[d];
            if(next_confirmed_mask[d]) begin
                if(work_mask[d] && work_side_depth[d]>confirmed_depth) confirmed_depth=work_side_depth[d];
                else if(!work_mask[d] && pub_depth[d]>confirmed_depth) confirmed_depth=pub_depth[d];
            end
        end
    end
    wire same_geometry = published_valid && (&close_corners);
    integer p;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            o_status<=0; o_defect_mask<=0; o_max_depth<=0; o_hold<=0;
            ok_count<=0; published_valid<=0; soft_loss_count<=0;
            for(p=0;p<4;p=p+1) begin
                pub_slope[p]<=0; pub_base[p]<=0; pub_ref[p]<=0; pub_begin[p]<=0; pub_end[p]<=0;
                pub_corner_x[p]<=0; pub_corner_y[p]<=0;
                pub_l[p]<=0; pub_r[p]<=0; pub_t[p]<=0; pub_b[p]<=0; pub_depth[p]<=0;
                assert_count[p]<=0; release_count[p]<=0;
                candidate_start[p]<=0; candidate_end[p]<=0;
            end
        end else if(!i_enable || i_clear) begin
            o_status<=0; o_defect_mask<=0; o_max_depth<=0; o_hold<=0;
            ok_count<=0; published_valid<=0; soft_loss_count<=0;
            for(p=0;p<4;p=p+1) begin assert_count[p]<=0; release_count[p]<=0; end
        end else if(i_raw_sof) begin
            if(!result_ready || result_status==3) begin
                // Soft quality loss may keep same-object drawing for TWO
                // frames, explicitly WAIT/HOLD; an old OK is never retained.
                // Hard loss/context change/timeout still clears immediately.
                ok_count<=0;
                if(result_ready && !result_hard_invalid && published_valid &&
                   !geometry_jump && soft_loss_count<2) begin
                    o_status<=0; o_hold<=1; soft_loss_count<=soft_loss_count+1'b1;
                    o_defect_mask<=held_mask; o_max_depth<=held_depth;
                    for(p=0;p<4;p=p+1) begin
                        assert_count[p]<=held_mask[p] ? assert_count[p] : 0;
                        release_count[p]<=release_count[p]<RELEASE_FRAMES ? release_count[p]+1'b1 : release_count[p];
                    end
                end else begin
                    o_status<=3; o_hold<=0; o_defect_mask<=0; o_max_depth<=0;
                    published_valid<=0; soft_loss_count<=0;
                    for(p=0;p<4;p=p+1) begin assert_count[p]<=0; release_count[p]<=0; end
                end
            end else begin
                // Publication is frame-atomic. Candidate side changes cannot
                // erase another confirmed side or redraw unconfirmed red boxes.
                published_valid<=1; soft_loss_count<=0;
                o_hold<=|(next_confirmed_mask & ~work_mask);
                for(p=0;p<4;p=p+1) begin
                    pub_ref[p]<=current_ref[p];
                    if(!same_geometry) begin
                        pub_slope[p]<=slope[p]; pub_base[p]<=base[p];
                        pub_corner_x[p]<=corner_x[p]; pub_corner_y[p]<=corner_y[p];
                        pub_begin[p]<=side_begin[p]; pub_end[p]<=side_end[p];
                    end
                    assert_count[p]<=(geometry_jump || (work_mask[p] && !same_candidate[p])) ? (work_mask[p] ? 8'd1 : 8'd0) : work_mask[p] ?
                        (assert_count[p]<CONFIRM_FRAMES ? assert_count[p]+1'b1 : assert_count[p]) : 0;
                    release_count[p]<=geometry_jump ? 8'd0 : !work_mask[p] ?
                        (release_count[p]<RELEASE_FRAMES ? release_count[p]+1'b1 : release_count[p]) : 0;
                    if(work_mask[p] && (geometry_jump || !same_candidate[p] || next_confirmed_mask[p])) begin
                        // Keep the first candidate as the anchor until confirmation;
                        // otherwise small consecutive shifts can chain into a new defect.
                        candidate_start[p]<=work_start[p]-side_begin[p];
                        candidate_end[p]<=work_end[p]-side_begin[p];
                    end
                    if(work_mask[p] && next_confirmed_mask[p]) begin
                        pub_depth[p]<=work_side_depth[p];
                        if(same_box[p]) begin
                            pub_l[p]<=moved_l[p]; pub_r[p]<=moved_r[p];
                            pub_t[p]<=moved_t[p]; pub_b[p]<=moved_b[p];
                        end else begin
                            pub_l[p]<=next_l[p]; pub_r[p]<=next_r[p];
                            pub_t[p]<=next_t[p]; pub_b[p]<=next_b[p];
                        end
                    end else if(next_confirmed_mask[p] && !geometry_jump) begin
                        pub_l[p]<=moved_l[p]; pub_r[p]<=moved_r[p];
                        pub_t[p]<=moved_t[p]; pub_b[p]<=moved_b[p];
                    end
                end
                o_defect_mask<=next_confirmed_mask;
                o_max_depth<=next_confirmed_mask!=0 ? confirmed_depth : 11'd0;
                ok_count<=geometry_jump ? (work_mask==0 ? 8'd1 : 8'd0) :
                    work_mask==0 ? (ok_count<CONFIRM_FRAMES ? ok_count+1'b1 : ok_count) : 0;
                o_status<=next_confirmed_mask!=0 ? 2'd2 : work_mask!=0 ? 2'd0 :
                    (CONFIRM_FRAMES<=1 || (!geometry_jump && ok_count>=CONFIRM_FRAMES-1)) ? 2'd1 : 2'd0;
            end
        end
    end

    reg [11:0] raw_next_x, raw_next_y;
    wire [11:0] raw_x0 = i_raw_sof || i_raw_sol ? 12'd0 : raw_next_x;
    wire [11:0] raw_y = i_raw_sof ? 12'd0 : raw_next_y;
    reg signed [LW-1:0] render_v [0:1], render_h [0:1];
    integer r;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            raw_next_x<=0; raw_next_y<=0;
            for(r=0;r<2;r=r+1) begin render_v[r]<=0; render_h[r]<=0; end
        end else if(i_raw_valid) begin
            if(raw_x0==IMAGE_WIDTH-2) begin raw_next_x<=0; raw_next_y<=raw_y+1'b1; end
            else begin raw_next_x<=raw_x0+2; raw_next_y<=raw_y; end
            for(r=0;r<2;r=r+1) begin
                if(raw_y<ROI_Y_MIN || (raw_y==ROI_Y_MIN && raw_x0==0)) render_v[r]<=pub_base[r];
                else if(raw_x0==IMAGE_WIDTH-2) render_v[r]<=render_v[r]+pub_slope[r];
                if(raw_x0<ROI_X_MIN) render_h[r]<=pub_base[r+2];
                else render_h[r]<=render_h[r]+($signed({{(LW-SP){pub_slope[r+2][SP-1]}},pub_slope[r+2]})<<<1);
            end
        end
    end
    function box_pixel;
        input [11:0] x,y,l,r,t,b;
        begin
            box_pixel=x>=l && x<=r && y>=t && y<=b &&
                (x<=l+1 || x+1>=r || y<=t+1 || y+1>=b);
        end
    endfunction
    function on_line;
        input signed [CW+1:0] pixel;
        input signed [LW-1:0] line_q;
        reg signed [CW+1:0] q;
        reg signed [CW+1:0] one;
        begin
            // abs(256*pixel-line_q)<=256, without a wide per-pixel subtract.
            // Arithmetic shift gives floor even for a negative line position.
            q=line_q>>>F; one=1;
            on_line=pixel==q || pixel==q+one ||
                (line_q[F-1:0]==0 && pixel==q-one);
        end
    endfunction
    function roi_dash_pixel;
        input [11:0] x,y;
        reg [11:0] relative_x,relative_y;
        begin
            relative_x=x-ROI_X_MIN; relative_y=y-ROI_Y_MIN;
            roi_dash_pixel=x>=ROI_X_MIN && x<=ROI_X_MAX &&
                y>=ROI_Y_MIN && y<=ROI_Y_MAX &&
                (((y<=ROI_Y_MIN+1 || y+1>=ROI_Y_MAX) && !relative_x[4]) ||
                 ((x<=ROI_X_MIN+1 || x+1>=ROI_X_MAX) && !relative_y[4]));
        end
    endfunction
    function [2:0] overlay;
        input [11:0] x,y;
        input lane;
        reg signed [CW+1:0] px, py;
        reg signed [LW-1:0] line_q;
        reg line_pixel;
        integer k;
        begin
            overlay=0; line_pixel=0;
            px=$signed({1'b0,x})-ROI_X_MIN;
            py=$signed({1'b0,y})-ROI_Y_MIN;
            if(roi_dash_pixel(x,y)) overlay=6;
            if(x>=ROI_X_MIN && x<=ROI_X_MAX && y>=ROI_Y_MIN && y<=ROI_Y_MAX) begin
                for(k=0;k<4;k=k+1) begin
                    if(k<2) begin
                        if(y-ROI_Y_MIN>=pub_begin[k] && y-ROI_Y_MIN<=pub_end[k] &&
                            on_line(px,render_v[k])) line_pixel=1;
                    end else begin
                        line_q=render_h[k-2]+(lane ?
                            $signed({{(LW-SP){pub_slope[k][SP-1]}},pub_slope[k]}) : $signed({LW{1'b0}}));
                        if(x-ROI_X_MIN>=pub_begin[k] && x-ROI_X_MIN<=pub_end[k] &&
                            on_line(py,line_q)) line_pixel=1;
                    end
                    if((o_status==2 || o_hold) && o_defect_mask[k] && box_pixel(x,y,pub_l[k],pub_r[k],pub_t[k],pub_b[k])) overlay=4;
                end
                if(published_valid && line_pixel && overlay!=4)
                    overlay=o_status==1 ? 3'd5 : (o_status==2 || (o_hold && o_defect_mask!=0)) ? 3'd3 : 3'd6;
            end
        end
    endfunction
    assign o_overlay_valid=i_raw_valid;
    assign o_overlay_tag={overlay(raw_x0,raw_y,1'b0),overlay(raw_x0+1'b1,raw_y,1'b1)};
endmodule
