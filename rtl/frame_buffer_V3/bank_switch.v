

module bank_switch #(
		parameter FB_NUM = 2,
		parameter MAX_VID_WIDTH = 1920,
		parameter MAX_VID_HIGHT = 1080,
		parameter START_ADDR= 0,
		parameter VID_DATA_WIDTH= 16,
		parameter AXI_DATA_WIDTH = 256
		
)

(
input	wire		ddr_clk,//!时钟
input	wire		rst_n,//!复位，低电平有效

input	wire		wr_sw,//!写bank切换请求信号,电平有效
input	wire		rd_sw,//!读bank切换请求信号,电平有效
input   wire        save_req,
input   wire        toggle_saved_req,
input   wire        toggle_freeze_req,
input   wire        previous_saved_req,
input   wire        next_saved_req,
output  wire [1:0]  display_state,
output  wire        saved_valid,
output  wire [2:0]  saved_count,
output  wire [2:0]  saved_index,
output  wire        freeze_capture,

output	reg	[2:0]	wr_bank,
output	reg	[2:0]	rd_bank,
output	reg			rd_sw_ack,
output	reg			wr_sw_ack,
output	reg[31:0] 	rd_start_addr,
output	reg[31:0]	wr_start_addr




);                       
localparam AXI_BYTE_NUMBER = AXI_DATA_WIDTH/8  ;
localparam FRAME_LEN =   MAX_VID_WIDTH*MAX_VID_HIGHT*VID_DATA_WIDTH/8 + 32'h200;  

localparam FRAME_1ST_START_ADDR = START_ADDR;
localparam FRAME_2ND_START_ADDR = FRAME_LEN + START_ADDR ;

localparam FRAME_3RD_START_ADDR = FRAME_LEN+ FRAME_2ND_START_ADDR;
localparam FRAME_4TH_START_ADDR = FRAME_LEN+ FRAME_3RD_START_ADDR;
localparam FRAME_5TH_START_ADDR = FRAME_LEN+ FRAME_4TH_START_ADDR;
localparam FRAME_6TH_START_ADDR = FRAME_LEN+ FRAME_5TH_START_ADDR;
localparam FRAME_7TH_START_ADDR = FRAME_LEN+ FRAME_6TH_START_ADDR;
localparam FRAME_8TH_START_ADDR = FRAME_LEN+ FRAME_7TH_START_ADDR;


	
	generate 
	if (FB_NUM != 3) begin : no_snapshot
		assign display_state = 2'd0;
		assign saved_valid = 1'b0;
		assign saved_count = 3'd0;
		assign saved_index = 3'd0;
		assign freeze_capture = 1'b0;
	end
	if( FB_NUM == 1 ) begin : one_fb 
		always @( posedge ddr_clk or negedge rst_n ) 
		begin 
			if( !rst_n ) begin
				wr_bank <= 2'b00;
				rd_bank <= 2'b01;
				wr_sw_ack <= 1'b0;
				rd_sw_ack <= 1'b0;     
				rd_start_addr <= FRAME_1ST_START_ADDR; 
				wr_start_addr <= FRAME_1ST_START_ADDR; 
			end else begin 
				wr_bank <= 2'b00;
				rd_bank <= 2'b00;
				wr_sw_ack <= wr_sw;
				rd_sw_ack <= rd_sw;   
				rd_start_addr <= FRAME_1ST_START_ADDR;
				wr_start_addr <= FRAME_1ST_START_ADDR;
			end 
		end 

	end else if( FB_NUM == 2 ) begin :tow_fb
		reg			bank_sw_en = 1'b0;
		reg			bank_sw_en_d1 = 1'b0;
		wire		pos_bank_sw_en;
		always @( posedge ddr_clk )
		begin
			bank_sw_en <= wr_sw & rd_sw;
			bank_sw_en_d1 <= bank_sw_en;
		end
		assign pos_bank_sw_en = {bank_sw_en_d1,bank_sw_en} == 2'b01;
		
		always @( posedge ddr_clk or negedge rst_n)
		begin
			if( !rst_n ) begin
				wr_bank <= 2'b00;
				rd_bank <= 2'b01;      
				wr_start_addr <= FRAME_1ST_START_ADDR; 
				rd_start_addr <= FRAME_2ND_START_ADDR; 
			end else if( pos_bank_sw_en ) begin//必须两个bank同时切换
				wr_bank[0] <= ~wr_bank[0];
				rd_bank[0] <= wr_bank[0];
				rd_bank[1] <= 1'b0;
				wr_bank[1] <= 1'b0;      
				wr_start_addr <= wr_bank[0] ? FRAME_1ST_START_ADDR : FRAME_2ND_START_ADDR;
				rd_start_addr <= wr_bank[0] ? FRAME_2ND_START_ADDR : FRAME_1ST_START_ADDR; 
			end
		end
		
		always @( posedge ddr_clk )
		begin
			wr_sw_ack	 <= pos_bank_sw_en;
			rd_sw_ack	 <= pos_bank_sw_en;
		end
		
		
	end else if( FB_NUM == 3 ) begin :three_fb
		localparam [1:0] LIVE = 2'd0, FROZEN = 2'd1, SAVED = 2'd2;
		reg	[2:0] 	dirt_bank = 3'd2;
		reg			dirt_en = 1'b1;
		reg	[2:0]	clean_bank = 3'd0;
		reg			clean_en = 1'b0;
		reg [1:0] requested_state;
		reg [1:0] active_state;
		reg [2:0] snapshot_bank [0:4];
		reg [2:0] oldest_slot;
		reg [2:0] snapshot_count;
		reg [2:0] selected_order;
		reg [2:0] displayed_order;
		reg saved_valid_r;
		reg save_pending;
		reg [1:0] save_ready_count;
		integer slot;
		function [2:0] slot_add;
			input [2:0] first;
			input [2:0] offset;
			reg [3:0] sum;
			begin
				sum = {1'b0, first} + {1'b0, offset};
				slot_add = (sum >= 4'd5) ? sum - 4'd5 : sum;
			end
		endfunction
		wire [2:0] next_slot = slot_add(oldest_slot, snapshot_count);
		wire [2:0] selected_slot = slot_add(oldest_slot, selected_order);
		wire [2:0] spare_bank = (snapshot_count == 3'd5) ?
		                              snapshot_bank[oldest_slot] : 3'd3 + snapshot_count;
		assign display_state = active_state;
		assign saved_valid = saved_valid_r;
		assign saved_count = snapshot_count;
		assign saved_index = (active_state == SAVED) ? displayed_order + 3'd1 : 3'd0;
		assign freeze_capture = (requested_state == FROZEN);

		function [31:0] bank_addr;
			input [2:0] bank;
			begin
				case (bank)
					2'd0: bank_addr = FRAME_1ST_START_ADDR;
					2'd1: bank_addr = FRAME_2ND_START_ADDR;
					2'd2: bank_addr = FRAME_3RD_START_ADDR;
					2'd3: bank_addr = FRAME_4TH_START_ADDR;
					3'd4: bank_addr = FRAME_5TH_START_ADDR;
					3'd5: bank_addr = FRAME_6TH_START_ADDR;
					3'd6: bank_addr = FRAME_7TH_START_ADDR;
					default: bank_addr = FRAME_8TH_START_ADDR;
				endcase
			end
		endfunction
		wire		pos_wr_sw_en;
		wire		pos_rd_sw_en;
		reg			wr_sw_d1 = 1'b0;
		reg			rd_sw_d1 = 1'b0;
		always @( posedge ddr_clk )
		begin
				wr_sw_d1 <= wr_sw;
				rd_sw_d1 <= rd_sw;
		end
		assign pos_wr_sw_en = {wr_sw_d1,wr_sw} == 2'b01;
		assign pos_rd_sw_en = {rd_sw_d1,rd_sw} == 2'b01;
		
		always @( posedge ddr_clk )
		begin
			wr_sw_ack <= pos_wr_sw_en;
			rd_sw_ack <= pos_rd_sw_en;
		end
		always @( posedge ddr_clk or negedge rst_n)
		begin
			if( !rst_n ) begin
				wr_bank <= 3'd0;
				rd_bank <= 3'd1;
				dirt_bank <= 3'd2;
				dirt_en <= 1'b1;
				clean_en <= 1'b0;
				clean_bank <= 3'd0;
				requested_state <= LIVE;
				active_state <= LIVE;
				for (slot = 0; slot < 5; slot = slot + 1)
					snapshot_bank[slot] <= 3'd0;
				oldest_slot <= 3'd0;
				snapshot_count <= 3'd0;
				selected_order <= 3'd0;
				displayed_order <= 3'd0;
				saved_valid_r <= 1'b0;
				save_pending <= 1'b0;
				save_ready_count <= 2'd0;
				
				wr_start_addr <= FRAME_1ST_START_ADDR;
				rd_start_addr <= FRAME_2ND_START_ADDR; 
			end else begin
				if (toggle_saved_req && saved_valid_r && !save_pending &&
				    save_ready_count == 0 && !save_req) begin
					requested_state <= (requested_state == SAVED) ? LIVE : SAVED;
					if (requested_state != SAVED)
						selected_order <= snapshot_count - 3'd1;
				end else if (toggle_freeze_req && requested_state != SAVED)
					requested_state <= (requested_state == FROZEN) ? LIVE : FROZEN;
				if (previous_saved_req && !next_saved_req &&
				    requested_state == SAVED && active_state == SAVED && saved_valid_r)
					selected_order <= (selected_order == 3'd0) ?
					                  snapshot_count - 3'd1 : selected_order - 3'd1;
				else if (next_saved_req && !previous_saved_req &&
				         requested_state == SAVED && active_state == SAVED && saved_valid_r)
					selected_order <= (selected_order == snapshot_count - 3'd1) ?
					                  3'd0 : selected_order + 3'd1;
				if (save_req && requested_state == LIVE && active_state == LIVE &&
				    !save_pending && save_ready_count == 0)
					save_pending <= 1'b1;

				if (pos_wr_sw_en) begin
					if (save_pending) begin
						// Pin the completed writer bank; return a free or oldest
						// snapshot bank to the live three-bank rotation.
						snapshot_bank[next_slot] <= wr_bank;
						if (snapshot_count == 3'd5)
							oldest_slot <= slot_add(oldest_slot, 3'd1);
						else
							snapshot_count <= snapshot_count + 3'd1;
						selected_order <= (snapshot_count == 3'd5) ?
						                  3'd4 : snapshot_count;
						saved_valid_r <= 1'b0;
						save_ready_count <= 2'd2;
						save_pending <= 1'b0;
						if (dirt_en) begin
							wr_bank <= dirt_bank;
							wr_start_addr <= bank_addr(dirt_bank);
							dirt_bank <= spare_bank;
							dirt_en <= 1'b1;
						end else begin
							wr_bank <= spare_bank;
							wr_start_addr <= bank_addr(spare_bank);
						end
					end else if (dirt_en) begin
						wr_bank <= dirt_bank;
						wr_start_addr <= bank_addr(dirt_bank);
						clean_bank <= wr_bank;
						clean_en <= 1'b1;
						dirt_en <= 1'b0;
					end
				end else if (pos_rd_sw_en) begin
					active_state <= requested_state;
					if (save_ready_count != 0) begin
						save_ready_count <= save_ready_count - 1'b1;
						if (save_ready_count == 2'd1)
							saved_valid_r <= 1'b1;
					end
					if (requested_state == SAVED && saved_valid_r) begin
						rd_start_addr <= bank_addr(snapshot_bank[selected_slot]);
						displayed_order <= selected_order;
					end
					else if (requested_state == FROZEN)
						rd_start_addr <= bank_addr(rd_bank);
					else if (clean_en)
						rd_start_addr <= bank_addr(clean_bank);
					else
						rd_start_addr <= bank_addr(rd_bank);

					if (requested_state != FROZEN) begin
						if (clean_en) begin
							rd_bank <= clean_bank;
							dirt_bank <= rd_bank;
							dirt_en <= 1'b1;
						end
						clean_en <= 1'b0;
					end
				end
			end
		end
						
	end
	endgenerate


endmodule
