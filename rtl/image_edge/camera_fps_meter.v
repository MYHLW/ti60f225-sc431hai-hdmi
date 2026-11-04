module camera_fps_meter #(
    parameter integer REF_CLK_HZ = 5000000
) (
    input  wire       frame_clk,
    input  wire       frame_rst_n,
    input  wire       frame_vs,
    input  wire       ref_clk,
    input  wire       ref_rst_n,
    input  wire       display_clk,
    input  wire       display_rst_n,
    output reg  [7:0] o_fps_bcd
);

    localparam integer SECOND_COUNT_WIDTH =
        (REF_CLK_HZ <= 2) ? 1 : $clog2(REF_CLK_HZ);

    reg frame_vs_d;
    reg frame_toggle;
    always @(posedge frame_clk or negedge frame_rst_n) begin
        if (!frame_rst_n) begin
            frame_vs_d <= 1'b0;
            frame_toggle <= 1'b0;
        end else begin
            frame_vs_d <= frame_vs;
            if (frame_vs && !frame_vs_d)
                frame_toggle <= ~frame_toggle;
        end
    end

    reg frame_toggle_meta;
    reg frame_toggle_sync;
    reg frame_toggle_sync_d;
    wire frame_event = frame_toggle_sync ^ frame_toggle_sync_d;
    reg [SECOND_COUNT_WIDTH-1:0] second_count;
    reg [3:0] frame_tens;
    reg [3:0] frame_ones;
    reg [7:0] fps_bcd_ref;
    reg fps_update_toggle;

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            frame_toggle_meta <= 1'b0;
            frame_toggle_sync <= 1'b0;
            frame_toggle_sync_d <= 1'b0;
            second_count <= {SECOND_COUNT_WIDTH{1'b0}};
            frame_tens <= 4'd0;
            frame_ones <= 4'd0;
            fps_bcd_ref <= 8'h00;
            fps_update_toggle <= 1'b0;
        end else begin
            frame_toggle_meta <= frame_toggle;
            frame_toggle_sync <= frame_toggle_meta;
            frame_toggle_sync_d <= frame_toggle_sync;

            if (second_count == REF_CLK_HZ - 1) begin
                second_count <= {SECOND_COUNT_WIDTH{1'b0}};
                if (frame_event && (frame_tens != 4'd9 || frame_ones != 4'd9)) begin
                    if (frame_ones == 4'd9)
                        fps_bcd_ref <= {frame_tens + 1'b1, 4'd0};
                    else
                        fps_bcd_ref <= {frame_tens, frame_ones + 1'b1};
                end else begin
                    fps_bcd_ref <= {frame_tens, frame_ones};
                end
                frame_tens <= 4'd0;
                frame_ones <= 4'd0;
                fps_update_toggle <= ~fps_update_toggle;
            end else begin
                second_count <= second_count + 1'b1;
                if (frame_event && (frame_tens != 4'd9 || frame_ones != 4'd9)) begin
                    if (frame_ones == 4'd9) begin
                        frame_tens <= frame_tens + 1'b1;
                        frame_ones <= 4'd0;
                    end else begin
                        frame_ones <= frame_ones + 1'b1;
                    end
                end
            end
        end
    end

    reg [7:0] fps_bcd_meta;
    reg [7:0] fps_bcd_sync;
    reg update_meta;
    reg update_sync;
    reg update_sync_d;
    reg update_pending;

    always @(posedge display_clk or negedge display_rst_n) begin
        if (!display_rst_n) begin
            fps_bcd_meta <= 8'h00;
            fps_bcd_sync <= 8'h00;
            update_meta <= 1'b0;
            update_sync <= 1'b0;
            update_sync_d <= 1'b0;
            update_pending <= 1'b0;
            o_fps_bcd <= 8'h00;
        end else begin
            fps_bcd_meta <= fps_bcd_ref;
            fps_bcd_sync <= fps_bcd_meta;
            update_meta <= fps_update_toggle;
            update_sync <= update_meta;
            update_sync_d <= update_sync;
            if (update_sync ^ update_sync_d)
                update_pending <= 1'b1;
            else if (update_pending) begin
                o_fps_bcd <= fps_bcd_sync;
                update_pending <= 1'b0;
            end
        end
    end

endmodule
