module shape_track_filter #(
    parameter integer MAX_OBJECTS = 4,
    parameter integer CONFIRM_FRAMES = 2,
    parameter integer CHANGE_FRAMES = 3,
    parameter integer HOLD_MISSES = 2
) (
    input wire clk,
    input wire rst_n,
    input wire i_clear,
    input wire i_update,
    input wire i_overflow,
    input wire [3:0] i_count,
    input wire [MAX_OBJECTS*3-1:0] i_class,
    input wire [MAX_OBJECTS*12-1:0] i_x_min, i_x_max, i_y_min, i_y_max,
    output reg [3:0] o_count,
    output reg [4:0] o_shape_mask,
    output reg [MAX_OBJECTS*3-1:0] o_class,
    output reg [MAX_OBJECTS*12-1:0] o_x_min, o_x_max, o_y_min, o_y_max,
    output reg o_stale,
    output wire o_busy
);
    localparam integer INDEX_WIDTH = MAX_OBJECTS <= 2 ? 1 : $clog2(MAX_OBJECTS);
    localparam [2:0] IDLE=0, SCAN=1, APPLY=2, AGE=3, COMMIT=4;
    reg [2:0] state;
    reg [INDEX_WIDTH-1:0] detection_index, scan_index, best_index;
    reg [3:0] detection_count;
    reg [14:0] best_distance;
    reg best_valid;
    reg valid [0:MAX_OBJECTS-1];
    reg seen [0:MAX_OBJECTS-1];
    reg [2:0] stable_class [0:MAX_OBJECTS-1];
    reg [2:0] candidate_class [0:MAX_OBJECTS-1];
    reg [2:0] votes [0:MAX_OBJECTS-1];
    reg [2:0] misses [0:MAX_OBJECTS-1];
    reg [11:0] x_min [0:MAX_OBJECTS-1], x_max [0:MAX_OBJECTS-1];
    reg [11:0] y_min [0:MAX_OBJECTS-1], y_max [0:MAX_OBJECTS-1];
    reg [MAX_OBJECTS*3-1:0] classes;
    reg [MAX_OBJECTS*12-1:0] xs0, xs1, ys0, ys1;
    wire [2:0] new_class = classes[detection_index*3 +: 3];
    wire [11:0] new_x0 = xs0[detection_index*12 +: 12];
    wire [11:0] new_x1 = xs1[detection_index*12 +: 12];
    wire [11:0] new_y0 = ys0[detection_index*12 +: 12];
    wire [11:0] new_y1 = ys1[detection_index*12 +: 12];
    wire [12:0] new_cx = {1'b0,new_x0}+new_x1;
    wire [12:0] new_cy = {1'b0,new_y0}+new_y1;
    wire [12:0] old_cx = {1'b0,x_min[scan_index]}+x_max[scan_index];
    wire [12:0] old_cy = {1'b0,y_min[scan_index]}+y_max[scan_index];
    wire [12:0] dx = new_cx>=old_cx ? new_cx-old_cx : old_cx-new_cx;
    wire [12:0] dy = new_cy>=old_cy ? new_cy-old_cy : old_cy-new_cy;
    wire [14:0] distance = {2'b0,dx}+{2'b0,dy};
    wire [12:0] new_width = {1'b0,new_x1}-new_x0+1'b1;
    wire [12:0] new_height = {1'b0,new_y1}-new_y0+1'b1;
    wire [12:0] old_width = {1'b0,x_max[scan_index]}-x_min[scan_index]+1'b1;
    wire [12:0] old_height = {1'b0,y_max[scan_index]}-y_min[scan_index]+1'b1;
    wire [12:0] match_width = new_width>old_width ? new_width : old_width;
    wire [12:0] match_height = new_height>old_height ? new_height : old_height;
    wire match = valid[scan_index] && !seen[scan_index] &&
                 new_x0<=x_max[scan_index] && x_min[scan_index]<=new_x1 &&
                 new_y0<=y_max[scan_index] && y_min[scan_index]<=new_y1 &&
                 dx<=match_width && dy<=match_height &&
                 ({1'b0,new_width} <= {old_width,1'b0}) &&
                 ({1'b0,old_width} <= {new_width,1'b0}) &&
                 ({1'b0,new_height} <= {old_height,1'b0}) &&
                 ({1'b0,old_height} <= {new_height,1'b0});
    integer reset_index, free_index;
    reg free_valid;
    reg [INDEX_WIDTH-1:0] free_slot;
    always @(*) begin
        free_valid=0; free_slot=0;
        for (free_index=0; free_index<MAX_OBJECTS; free_index=free_index+1)
            if (!valid[free_index] && !free_valid) begin
                free_valid=1; free_slot=free_index;
            end
    end
    wire [INDEX_WIDTH-1:0] apply_slot = best_valid ? best_index : free_slot;
    assign o_busy = state != IDLE;

    // Matching is sequential: one comparison per cycle, not an all-pairs
    // combinational matrix. Only object descriptors are retained between frames.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; detection_index<=0; scan_index<=0; best_index<=0;
            detection_count<=0; best_distance<=15'h7fff; best_valid<=0;
            classes<=0; xs0<=0; xs1<=0; ys0<=0; ys1<=0;
            o_count<=0; o_shape_mask<=0; o_class<=0; o_stale<=0;
            o_x_min<=0; o_x_max<=0; o_y_min<=0; o_y_max<=0;
            for (reset_index=0; reset_index<MAX_OBJECTS; reset_index=reset_index+1) begin
                valid[reset_index]<=0; seen[reset_index]<=0;
                stable_class[reset_index]<=0; candidate_class[reset_index]<=0;
                votes[reset_index]<=0; misses[reset_index]<=0;
                x_min[reset_index]<=0; x_max[reset_index]<=0;
                y_min[reset_index]<=0; y_max[reset_index]<=0;
            end
        end else if (i_clear) begin
            state<=IDLE;
            o_count<=0; o_shape_mask<=0; o_class<=0; o_stale<=0;
            o_x_min<=0; o_x_max<=0; o_y_min<=0; o_y_max<=0;
            for (reset_index=0; reset_index<MAX_OBJECTS; reset_index=reset_index+1) begin
                valid[reset_index]<=0; seen[reset_index]<=0;
                stable_class[reset_index]<=0; candidate_class[reset_index]<=0;
                votes[reset_index]<=0; misses[reset_index]<=0;
            end
        end else begin
            case (state)
                IDLE: if (i_update) begin
                    classes<=i_class; xs0<=i_x_min; xs1<=i_x_max;
                    ys0<=i_y_min; ys1<=i_y_max;
                    detection_count<=i_overflow ? 4'd0 : i_count;
                    detection_index<=0; scan_index<=0;
                    best_valid<=0; best_distance<=15'h7fff;
                    for (reset_index=0; reset_index<MAX_OBJECTS; reset_index=reset_index+1)
                        seen[reset_index]<=0;
                    state<=(!i_overflow && i_count!=0) ? SCAN : AGE;
                end
                SCAN: begin
                    if (match && (!best_valid || distance<best_distance)) begin
                        best_valid<=1; best_index<=scan_index; best_distance<=distance;
                    end
                    if (scan_index==MAX_OBJECTS-1) state<=APPLY;
                    else scan_index<=scan_index+1'b1;
                end
                APPLY: begin
                    if ((new_class>=1 && new_class<=5) && (best_valid || free_valid)) begin
                        valid[apply_slot]<=1; seen[apply_slot]<=1; misses[apply_slot]<=0;
                        x_min[apply_slot]<=new_x0; x_max[apply_slot]<=new_x1;
                        y_min[apply_slot]<=new_y0; y_max[apply_slot]<=new_y1;
                        if (!best_valid) begin
                            stable_class[apply_slot]<=0;
                            candidate_class[apply_slot]<=new_class; votes[apply_slot]<=1;
                        end else if (new_class==stable_class[apply_slot]) begin
                            candidate_class[apply_slot]<=new_class; votes[apply_slot]<=0;
                        end else if (new_class!=candidate_class[apply_slot]) begin
                            candidate_class[apply_slot]<=new_class; votes[apply_slot]<=1;
                        end else if (votes[apply_slot]+1 >=
                            (stable_class[apply_slot]==0 ? CONFIRM_FRAMES : CHANGE_FRAMES)) begin
                            stable_class[apply_slot]<=new_class; votes[apply_slot]<=0;
                        end else votes[apply_slot]<=votes[apply_slot]+1'b1;
                    end
                    scan_index<=0; best_valid<=0; best_distance<=15'h7fff;
                    if (detection_index+1 >= detection_count) state<=AGE;
                    else begin detection_index<=detection_index+1'b1; state<=SCAN; end
                end
                AGE: begin
                    if (valid[scan_index] && !seen[scan_index]) begin
                        votes[scan_index]<=0; candidate_class[scan_index]<=stable_class[scan_index];
                        if (stable_class[scan_index]==0 || misses[scan_index]+1>=HOLD_MISSES) begin
                            valid[scan_index]<=0; stable_class[scan_index]<=0;
                        end else misses[scan_index]<=misses[scan_index]+1'b1;
                    end
                    if (scan_index==MAX_OBJECTS-1) state<=COMMIT;
                    else scan_index<=scan_index+1'b1;
                end
                COMMIT: begin
                    o_count<=compact_count; o_shape_mask<=compact_mask;
                    o_class<=compact_class; o_stale<=compact_stale;
                    o_x_min<=compact_x0; o_x_max<=compact_x1;
                    o_y_min<=compact_y0; o_y_max<=compact_y1;
                    state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end

    integer output_index;
    reg [3:0] compact_count;
    reg [4:0] compact_mask;
    reg [MAX_OBJECTS*3-1:0] compact_class;
    reg [MAX_OBJECTS*12-1:0] compact_x0, compact_x1, compact_y0, compact_y1;
    reg compact_stale;
    always @(*) begin
        compact_count=0; compact_mask=0; compact_class=0;
        compact_x0=0; compact_x1=0; compact_y0=0; compact_y1=0; compact_stale=0;
        for (output_index=0; output_index<MAX_OBJECTS; output_index=output_index+1)
            if (valid[output_index] && stable_class[output_index]!=0) begin
                compact_class[compact_count*3 +: 3]=stable_class[output_index];
                compact_x0[compact_count*12 +: 12]=x_min[output_index];
                compact_x1[compact_count*12 +: 12]=x_max[output_index];
                compact_y0[compact_count*12 +: 12]=y_min[output_index];
                compact_y1[compact_count*12 +: 12]=y_max[output_index];
                compact_mask[stable_class[output_index]-1]=1'b1;
                compact_stale=compact_stale || (misses[output_index]!=0);
                compact_count=compact_count+1'b1;
            end
    end
endmodule
