
/////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2013-2021 Efinix Inc. All rights reserved.
//
// Description:
// Example top file for ti60f225 dev kit OOB design
//
// Language:  Verilog 2001
//Ti60f225_sc431hai2hdmi_v6：
//使用了最新版本的framebuffer_v3;
// ------------------------------------------------------------------------------

/////////////////////////////////////////////////////////////////////////////////
//`define SOFT_TAP 1
`include "ddr3_controller/ddr3_parameter.vh"
`include "frame_buffer_V3/color_bar_rgb.v"
// `include "define.v"

module ti60f225_oob_top #(

	parameter                       RANK_RATIO         = 1,       // # of unique CS outputs per rank
	parameter                       ASYN_AXI_CLK       = `ASYN_AXI_CLK, 
	parameter                       RANKS              = `RANKS,
	parameter                       CK_WIDTH           = `CK_WIDTH,       // # of CK/CK# outputs to memory   
	parameter                       CKE_WIDTH          = `CKE_WIDTH,       // # of cke outputs
	parameter                       CS_WIDTH           = `CS_WIDTH,       // # of unique CS outputs
	parameter                       BANK_WIDTH         = `BANK_WIDTH,       // # of bank bits
	parameter                       ROW_WIDTH          = `ROW_WIDTH,       // DRAM address bus width
	parameter                       COL_WIDTH          = `COL_WIDTH,      // column address width
	parameter                       DM_WIDTH           = `DM_WIDTH,       // # of DM (data mask)
	parameter                       DQS_WIDTH          = `DQS_WIDTH,       // # of DQS (strobe)
	parameter                       DQ_WIDTH           = `DQ_WIDTH,      // # of DQ (data)
	parameter                       ODT_WIDTH          = `ODT_WIDTH,
	parameter                       DQ_CNT_WIDTH       = `DQ_CNT_WIDTH,       // = ceil(log2(DQ_WIDTH))
	parameter                       DQS_CNT_WIDTH      = `DQS_CNT_WIDTH,       // = ceil(log2(DQS_WIDTH))  
	parameter                       DRAM_WIDTH         = `DRAM_WIDTH,       // # of DQ per DQS   
	parameter                       DATA_WIDTH         = `DATA_WIDTH,
	parameter                       ADDR_WIDTH         = `ADDR_WIDTH,    
	parameter                       AXI_ID_WIDTH       = `AXI_ID_WIDTH,
	parameter                       AXI_ADDR_WIDTH     = `AXI_ADDR_WIDTH,
	parameter                       AXI_DATA_WIDTH     = `AXI_DATA_WIDTH,
	parameter                       HDMI_TEST_PATTERN  = 1'b0,
	parameter [3:0]                 IMAGE_MODE         = 4'd0,
	parameter [10:0]                SOBEL_THRESHOLD    = 11'd192
)
(

  (* syn_peri_port = 0 *) input jtag_inst1_CAPTURE,
  (* syn_peri_port = 0 *) input jtag_inst1_DRCK,
  (* syn_peri_port = 0 *) input jtag_inst1_RESET,
  (* syn_peri_port = 0 *) input jtag_inst1_RUNTEST,
  (* syn_peri_port = 0 *) input jtag_inst1_SEL,
  (* syn_peri_port = 0 *) input jtag_inst1_SHIFT,
  (* syn_peri_port = 0 *) input jtag_inst1_TCK,
  (* syn_peri_port = 0 *) input jtag_inst1_TDI,
  (* syn_peri_port = 0 *) input jtag_inst1_TMS,
  (* syn_peri_port = 0 *) input jtag_inst1_UPDATE,
  (* syn_peri_port = 0 *) output jtag_inst1_TDO,

   //Clocks 
	input	wire	i_arstn,
    input wire i_key1_n,
    input wire i_key2_n,
    input wire i_key3_n,
    input	wire	i_mipi_rx_pclk,
    input wire  vid_clk_dvi2,
    input wire hdmi_tx_slow_clk,
    input wire CLK_5M,
    input  wire CLK_25M,
	output  wire    pll_inst1_RSTN,
	input	wire	i_pll_locked,
	input 	wire  	pll_locked,
	output  wire    pll_inst4_RSTN,
	input   wire    pll_inst4_LOCKED,
	output  wire  	USER_PLL_RSTN,
    output 	wire 	DDR3_PLL_RSTN,
	input 	wire  	user_pll_locked,
    //CSI Interface
    input	 wire		io_cam_sda_IN,
    output wire   io_cam_sda_OUT,
    output wire		io_cam_sda_OE,

    output io_cam_scl_OUT,
    input io_cam_scl_IN,
    output io_cam_scl_OE,

    output	wire		o_cam_rst_p,
    
    input	wire		i_cam_ck_LP_P_IN,
    input	wire		i_cam_ck_LP_N_IN,
    output	wire		o_cam_ck_HS_TERM,
    output	wire		o_cam_ck_HS_ENA,
    input	wire		i_cam_ck_CLKOUT,
    
    input	wire	[7:0]			cam_d0_HS_IN,
    input	  wire		      cam_d0_LP_P_IN,
    input	  wire		      cam_d0_LP_N_IN,
    output	wire		      cam_d0_HS_TERM,
    output	wire		      cam_d0_HS_ENA,
    output	wire		      cam_d0_RST,
    output	wire		      cam_d0_FIFO_RD,
    input	  wire		      cam_d0_FIFO_EMPTY,
    
    input 	wire	[7:0]			cam_d1_HS_IN,
    input	  wire		        cam_d1_LP_P_IN,
    input	  wire		        cam_d1_LP_N_IN,
    output	wire		        cam_d1_HS_TERM,
    output	wire		        cam_d1_HS_ENA,
    output	wire		        cam_d1_RST,
    output	wire		        cam_d1_FIFO_RD,
    input	  wire		        cam_d1_FIFO_EMPTY,
    
    input 	wire	[7:0]			cam_d2_HS_IN,
    input	  wire		        cam_d2_LP_P_IN,
    input	  wire		        cam_d2_LP_N_IN,
    output	wire		        cam_d2_HS_TERM,
    output	wire		        cam_d2_HS_ENA,
    output	wire		        cam_d2_RST,
    output	wire		        cam_d2_FIFO_RD,
    input	  wire		        cam_d2_FIFO_EMPTY,  
   
    input 	wire	[7:0]			cam_d3_HS_IN,
    input	  wire		        cam_d3_LP_P_IN,
    input	  wire		        cam_d3_LP_N_IN,
    output	wire		        cam_d3_HS_TERM,
    output	wire		        cam_d3_HS_ENA,
    output	wire		        cam_d3_RST,
    output	wire		        cam_d3_FIFO_RD,
    input	  wire		        cam_d3_FIFO_EMPTY,

	
	input 					tx_cal_clk_90edge,
  	input 					rx_cal_clk,
  	input 					tx_cal_clk,
	input                              core_clk,     // CORE CLK @ 100MHz
	input                              sdram_clk,    // SDRAM CK @ 400MHz
	// PLL status flags  
	output [2:0]                       pll_shift,  
	output [4:0]                       pll_shift_sel,
	output                             pll_shift_ena,  
	// memory interface ports
	output                             ddr_ck_hi,
	output                             ddr_ck_lo,
	output                             ddr_reset_n,
	output [CKE_WIDTH-1:0]             ddr_cke,     
	output [ROW_WIDTH-1:0]             ddr_addr,
	output [BANK_WIDTH-1:0]            ddr_ba,
	output                             ddr_cas_n,
 
	output [CS_WIDTH*RANK_RATIO-1:0]   ddr_cs_n,
	output                             ddr_ras_n,
	output                             ddr_we_n,
	
	input  [DQS_WIDTH-1:0]             ddr_dqs_in_hi,
	input  [DQS_WIDTH-1:0]             ddr_dqs_in_lo,
	input  [DQ_WIDTH-1:0]              ddr_dq_in_hi,
	input  [DQ_WIDTH-1:0]              ddr_dq_in_lo,
	
	output [DQS_WIDTH-1:0]             ddr_dqs_oe,
	output [DQS_WIDTH-1:0]             ddr_dqs_oe_n,
	output [DQ_WIDTH-1:0]              ddr_dq_oe,  
	output [DQS_WIDTH-1:0]             ddr_dqs_out_hi,
	output [DQS_WIDTH-1:0]             ddr_dqs_out_lo,
	output [DQ_WIDTH-1:0]              ddr_dq_out_hi,
	output [DQ_WIDTH-1:0]              ddr_dq_out_lo,
	output [DM_WIDTH-1:0]              ddr_dm_hi,
	output [DM_WIDTH-1:0]              ddr_dm_lo,
	output [ODT_WIDTH-1:0]             ddr_odt,

       //LED
       output [3:0] led,

       // UART touch screen (115200, 8N1)
       input  wire uart_rx,
       output wire uart_tx,

       // MIPI DSI
       input	wire	                     i_mipi_tx_pclk		,
       output	wire	                     mipi_dp_clk_LP_P_OUT		,
       output	wire	                     mipi_dp_clk_LP_N_OUT		,
       output	wire	[7:0] 	              mipi_dp_clk_HS_OUT		,
       output	wire	                     mipi_dp_clk_HS_OE		,
       output	wire	                     mipi_dp_data3_LP_P_OUT	,
       output	wire	                     mipi_dp_data2_LP_P_OUT	,
       output	wire	                     mipi_dp_data1_LP_P_OUT	,
       output	wire	                     mipi_dp_data0_LP_P_OUT	,
       output	wire	                     mipi_dp_data3_LP_N_OUT	,
       output	wire	                     mipi_dp_data2_LP_N_OUT	,
       output	wire	                     mipi_dp_data1_LP_N_OUT	,
       output	wire	                     mipi_dp_data0_LP_N_OUT	,
       output	wire	[7:0] 	              mipi_dp_data0_HS_OUT	       ,
       output	wire	[7:0] 	              mipi_dp_data1_HS_OUT	       ,
       output	wire	[7:0] 	              mipi_dp_data2_HS_OUT	       ,
       output	wire	[7:0] 	              mipi_dp_data3_HS_OUT	       ,
       output	wire	                     mipi_dp_data3_HS_OE		,
       output	wire	                     mipi_dp_data2_HS_OE		,
       output	wire	                     mipi_dp_data1_HS_OE		,
       output	wire	                     mipi_dp_data0_HS_OE		,

       output	wire	                     mipi_dp_clk_RST		,
       output	wire	                     mipi_dp_data0_RST		,
       output	wire	                     mipi_dp_data1_RST		,
       output	wire	                     mipi_dp_data2_RST		,
       output	wire	                     mipi_dp_data3_RST		,
       output	wire	                     mipi_dp_clk_LP_P_OE		,
       output	wire	                     mipi_dp_clk_LP_N_OE		,
       output	wire	                     mipi_dp_data3_LP_P_OE	,
       output	wire	                     mipi_dp_data3_LP_N_OE	,
       output	wire	                     mipi_dp_data2_LP_P_OE	,
       output	wire	                     mipi_dp_data2_LP_N_OE	,
       output	wire	                     mipi_dp_data1_LP_P_OE	,
       output	wire	                     mipi_dp_data1_LP_N_OE	,
       output	wire	                     mipi_dp_data0_LP_P_OE	,
       output	wire	                     mipi_dp_data0_LP_N_OE	,

       input  wire	                     mipi_dp_data0_LP_P_IN	,
       input  wire	                     mipi_dp_data0_LP_N_IN	,
       output	wire	                     LCD_RST_P			,
       output wire                        LCD_POWER			,

       // hdmi interface

    output tmds_tx_clk_TX_OE,
    output [9:0] tmds_tx_clk_TX_DATA,
    output tmds_tx_clk_TX_RST,
    output tmds_tx_data0_TX_OE,
    output [9:0] tmds_tx_data0_TX_DATA,
    output tmds_tx_data0_TX_RST,
    output tmds_tx_data1_TX_OE,
    output [9:0] tmds_tx_data1_TX_DATA,
    output tmds_tx_data1_TX_RST,
    output tmds_tx_data2_TX_OE,
    output [9:0] tmds_tx_data2_TX_DATA,
    output tmds_tx_data2_TX_RST


);

function integer log2;
	input	integer	val;
	integer	i;
	begin
		log2 = 0;
		for (i=0; 2**i<val; i=i+1)
			log2 = i+1;
	end
endfunction


//===============================================================================
//localparam
//===============================================================================
localparam WR_FIFO_DEPTH  = 1024;
localparam RD_FIFO_DEPTH  = 1024;

// localparam	MAX_HRES		= 12'd1920;
// localparam	MAX_VRES		= 12'd1080;
// localparam	HSP			= 8'd2;
// localparam	HBP			= 8'd88;
// localparam	HFP			= 8'd120;
// localparam	VSP			= 8'd2;
// localparam	VBP			= 8'd20;
// localparam	VFP			= 8'd20;

localparam MAX_HRES = 1920;
localparam HFP      = 88;
localparam HSP      = 44;
localparam HBP      = 148;

localparam MAX_VRES = 1080;
localparam VFP      = 4;
localparam VSP      = 5;
localparam VBP      = 36;
//===============================================================================
//signal
//===============================================================================
   
wire                              app_sr_active;
wire                              app_ref_ack;
wire                              app_zq_ack;
wire                              cal_done;

// Slave Interface Write Address Ports
wire [AXI_ID_WIDTH-1:0]           s_axi_awid;
wire [AXI_ADDR_WIDTH-1:0]         s_axi_awaddr;
wire [7:0]                        s_axi_awlen;
wire [2:0]                        s_axi_awsize;
wire [1:0]                        s_axi_awburst;
wire [0:0]                        s_axi_awlock;
wire [3:0]                        s_axi_awcache;
wire [2:0]                        s_axi_awprot;
wire                              s_axi_awvalid;
wire                              s_axi_awready;
// Slave Interface Write Data Ports
wire [AXI_DATA_WIDTH-1:0]         s_axi_wdata;
wire [(AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb;
wire                              s_axi_wlast;
wire                              s_axi_wvalid;
wire                              s_axi_wready;
// Slave Interface Write Response Ports
wire                              s_axi_bready;
wire [AXI_ID_WIDTH-1:0]           s_axi_bid;
wire [1:0]                        s_axi_bresp;
wire                              s_axi_bvalid;
// Slave Interface Read Address Ports
wire [AXI_ID_WIDTH-1:0]           s_axi_arid;
wire [AXI_ADDR_WIDTH-1:0]         s_axi_araddr;
wire [7:0]                        s_axi_arlen;
wire [2:0]                        s_axi_arsize;
wire [1:0]                        s_axi_arburst;
wire [0:0]                        s_axi_arlock;
wire [3:0]                        s_axi_arcache;
wire [2:0]                        s_axi_arprot;
wire                              s_axi_arvalid;
wire                              s_axi_arready;
// Slave Interface Read Data Ports
wire                              s_axi_rready;
wire [AXI_ID_WIDTH-1:0]           s_axi_rid;
wire [AXI_DATA_WIDTH-1:0]         s_axi_rdata;
wire [1:0]                        s_axi_rresp;
wire                              s_axi_rlast;
wire                              s_axi_rvalid;




////////////////////////////////////////////////////////////////
// System & Debugger
wire    w_arstn;
// wire	w_sysclk_mcu_arstn;
// wire	w_sysclk_mcu_arst;
wire	w_mipi_rx_pclk_arstn;
wire	w_mipi_rx_pclk_arst;

wire		       w_mipi_rx_vs;
wire		       w_mipi_rx_hs;
wire	       w_mipi_rx_de;
wire	[63:0]			w_mipi_rx_data	;

wire					io_systemReset;



//===================================================================================================
//reset module
//===================================================================================================

assign w_arstn  		       = i_pll_locked & pll_locked & user_pll_locked;
assign pll_inst1_RSTN  		= i_arstn;
assign USER_PLL_RSTN      		= i_arstn;
assign mipi_dsi_tx_pll_RSTN 	= i_arstn;
assign DDR3_PLL_RSTN 		= i_arstn;
reset_ctrl
#(
	.NUM_RST		(2),
	.CYCLE			(1),
	.IN_RST_ACTIVE	(4'b00),
	.OUT_RST_ACTIVE	(4'b10)
)
inst_reset_ctrl
(
	.i_arst		({2{w_arstn}}),//({{4{i_pll_locked}},                  {2{i_arstn}}}),
	.i_clk			({2{i_mipi_rx_pclk}}),
	.o_srst		({w_mipi_rx_pclk_arst, w_mipi_rx_pclk_arstn})
);



reg [25:0] cnt = 'd0;
always @( posedge core_clk)
begin 
       cnt <= cnt + 1'b1;
end
assign led[0]  = cal_done ? cnt[24] : 1'b0;

//========================================================================================================
// UART touch screen command interface
//========================================================================================================
wire [7:0] uart_rx_data;
wire       uart_rx_valid;
wire [7:0] uart_ctrl;
wire       uart_enable9;
wire       uart_enable10;
wire       uart_enable11;
wire       uart_enable12;
reg  [2:0] uart_mode_core;
reg        uart_mode_req_toggle;
wire [2:0] uart_left_core, uart_right_core;
wire uart_compare_req_toggle;

always @(posedge core_clk or negedge w_arstn) begin
  if (!w_arstn) begin
    uart_mode_core <= 3'd0;
    uart_mode_req_toggle <= 1'b0;
  end else if (uart_rx_valid && ((uart_rx_data >= 8'h70 && uart_rx_data <= 8'h75) || uart_rx_data==8'h78)) begin
    uart_mode_core <= uart_rx_data==8'h78 ? 3'd7:uart_rx_data[2:0];
    uart_mode_req_toggle <= ~uart_mode_req_toggle;
  end
end

// OSD visibility: core command (independent of enable1-enable12).
reg osd_enable_core;
reg [15:0] osd_cmd_guard;
always @(posedge core_clk or negedge w_arstn) begin
  if (!w_arstn) begin
    osd_enable_core <= 1'b1;
    osd_cmd_guard <= 16'd0;
  end else begin
    if (osd_cmd_guard != 0) osd_cmd_guard <= osd_cmd_guard - 1'b1;
    if (uart_rx_valid && uart_rx_data == 8'h65 && osd_cmd_guard == 0) begin
      osd_enable_core <= ~osd_enable_core;
      osd_cmd_guard <= 16'd50000;
    end
  end
end
// OSD visibility: end core command.

FPGA_UART_Test #(
       .CLK_FREQ_HZ (100_000_000),
       .BAUD_RATE   (115_200)
) inst_uart_touch_screen (
       .clk         (core_clk),
       .rst_n       (w_arstn),
       .fpga_rxd    (uart_rx),
       .fpga_txd    (uart_tx),
       .rxd_data    (uart_rx_data),
       .rxd_valid   (uart_rx_valid),
       .ctrl_out    (uart_ctrl),
       .enable9     (uart_enable9),
       .enable10    (uart_enable10),
       .enable11    (uart_enable11),
       .enable12    (uart_enable12),
       .compare_left(uart_left_core), .compare_right(uart_right_core),
       .compare_req_toggle(uart_compare_req_toggle)
);

//========================================================================================================
//MIPI RX
//========================================================================================================
wire i_mipi_clk ;
assign i_mipi_clk = core_clk;

		assign	cam_d0_RST		= 1'b0;
		assign	cam_d1_RST		= 1'b0;
		assign  cam_d2_RST = 1'b0;
    assign  cam_d3_RST = 1'b0;
	
wire [15:0] mipi_debug_out;
		

		csi_rx_controller inst_efx_csi2_rx
		(
              .reset_n			(i_arstn),
              .clk				(i_mipi_clk),
              .reset_byte_HS_n	(i_arstn),
              .clk_byte_HS		  (i_cam_ck_CLKOUT),
              .reset_pixel_n		(w_mipi_rx_pclk_arstn),
              .clk_pixel			  (i_mipi_rx_pclk),
              
              .Rx_LP_CLK_P		  (i_cam_ck_LP_P_IN),
              .Rx_LP_CLK_N		  (i_cam_ck_LP_N_IN),
              .Rx_HS_enable_C		(o_cam_ck_HS_ENA),
              .LVDS_termen_C		(o_cam_ck_HS_TERM),
              
              .Rx_LP_D_P			({cam_d3_LP_P_IN, cam_d2_LP_P_IN, cam_d1_LP_P_IN, cam_d0_LP_P_IN}),//(r_mipi_rx_data_LP_P_IN_2P),
              .Rx_LP_D_N			({cam_d3_LP_N_IN, cam_d2_LP_N_IN, cam_d1_LP_N_IN, cam_d0_LP_N_IN}),//(r_mipi_rx_data_LP_N_IN_2P),
              .Rx_HS_D_0			(cam_d0_HS_IN),//(r_mipi_rx_data_HS_IN_2P[0*8+:8]),
              .Rx_HS_D_1			(cam_d1_HS_IN),//(r_mipi_rx_data_HS_IN_2P[1*8+:8]),
              .Rx_HS_D_2			(cam_d2_HS_IN),
              .Rx_HS_D_3			(cam_d3_HS_IN),
              .Rx_HS_D_4			(),
              .Rx_HS_D_5			(),
              .Rx_HS_D_6			(),
              .Rx_HS_D_7			(),
              .Rx_HS_enable_D		({cam_d3_HS_ENA    ,cam_d2_HS_ENA    ,cam_d1_HS_ENA    ,cam_d0_HS_ENA    }),//( w_cam_d_HS_ENA),
              .LVDS_termen_D		({cam_d3_HS_TERM   ,cam_d2_HS_TERM   ,cam_d1_HS_TERM   ,cam_d0_HS_TERM   }),
              .fifo_rd_enable		({cam_d3_FIFO_RD   ,cam_d2_FIFO_RD   ,cam_d1_FIFO_RD   ,cam_d0_FIFO_RD   }),
              .fifo_rd_empty		({cam_d3_FIFO_EMPTY,cam_d2_FIFO_EMPTY,cam_d1_FIFO_EMPTY,cam_d0_FIFO_EMPTY}),
              .DLY_enable_D		       (),
              .DLY_inc_D			(),
              .u_dly_enable_D		(),
              .u_dly_inc_D		       (),
              
              .axi_clk			(1'b0),
              .axi_reset_n		       (1'b0),
              .axi_awaddr			(6'b0),
              .axi_awvalid		       (1'b0),
              .axi_awready		       (),
              .axi_wdata			(32'b0),
              .axi_wvalid			(1'b0),
              .axi_wready			(),
              
              .axi_bvalid			(),
              .axi_bready			(1'b0),
              .axi_araddr			(6'b0),
              .axi_arvalid		       (1'b0),
              .axi_arready		       (),
              .axi_rdata			(),
              .axi_rvalid			(),
              .axi_rready			(1'b1),
              
              .hsync_vc0			(w_mipi_rx_hs),
              .hsync_vc1			(),
              .hsync_vc2			(),
              .hsync_vc3			(),
              .vsync_vc0			(w_mipi_rx_vs),
              .vsync_vc1			(),
              .vsync_vc2			(),
              .vsync_vc3			(),
              .vc				(),
              .word_count			(),
              .shortpkt_data_field        (),
              .datatype			(),
              .pixel_per_clk		(),
              .pixel_data			(w_mipi_rx_data),
              .pixel_data_valid	       (w_mipi_rx_de),
              .irq				(),
              .mipi_debug_out(mipi_debug_out)
		);

//     wire		       w1_mipi_rx_vs;
// wire		       w1_mipi_rx_hs;
// wire	       w1_mipi_rx_de;
// wire	[39:0]			w1_mipi_rx_data	;
// sensor_clipper  sensor_clipper_inst (
//     .clk(i_mipi_rx_pclk),
//     .i_vs(w_mipi_rx_vs),
//     .i_hs(w_mipi_rx_hs),
//     .i_de(w_mipi_rx_de),
//     .i_dat(w_mipi_rx_data[39:0]),

//     .o_hs(w1_mipi_rx_hs),
//     .o_vs(w1_mipi_rx_vs),
//     .o_de(w1_mipi_rx_de),
//     .o_dat(w1_mipi_rx_data)
   
//   );


wire mdebug_pixel_fifo_full     = mipi_debug_out[0] ;
wire mdebug_pixel_fifo_empty    = mipi_debug_out[1] ;
wire mdebug_crc_error           = mipi_debug_out[2] ;
wire mdebug_ecc_1bit_error      = mipi_debug_out[3] ;
wire mdebug_ecc_2bit_error      = mipi_debug_out[4] ;
wire mdebug_undersize_pkt_error = mipi_debug_out[5] ;
wire mdebug_line_vc0_error      = mipi_debug_out[6] ;
wire mdebug_frame_vc0_error    = mipi_debug_out[10];   
wire mdebug_receive_error      = mipi_debug_out[14];


//========================================================================================================
//
//========================================================================================================
		

//*************** imx219 config********************/
// mipi_config_imx219_top u_config_imx219(
// 										.i_sys_clk(CLK_5M)    	,    /////48M 
// 										.sys_rstn(vid_rst_n )    ,
// 										.o_sen_rst_n(o_cam_rstn)  	,
										
										// .o_iic_sda_OE(io_cam_sda_OE) ,
										// .i_iic_sda(io_cam_sda_IN)   	,
										// .o_iic_sda(io_cam_sda_OUT)   	,
										// .o_iic_scl(io_cam_scl)    	
										// ); 	

wire scl_padoen_o;
wire sda_padoen_o;


reg [15:0] i2c_rst_cnt = '0;

always @( posedge CLK_5M or negedge w_arstn )
begin
    if( !w_arstn )
       i2c_rst_cnt <= 'd0;
    else 
       i2c_rst_cnt <= i2c_rst_cnt[15] ? i2c_rst_cnt : i2c_rst_cnt + 1'b1;
end
// SC431HAI requires at least 4 ms from XSHUTDN release to initial I2C setup.
// 32768 cycles at 5 MHz provide about 6.55 ms of margin.
wire i2c_rst_n = i2c_rst_cnt[15];

wire cam_i2c_config_done;
wire cam_i2c_nack_seen;

i2c_master_ctrl_top u2_i2c_master_ctrl_top(
  /*i*/.clk			(CLK_5M		),
  /*i*/.rst_n			(i2c_rst_n		),
  /*i*/.scl_pad_i     (io_cam_scl_IN),//(1'b1),
  /*o*/.scl_pad_o     (io_cam_scl_OUT),
  /*o*/.scl_padoen_o  (scl_padoen_o),
  /*i*/.sda_pad_i     (io_cam_sda_IN),
  /*o*/.sda_pad_o     (io_cam_sda_OUT),
  /*o*/.sda_padoen_o  (sda_padoen_o),
  /*o*/.config_done   (cam_i2c_config_done),
  /*o*/.i2c_nack_seen (cam_i2c_nack_seen)
  
  );
assign o_cam_rst_p = ~w_arstn;
assign io_cam_scl_OE = ~scl_padoen_o;
assign io_cam_sda_OE = ~sda_padoen_o;

reg mipi_vs_d = 1'b0;
reg mipi_frame_seen = 1'b0;

always @( posedge i_mipi_rx_pclk or negedge w_arstn )
begin
  if( !w_arstn ) begin
    mipi_vs_d <= 1'b0;
    mipi_frame_seen <= 1'b0;
  end else begin
    mipi_vs_d <= w_mipi_rx_vs;
    if( w_mipi_rx_vs & ~mipi_vs_d )
      mipi_frame_seen <= 1'b1;
  end
end

assign led[1] = cam_i2c_config_done;
// UART verification: 0x01/0x81 toggles the existing frame-status LED state.
assign led[2] = mipi_frame_seen ^ uart_ctrl[0];

//=====================================================================================
//frame buffer
//=====================================================================================
wire [7:0] 	ch0_r;
wire [7:0]    ch0_g;
wire [7:0]    ch0_b;
wire ch0_vs;
wire ch0_hs;
wire ch0_de;
wire [1:0] framebuffer_state;
wire framebuffer_saved_valid;
wire [2:0] framebuffer_saved_count;
wire [2:0] framebuffer_saved_index;
reg [2:0] frame_key_meta;
reg [2:0] frame_key_sync;
reg [2:0] frame_key_stable;
reg [2:0] frame_key_press;
reg [19:0] frame_key_count [0:2];
integer frame_key_index;
reg [7:0] uart_ctrl_prev;
reg uart_enable9_prev;
wire uart_save_press = uart_ctrl[6] && !uart_ctrl_prev[6];
wire uart_saved_press = uart_ctrl[3] && !uart_ctrl_prev[3];
wire uart_previous_press = uart_ctrl[4] && !uart_ctrl_prev[4];
wire uart_next_press = uart_ctrl[5] && !uart_ctrl_prev[5];
wire uart_freeze_press = uart_enable9 ^ uart_enable9_prev;

always @(posedge core_clk or negedge vid_rst_n) begin
  if (!vid_rst_n) begin
    uart_ctrl_prev <= 8'd0;
    uart_enable9_prev <= 1'b0;
  end else begin
    uart_ctrl_prev <= uart_ctrl;
    uart_enable9_prev <= uart_enable9;
  end
end

// KEY1: save, KEY2: live/saved, KEY3: freeze. KEY0 remains the board reset.
always @(posedge core_clk or negedge vid_rst_n) begin
  if (!vid_rst_n) begin
    frame_key_meta <= 3'b111;
    frame_key_sync <= 3'b111;
    frame_key_stable <= 3'b111;
    frame_key_press <= 3'b000;
    for (frame_key_index = 0; frame_key_index < 3; frame_key_index = frame_key_index + 1)
      frame_key_count[frame_key_index] <= 20'd0;
  end else begin
    frame_key_meta <= {i_key3_n, i_key2_n, i_key1_n};
    frame_key_sync <= frame_key_meta;
    frame_key_press <= 3'b000;
    for (frame_key_index = 0; frame_key_index < 3; frame_key_index = frame_key_index + 1) begin
      if (frame_key_sync[frame_key_index] == frame_key_stable[frame_key_index])
        frame_key_count[frame_key_index] <= 20'd0;
      else if (frame_key_count[frame_key_index] == 20'd999999) begin
        frame_key_stable[frame_key_index] <= frame_key_sync[frame_key_index];
        frame_key_count[frame_key_index] <= 20'd0;
        if (!frame_key_sync[frame_key_index])
          frame_key_press[frame_key_index] <= 1'b1;
      end else
        frame_key_count[frame_key_index] <= frame_key_count[frame_key_index] + 1'b1;
    end
  end
end
// IMX219
  frame_buffer #(
.I_VID_WIDTH         (32),
.O_VID_WIDTH         (16),
.START_ADDR          (32'h00000        ),
.AXI_DATA_WIDTH      ( AXI_DATA_WIDTH	),
.AXI_ADDR_WIDTH      ( AXI_ADDR_WIDTH	),
.WR_FIFO_DEPTH	      ( 1024		),    
.RD_FIFO_DEPTH 	      ( 1024 	),
.BURST_LEN  	       (127),
.FB_NUM	            (3),
.MAX_VID_WIDTH	    (MAX_HRES/2) ,
.MAX_VID_HIGHT	    (MAX_VRES)


)checker0(
       .axi_clk		(core_clk 	        ),
       .rst_n			(vid_rst_n   ),
       .save_req        (frame_key_press[0] | uart_save_press),
       .toggle_saved_req(frame_key_press[1] | uart_saved_press),
       .toggle_freeze_req(frame_key_press[2] | uart_freeze_press),
       .previous_saved_req(uart_previous_press),
       .next_saved_req(uart_next_press),
       .display_state   (framebuffer_state),
       .saved_valid     (framebuffer_saved_valid),
       .saved_count     (framebuffer_saved_count),
       .saved_index     (framebuffer_saved_index),

/*i*/.i_clk			(i_mipi_rx_pclk      ),
/*i*/.i_vs			(w_mipi_rx_vs	),
/*i*/.i_de			(w_mipi_rx_de & w_mipi_rx_hs	),
/*i*/.vin 			({w_mipi_rx_data[39:32],w_mipi_rx_data[29:22],w_mipi_rx_data[19:12],w_mipi_rx_data[9:2]}	),
                     
/*i*/.o_clk			(vid_clk_dvi2),//(i_mipi_rx_pclk	),
/*i*/.o_hs    		(ch0_hs		),			
/*i*/.o_vs    		(ch0_vs		),			
/*i*/.o_de    		(ch0_de		),			
/*i*/.vout    		({ch0_g,ch0_b}	),//ch0_r,

/*i*/.H_FRONT_PORCH (HFP/2  		),//
/*i*/.H_SYNC 	 	    (HSP/2	 	),///2
/*i*/.H_VALID 	 	  (MAX_HRES/2     ),//		
/*i*/.H_BACK_PORCH	(HBP/2		),//		
/*i*/.V_FRONT_PORCH (VFP  		),//		
/*i*/.V_SYNC 	 	    (VSP 	 	),//		
/*i*/.V_VALID 	 	  (MAX_VRES     ),//		
/*i*/.V_BACK_PORCH	(VBP		),//		

       .awid			(s_axi_awid	),      
       .awaddr		(s_axi_awaddr	),
       .awlen			(s_axi_awlen	),
       .awsize		(s_axi_awsize	),
       .awburst		(s_axi_awburst),
       .awprot    (s_axi_awprot ),
       .awcache   (s_axi_awcache),
       .awlock		(s_axi_awlock	),
       .awvalid		(s_axi_awvalid),
       .awready		(s_axi_awready),

       .arid			(s_axi_arid	  ),
       .araddr		(s_axi_araddr	),
       .arlen			(s_axi_arlen	),
       .arsize		(s_axi_arsize	),
       .arburst 	(s_axi_arburst),

       .arprot    (s_axi_arprot ),
       .arcache   (s_axi_arcache),
       .arlock 		(s_axi_arlock	),
       .arvalid		(s_axi_arvalid),
       .arready		(s_axi_arready),

       .wdata			(s_axi_wdata	),
       .wstrb			(s_axi_wstrb	),
       .wlast			(s_axi_wlast	),
       .wvalid		(s_axi_wvalid	),
       .wready		(s_axi_wready	),


       .rid			  (s_axi_rid	),
       .rdata			(s_axi_rdata	),
       .rlast			(s_axi_rlast	),
       .rvalid 		(s_axi_rvalid	),
       .rready		(s_axi_rready	),
       .rresp			(s_axi_rresp	),

       .bid			  (s_axi_bid	),
       .bvalid		(s_axi_bvalid	),
       .bready	  (s_axi_bready	)
);


ddr3_top                 u_ddr3_top
(

.axi_clk                (core_clk            ),
.core_clk               (core_clk            ),
.sdram_clk              (sdram_clk           ),  
.rx_cal_clk             (rx_cal_clk          ),
.tx_cal_clk             (tx_cal_clk          ),
.tx_cal_clk_90edge      (tx_cal_clk_90edge   ),
.rstn                   (w_arstn             ),      
.pll_shift              (pll_shift           ),
.pll_shift_sel          (pll_shift_sel       ),
.pll_shift_ena          (pll_shift_ena       ),       
///////////////DDR BUS
.ddr_ck_hi              (ddr_ck_hi           ),
.ddr_ck_lo              (ddr_ck_lo           ),
.ddr_cke                (ddr_cke             ),    
.ddr_reset_n            (ddr_reset_n         ),
.ddr_cs_n               (ddr_cs_n            ),
.ddr_ras_n              (ddr_ras_n           ),
.ddr_cas_n              (ddr_cas_n           ),
.ddr_we_n               (ddr_we_n            ),     
.ddr_addr               (ddr_addr            ),
.ddr_ba                 (ddr_ba              ),

.ddr_dqs_oe             (ddr_dqs_oe          ),
.ddr_dqs_oe_n           (ddr_dqs_oe_n        ),
.ddr_dq_oe              (ddr_dq_oe           ),
.ddr_dqs_in_hi          (ddr_dqs_in_hi       ),
.ddr_dqs_in_lo          (ddr_dqs_in_lo       ),
.ddr_dq_in_hi           (ddr_dq_in_hi        ),
.ddr_dq_in_lo           (ddr_dq_in_lo        ),

.ddr_dqs_out_hi         (ddr_dqs_out_hi      ),
.ddr_dqs_out_lo         (ddr_dqs_out_lo      ),
.ddr_dq_out_hi          (ddr_dq_out_hi       ),
.ddr_dq_out_lo          (ddr_dq_out_lo       ),

.ddr_dm_hi              (ddr_dm_hi           ),
.ddr_dm_lo              (ddr_dm_lo           ),
.ddr_odt                (ddr_odt             ),

// Application interface ports
.app_sr_req                     (1'b0),
.app_ref_req                    (1'b0),
.app_zq_req                     (1'b0),
.app_sr_active                  (app_sr_active),
.app_ref_ack                    (app_ref_ack),
.app_zq_ack                     (app_zq_ack),

// Slave Interface Write Address Ports
.s_axi_awid                     (s_axi_awid        ),
.s_axi_awaddr                   (s_axi_awaddr      ),
.s_axi_awlen                    (s_axi_awlen       ),
.s_axi_awsize                   (s_axi_awsize      ),
.s_axi_awburst                  (s_axi_awburst     ),
.s_axi_awlock                   (s_axi_awlock      ),
.s_axi_awcache                  (s_axi_awcache     ),
.s_axi_awprot                   (s_axi_awprot      ),
.s_axi_awqos                    (4'h0              ),
.s_axi_awvalid                  (s_axi_awvalid     ),
.s_axi_awready                  (s_axi_awready     ),
// Slave Interface Write Data Ports
.s_axi_wdata                    (s_axi_wdata       ),
.s_axi_wstrb                    (s_axi_wstrb       ),
.s_axi_wlast                    (s_axi_wlast       ),
.s_axi_wvalid                   (s_axi_wvalid      ),
.s_axi_wready                   (s_axi_wready      ),
// Slave Interface Write Response Ports
.s_axi_bid                      (s_axi_bid         ),
.s_axi_bresp                    (s_axi_bresp       ),
.s_axi_bvalid                   (s_axi_bvalid      ),
.s_axi_bready                   (s_axi_bready      ),
// Slave Interface Read Address Ports
.s_axi_arid                     (s_axi_arid        ),
.s_axi_araddr                   (s_axi_araddr      ),
.s_axi_arlen                    (s_axi_arlen       ),
.s_axi_arsize                   (s_axi_arsize      ),
.s_axi_arburst                  (s_axi_arburst     ),
.s_axi_arlock                   (s_axi_arlock      ),
.s_axi_arcache                  (s_axi_arcache     ),
.s_axi_arprot                   (s_axi_arprot      ),
.s_axi_arqos                    (4'h0              ),
.s_axi_arvalid                  (s_axi_arvalid     ),
.s_axi_arready                  (s_axi_arready     ),
// Slave Interface Read Data Ports
.s_axi_rid                      (s_axi_rid         ),
.s_axi_rdata                    (s_axi_rdata       ),
.s_axi_rresp                    (s_axi_rresp       ),
.s_axi_rlast                    (s_axi_rlast       ),
.s_axi_rvalid                   (s_axi_rvalid      ),
.s_axi_rready                   (s_axi_rready      ),
//DEBUG       
.wrlvl_dq_check                 (wrlvl_dq_check    ) ,
.rd_level_dqs_check             (rd_level_dqs_check) ,
.init_cur_state                 (init_cur_state    ) ,
.idelay_ld                      (idelay_ld         ) ,
.mpr_rdlvl_dly                  (mpr_rdlvl_dly     ) ,
.cal_done                       (cal_done          ) 
);

//***************************************************************************
// debayer
//***************************************************************************


wire        rgb_vs;
wire        rgb_hs;
wire        rgb_de;
wire        rgb_valid;
wire [47:0] rgb_datax2;
wire [15:0] r_gain = 16'd255;
wire [15:0] g_gain = 16'd255;
wire [15:0] b_gain = 16'd255;

debayer_top_2to1 debayer_top
(
	.in_pclk		  (vid_clk_dvi2),//(i_mipi_rx_pclk ),
	.in_rstn		  (vid_rst_n	),
	
	.raw_vs_i		  (ch0_vs		      ),
	.raw_hs_i		  (ch0_hs		      ),
	.raw_de_i		  (ch0_de		      ),
	.raw_valid_i	(ch0_de	        ),
	.raw_datax4_i	({ch0_b,ch0_g}	),
	.r_gain       (r_gain          ),
  .g_gain       (g_gain          ),
  .b_gain       (b_gain          ),
	.rgb_vs_o		  (rgb_vs         ),
	.rgb_hs_o		  (rgb_hs         ),
	.rgb_de_o		  (rgb_de         ),
	.rgb_valid_o	(rgb_valid      ),
	.rgb_datax2_o (rgb_datax2     )//b,g,r,b,g,r
);

wire [47:0] image_rgb_input = {
  rgb_datax2[31:24], rgb_datax2[39:32], rgb_datax2[47:40],
  rgb_datax2[7:0],   rgb_datax2[15:8],  rgb_datax2[23:16]
};
wire [3:0] image_requested_mode;
wire [10:0] image_requested_threshold;
wire [3:0] image_active_mode;
wire [10:0] image_active_threshold;
wire [3:0] image_object_count;
wire [4:0] image_shape_mask;
wire wb_vs;
wire wb_hs;
wire wb_de;
wire [47:0] image_algorithm_rgb;
wire [47:0] image_display_rgb;
wire image_vs;
wire image_hs;
wire image_de;
wire [47:0] image_rgb_output;
wire image_fifo_overflow;
wire image_fifo_underflow;

assign led[3] = cam_i2c_nack_seen | image_fifo_overflow | image_fifo_underflow;

reg [2:0] uart_mode_meta;
reg [2:0] uart_mode_sync;
reg uart_mode_req_meta;
reg uart_mode_req_sync;
reg uart_mode_req_seen;
wire uart_mode_select_valid = uart_mode_req_sync ^ uart_mode_req_seen;

always @(posedge vid_clk_dvi2 or negedge vid_rst_n) begin
  if (!vid_rst_n) begin
    uart_mode_meta <= 3'd0;
    uart_mode_sync <= 3'd0;
    uart_mode_req_meta <= 1'b0;
    uart_mode_req_sync <= 1'b0;
    uart_mode_req_seen <= 1'b0;
  end else begin
    uart_mode_meta <= uart_mode_core;
    uart_mode_sync <= uart_mode_meta;
    uart_mode_req_meta <= uart_mode_req_toggle;
    uart_mode_req_sync <= uart_mode_req_meta;
    uart_mode_req_seen <= uart_mode_req_sync;
  end
end

image_control_keys #(
  .DEBOUNCE_CYCLES   (37125),
  .DEFAULT_MODE       (IMAGE_MODE),
  .DEFAULT_THRESHOLD  (SOBEL_THRESHOLD)
) image_controls (
  .clk              (vid_clk_dvi2),
  .rst_n            (vid_rst_n),
  .i_key_down_n     (~uart_ctrl[1]),
  .i_key_up_n       (~uart_ctrl[2]),
  .i_key_mode_n     (~uart_ctrl[0]),
  .i_mode_select_valid(uart_mode_select_valid),
  .i_mode_select    ({1'b0, uart_mode_sync}),
  .o_mode           (image_requested_mode),
  .o_threshold      (image_requested_threshold),
  .o_feedback       ()
);

manual_white_balance_2ppc manual_white_balance (
  .clk              (vid_clk_dvi2),
  .rst_n            (vid_rst_n),
  .i_vs             (rgb_vs),
  .i_hs             (rgb_hs),
  .i_de             (rgb_de),
  .i_rgb            (image_rgb_input),
  .o_vs             (wb_vs),
  .o_hs             (wb_hs),
  .o_de             (wb_de),
  .o_algorithm_rgb  (image_algorithm_rgb),
  .o_display_rgb    (image_display_rgb)
);

wire image_roi_active, image_ccl_limit, image_tracks_stale;
wire image_inspection_active;
wire [1:0] image_inspection_status;
wire [3:0] image_inspection_mask;
wire [10:0] image_inspection_depth;
wire image_inspection_hold;
wire [10:0] image_low_threshold;
wire [7:0] image_overflow_count, image_underflow_count;
reg roi_meta, roi_sync;
// OSD visibility: video-domain level synchronizer.
reg osd_enable_meta, osd_enable_sync;
always @(posedge vid_clk_dvi2 or negedge vid_rst_n)
  if (!vid_rst_n) begin osd_enable_meta<=1'b1; osd_enable_sync<=1'b1; end
  else begin osd_enable_meta<=osd_enable_core; osd_enable_sync<=osd_enable_meta; end
// OSD visibility: end video-domain level synchronizer.
reg inspection_meta, inspection_sync;
reg compare_meta, compare_sync;
reg compare_req_meta, compare_req_sync, compare_req_d, compare_req_pending;
reg [2:0] compare_left_meta, compare_left_sync, compare_left_mode;
reg [2:0] compare_right_meta, compare_right_sync, compare_right_mode;
always @(posedge vid_clk_dvi2 or negedge vid_rst_n) begin
  if (!vid_rst_n) begin
    compare_meta<=0; compare_sync<=0;
    compare_req_meta<=0; compare_req_sync<=0; compare_req_d<=0; compare_req_pending<=0;
    compare_left_meta<=2; compare_left_sync<=2; compare_left_mode<=2;
    compare_right_meta<=3; compare_right_sync<=3; compare_right_mode<=3;
  end else begin
    compare_meta<=uart_enable12; compare_sync<=compare_meta;
    compare_left_meta<=uart_left_core; compare_left_sync<=compare_left_meta;
    compare_right_meta<=uart_right_core; compare_right_sync<=compare_right_meta;
    compare_req_meta<=uart_compare_req_toggle; compare_req_sync<=compare_req_meta;
    compare_req_d<=compare_req_sync;
    if (compare_req_sync ^ compare_req_d) compare_req_pending<=1;
    else if (compare_req_pending) begin
      compare_left_mode<=compare_left_sync; compare_right_mode<=compare_right_sync;
      compare_req_pending<=0;
    end
  end
end
wire [2:0] image_compare_left, image_compare_right;
// Internal mode 6 is not part of the six ordinary UART modes.
wire [3:0] image_processing_mode = (compare_sync && framebuffer_state_sync == 2'd2) ?
                                  4'd6 : image_requested_mode;
always @(posedge vid_clk_dvi2 or negedge vid_rst_n)
  if (!vid_rst_n) begin roi_meta <= 1'b0; roi_sync <= 1'b0; end
  else begin roi_meta <= uart_enable10; roi_sync <= roi_meta; end
always @(posedge vid_clk_dvi2 or negedge vid_rst_n)
  if (!vid_rst_n) begin inspection_meta<=1'b0; inspection_sync<=1'b0; end
  else begin inspection_meta<=uart_enable11; inspection_sync<=inspection_meta; end

image_edge_pipeline_2ppc #(
  .IMAGE_WIDTH      (MAX_HRES),
  .IMAGE_HEIGHT     (MAX_VRES),
  .H_TOTAL_PAIRS    ((MAX_HRES + HFP + HSP + HBP) / 2),
  .PAIR_ADDR_WIDTH  (10),
  .ROW_COUNT_WIDTH  (11),
  .FIFO_ADDR_WIDTH  (13)
) image_edge_pipeline (
  .clk              (vid_clk_dvi2),
  .rst_n            (vid_rst_n),
  .i_mode           (image_processing_mode),
  .i_compare_left   (compare_left_mode),
  .i_compare_right  (compare_right_mode),
  .i_threshold      (image_requested_threshold),
  .i_roi_enable     (roi_sync),
  .i_inspection_enable(inspection_sync),
  .i_source_context ({framebuffer_state_sync, framebuffer_index_sync}),
  .i_vs             (wb_vs),
  .i_hs             (wb_hs),
  .i_de             (wb_de),
  .i_rgb            (image_algorithm_rgb),
  .i_display_rgb    (image_display_rgb),
  .o_active_mode    (image_active_mode),
  .o_compare_left   (image_compare_left),
  .o_compare_right  (image_compare_right),
  .o_active_threshold(image_active_threshold),
  .o_object_count   (image_object_count),
  .o_shape_mask     (image_shape_mask),
  .o_roi_active     (image_roi_active),
  .o_ccl_limit      (image_ccl_limit),
  .o_tracks_stale   (image_tracks_stale),
  .o_inspection_active(image_inspection_active),
  .o_inspection_status(image_inspection_status),
  .o_inspection_mask(image_inspection_mask),
  .o_inspection_depth(image_inspection_depth),
  .o_inspection_hold (image_inspection_hold),
  .o_low_threshold  (image_low_threshold),
  .o_overflow_count (image_overflow_count),
  .o_underflow_count(image_underflow_count),
  .o_vs             (image_vs),
  .o_hs             (image_hs),
  .o_de             (image_de),
  .o_rgb            (image_rgb_output),
  .o_overflow       (image_fifo_overflow),
  .o_underflow      (image_fifo_underflow)
);

wire [7:0] camera_fps_bcd;
camera_fps_meter #(
  .REF_CLK_HZ       (5000000)
) camera_fps_meter_inst (
  .frame_clk        (i_mipi_rx_pclk),
  .frame_rst_n      (w_mipi_rx_pclk_arstn),
  .frame_vs         (w_mipi_rx_vs),
  .ref_clk          (CLK_5M),
  .ref_rst_n        (w_arstn),
  .display_clk      (vid_clk_dvi2),
  .display_rst_n    (vid_rst_n),
  .o_fps_bcd        (camera_fps_bcd)
);

wire osd_vs;
wire osd_hs;
wire osd_de;
wire [47:0] osd_rgb;
reg [1:0] framebuffer_state_meta;
reg [1:0] framebuffer_state_sync;
reg framebuffer_saved_meta;
reg framebuffer_saved_sync;
reg [2:0] framebuffer_count_meta;
reg [2:0] framebuffer_count_sync;
reg [2:0] framebuffer_index_meta;
reg [2:0] framebuffer_index_sync;
always @(posedge vid_clk_dvi2 or negedge vid_rst_n) begin
  if (!vid_rst_n) begin
    framebuffer_state_meta <= 2'd0;
    framebuffer_state_sync <= 2'd0;
    framebuffer_saved_meta <= 1'b0;
    framebuffer_saved_sync <= 1'b0;
    framebuffer_count_meta <= 3'd0;
    framebuffer_count_sync <= 3'd0;
    framebuffer_index_meta <= 3'd0;
    framebuffer_index_sync <= 3'd0;
  end else begin
    framebuffer_state_meta <= framebuffer_state;
    framebuffer_state_sync <= framebuffer_state_meta;
    framebuffer_saved_meta <= framebuffer_saved_valid;
    framebuffer_saved_sync <= framebuffer_saved_meta;
    framebuffer_count_meta <= framebuffer_saved_count;
    framebuffer_count_sync <= framebuffer_count_meta;
    framebuffer_index_meta <= framebuffer_saved_index;
    framebuffer_index_sync <= framebuffer_index_meta;
  end
end
video_status_osd_2ppc #(
  .IMAGE_WIDTH      (MAX_HRES),
  .IMAGE_HEIGHT     (MAX_VRES),
  .PAIR_ADDR_WIDTH  (10),
  .ROW_COUNT_WIDTH  (11),
  .COLOR_DIAGNOSTICS(0)
) video_status_osd (
  .clk              (vid_clk_dvi2),
  .rst_n            (vid_rst_n),
  .i_enable         (osd_enable_sync),
  .i_vs             (image_vs),
  .i_hs             (image_hs),
  .i_de             (image_de),
  .i_rgb            (image_rgb_output),
  .i_fps_bcd        (camera_fps_bcd),
  .i_mode           (image_active_mode),
  .i_compare_left   (image_compare_left),
  .i_compare_right  (image_compare_right),
  .i_object_count   (image_object_count),
  .i_shape_mask     (image_shape_mask),
  .i_frame_state    (framebuffer_state_sync),
  .i_saved_valid    (framebuffer_saved_sync),
  .i_saved_count    (framebuffer_count_sync),
  .i_saved_index    (framebuffer_index_sync),
  .i_high_threshold (image_active_threshold),
  .i_low_threshold  (image_low_threshold),
  .i_roi_active     (image_roi_active),
  .i_ccl_limit      (image_ccl_limit),
  .i_tracks_stale   (image_tracks_stale),
  .i_inspection_active(image_inspection_active),
  .i_inspection_status(image_inspection_status),
  .i_inspection_mask(image_inspection_mask),
  .i_inspection_depth(image_inspection_depth),
  .i_inspection_hold (image_inspection_hold),
  .i_overflow_count (image_overflow_count),
  .i_underflow_count(image_underflow_count),
  .i_color_valid    (1'b0),
  .i_color_mean_bcd (36'd0),
  .i_color_sat_bcd  (36'd0),
  .o_vs             (osd_vs),
  .o_hs             (osd_hs),
  .o_de             (osd_de),
  .o_rgb            (osd_rgb)
);

wire [47:0] image_datax2 = {
  osd_rgb[31:24], osd_rgb[39:32], osd_rgb[47:40],
  osd_rgb[7:0],   osd_rgb[15:8],  osd_rgb[23:16]
};
wire display_pair_vs = osd_vs;
wire display_pair_hs = osd_hs;
wire display_pair_de = osd_de;
wire [47:0] display_datax2 = image_datax2;

reg rgb_vs_r = 'd0;
always @( posedge hdmi_tx_slow_clk )
begin
  rgb_vs_r <= display_pair_vs;
end
assign pos_vs = {rgb_vs_r,display_pair_vs} == 2'b01;
reg vid_cnt = 'd0;
reg [7:0] hdmi_tx_rdata ;
reg [7:0] hdmi_tx_gdata ;
reg [7:0] hdmi_tx_bdata ;
reg hdmi_tx_vs;
reg hdmi_tx_hs;
reg hdmi_tx_de;
always @( posedge hdmi_tx_slow_clk )
begin
    if( pos_vs )
      vid_cnt <= 1'b1;
    else if( display_pair_de )
      vid_cnt <= ~vid_cnt ;

    if( vid_cnt )
      {hdmi_tx_bdata,hdmi_tx_gdata,hdmi_tx_rdata} <= display_datax2[23:0];
    else 
      {hdmi_tx_bdata,hdmi_tx_gdata,hdmi_tx_rdata} <= display_datax2[47:24];

  hdmi_tx_vs <= display_pair_vs;
  hdmi_tx_hs <= display_pair_hs;
  hdmi_tx_de <= display_pair_de;
end
//==============================================================================
// MIPI DSI
//==============================================================================
// signal 

reg		[25:0]	r_rst_cnt;

wire	[31:0]	w_axi_rdata;
wire			w_axi_awready;
wire			w_axi_wready;
wire			w_axi_arready;
wire			w_axi_rvalid;
wire			w_axi_bvalid;

wire	[6:0]	w_axi_awaddr;
wire			w_axi_awvalid;
wire	[31:0]	w_axi_wdata;
wire			w_axi_wvalid;
wire			w_axi_bready;
wire	[6:0]	w_axi_araddr;
wire			w_axi_arvalid;
wire			w_axi_rready;

wire			w_confdone;
assign w_confdone = 1'b1;

assign  LCD_POWER 			= i_arstn;
assign	LCD_RST_P	      = ~w_arstn;//~r_rst_cnt[23]; LCD复位先释放，然后再释放MIPI 的复位
assign	mipi_dp_clk_RST		= ~i_arstn;
assign	mipi_dp_data0_RST	= ~i_arstn;
assign	mipi_dp_data1_RST	= ~i_arstn;
assign	mipi_dp_data2_RST	= ~i_arstn;
assign	mipi_dp_data3_RST	= ~i_arstn;
////////////////////////////////////////////////////////////////
always@(posedge i_mipi_clk or  negedge w_arstn )
begin
  if ( !w_arstn ) begin
    r_rst_cnt	<= 'd0;
  end else 		
    r_rst_cnt	<= r_rst_cnt[25] ? r_rst_cnt :r_rst_cnt + 1'b1;
end

wire axi_rst_n = r_rst_cnt[25];

reg [26:0] dly_cnt = 'd0;

always @( posedge vid_clk_dvi2 or negedge w_arstn )
begin
  if( !w_arstn )
    dly_cnt <= 'd0;
  else if( w_confdone )
    dly_cnt <= dly_cnt[26] ? dly_cnt :(dly_cnt + 1'b1);
  else 
    dly_cnt <= 'd0;
end 

assign vid_rst_n = dly_cnt[26];




wire hs;
wire vs;
wire de;
wire [7:0] rgb_r;
wire [7:0] rgb_g;
wire [7:0] rgb_b;

color_bar_rgb #(
  .HS_POLORY       (1'b1),
  .VS_POLORY       (1'b1),
  .H_FRONT_PORCH   (HFP),
  .H_SYNC          (HSP),
  .H_VALID         (MAX_HRES),
  .H_BACK_PORCH    (HBP),
  .V_FRONT_PORCH   (VFP),
  .V_SYNC          (VSP),
  .V_VALID         (MAX_VRES),
  .V_BACK_PORCH    (VBP),
  .TEST_MODE       (2'd2)
) u_hdmi_test_pattern (
  .clk       (hdmi_tx_slow_clk),
  .rst_n     (vid_rst_n),
  .i_rdata   (8'd0),
  .i_gdata   (8'd0),
  .i_bdata   (8'd0),
  .h_cnt     (),
  .v_cnt     (),
  .hs        (hs),
  .vs        (vs),
  .de        (de),
  .w_h_state (),
  .w_v_state (),
  .rgb_r     (rgb_r),
  .rgb_g     (rgb_g),
  .rgb_b     (rgb_b)
);
  
  // color_bar_rgb #(
  // .HS_POLORY 		(1'b1		),
  // .VS_POLORY 		(1'b1		),
  // .H_FRONT_PORCH 	(HFP		),///2
  // .H_SYNC 		(HSP		),//
  // .H_VALID 		(MAX_HRES	),//
  // .H_BACK_PORCH 	(HBP		),//
  // .V_FRONT_PORCH 	(VFP		),
  // .V_SYNC 		(VSP		),
  // .V_VALID 		(MAX_VRES	),
  // .V_BACK_PORCH 	(VBP		),
  // .TEST_MODE 		(2'd2)
  // )u_color_bar_rgb1(
  // /*i*/.clk	(vid_clk_dvi2),//(vid_clk),
  // /*i*/.rst_n	(vid_rst_n),
  // /*o*/.hs	(hs),
  // /*o*/.vs	(vs),
  // /*o*/.de	(de),
  // // /*O*/.h_cnt (h_cnt),
  // // /*O*/.v_cnt (v_cnt),
  // /*o*/.rgb_r	(rgb_r),    //像素数据、红色分量
  // /*o*/.rgb_g	(rgb_g),    //像素数据、绿色分量
  // /*o*/.rgb_b (rgb_b)    //像素数据、蓝色分量
  
  // );

//=================================================================================
//hdmi tx ctrl 
//=================================================================================
wire                            video_hs;
wire                            video_vs;
wire                            video_de;
wire[7:0]                       video_r;
wire[7:0]                       video_g;
wire[7:0]                       video_b;

assign tmds_tx_data0_TX_OE = 1'b1;
assign tmds_tx_data1_TX_OE = 1'b1;
assign tmds_tx_data2_TX_OE = 1'b1;
assign tmds_tx_clk_TX_OE   = 1'b1;

assign tmds_tx_data0_TX_RST = 1'b0;
assign tmds_tx_data1_TX_RST = 1'b0;
assign tmds_tx_data2_TX_RST = 1'b0;
assign tmds_tx_clk_TX_RST   = 1'b0;

// 	  color_bar color_bar_m0(
// 	.clk(hdmi_tx_slow_clk),
// 	.rst(~vid_rst_n),
// 	.hs(video_hs),
// 	.vs(video_vs),
// 	.de(video_de),
// 	.rgb_r(video_r),
// 	.rgb_g(video_g),
// 	.rgb_b(video_b)
// );

wire [9:0] tmds_data0;
wire [9:0] tmds_data1;
wire [9:0] tmds_data2;
wire [9:0] tmds_clk ;
wire [7:0] gamma_rdata ;
wire [7:0] gamma_gdata ;
wire [7:0] gamma_bdata ;
wire gamma_valid;
wire gamma_hs;
wire gamma_vs;
wire gamma_sel = 1'b0;

wire [7:0] con_rdata ;
wire [7:0] con_gdata ;
wire [7:0] con_bdata ;
wire con_de;
wire con_hs;
wire con_vs;
wire con_sel;

wire [7:0] BRIGHT_SIG    ;
wire CONTRAST_SIG_G;
wire CONTRAST_SIG_R;
wire [7:0] CONTRAST_G    ;
wire CONTRAST_SIG_B;
wire [7:0] BRIGHT        ;
wire [7:0] CONTRAST_R    ;


wire CONTRAST_B    ;


gamma_correction
#(
	.DATA_WIDTH		(8),
	.GAMMA_CURVE	("./rtl/gamma_conrrection/2P2.mem")
)
inst_gamma_correction
(
	.i_pclk		(hdmi_tx_slow_clk),
	.i_rstn		(vid_rst_n),
	
	.i_red		(hdmi_tx_rdata),//(con_rdata  ),//
	.i_green	(hdmi_tx_gdata),//(con_gdata  ),//
	.i_blue		(hdmi_tx_bdata),//(con_bdata  ),//
  .i_valid	(hdmi_tx_de   ),//(con_de     ),//
  .i_hs     (hdmi_tx_hs   ),//(con_hs     ),//
  .i_vs     (hdmi_tx_vs   ),//(con_vs     ),//
	.o_blue		(gamma_bdata		),
  .o_green	(gamma_gdata	  ),
	.o_red		(gamma_rdata		),
	.o_valid	(gamma_valid	  ),
  .o_hs     (gamma_hs       ),
  .o_vs     (gamma_vs       )
);

dvi_encoder dvi_encoder_m0
(
	.pixelclk      		(hdmi_tx_slow_clk          ),// system clock
	.rst_p         		(~vid_rst_n      ),// reset
	.i_bdata      		(HDMI_TEST_PATTERN ? rgb_b : (gamma_sel ? gamma_bdata : hdmi_tx_rdata)),
	.i_gdata     		  (HDMI_TEST_PATTERN ? rgb_g : (gamma_sel ? gamma_gdata : hdmi_tx_gdata)),
	.i_rdata       		(HDMI_TEST_PATTERN ? rgb_r : (gamma_sel ? gamma_rdata : hdmi_tx_bdata)),
  .i_de            	(HDMI_TEST_PATTERN ? de    : (gamma_sel ? gamma_valid : hdmi_tx_de)),
	.i_hs         		(HDMI_TEST_PATTERN ? hs    : (gamma_sel ? gamma_hs : hdmi_tx_hs)),
	.i_vs         		(HDMI_TEST_PATTERN ? vs    : (gamma_sel ? gamma_vs : hdmi_tx_vs)),
	
  .video_format     (video_format), //// 00 = RGB, 01 = YCbCr 4:2:2, 10 = YCbCr 4:4:4
  .video_VIC        (0),
	.audio_L			    (audio_L),
  .audio_R			    (audio_R),
  .audio_valid		  (audio_valid),
  .audio_N                (6144),     //(20'h01880),//     
  .audio_CTS              (148500),
  .audio_sample_frequency (audio_samp_freq),    //(3'b000),// 
  .audio_word_length      ({audio_samp_word_len,audio_max_word_length}),//(4'b1011),//

	.tmds_data0    		(tmds_data0),
  .tmds_data1    		(tmds_data1),
  .tmds_data2    		(tmds_data2),
  .tmds_clk      	  (tmds_clk  )
);
assign tmds_tx_clk_TX_DATA   = ~tmds_clk;
assign tmds_tx_data0_TX_DATA = ~tmds_data0;
assign tmds_tx_data1_TX_DATA = ~tmds_data1;
assign tmds_tx_data2_TX_DATA = ~tmds_data2;

// USER1 remains present in the periphery design, but the release image does
// not instantiate the EDB/VIO/logic-analyzer core.  Consume every USER1 input
// so synthesis preserves the complete interface expected by the periphery.
assign jtag_inst1_TDO = jtag_inst1_CAPTURE ^ jtag_inst1_DRCK ^
                        jtag_inst1_RESET ^ jtag_inst1_RUNTEST ^
                        jtag_inst1_SEL ^ jtag_inst1_SHIFT ^
                        jtag_inst1_TCK ^ jtag_inst1_TDI ^
                        jtag_inst1_TMS ^ jtag_inst1_UPDATE;

endmodule
