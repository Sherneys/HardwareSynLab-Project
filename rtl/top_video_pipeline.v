//==============================================================================
// top_video_pipeline.v   (REVISED)
//------------------------------------------------------------------------------
// OV7670 -> frame buffer -> VGA pipeline. Now with:
//
//  * sw[14] = 1 : DEBUG test-pattern mode. The camera data path is bypassed
//                 and a colour gradient is displayed. Use this first to
//                 verify VGA cabling + sync + pixel clock + RGB pins BEFORE
//                 worrying about camera configuration. If the test pattern
//                 does NOT look like a clean 8-band colour bar, the issue
//                 is on the VGA side, not the camera side.
//
//  * Camera side is unchanged in concept, but the capture module now does
//    in-FPGA 2x2 downsampling, so the OV7670 stays in native VGA mode.
//
//  * BRAM read-latency phase corrected: we advance the read address one
//    cycle early so the pixel that arrives at the filter_unit matches the
//    (h_cnt, v_cnt) currently being displayed.
//
//  * sw[13] = 1 : bypass filter_unit (display raw frame-buffer contents).
//                 Useful while debugging, lets you see exactly what the
//                 camera wrote into BRAM without any filter interpretation.
//
// Switch map summary
//   sw[2:0]  : filter mode selector (see filter_unit.v)
//   sw[13]   : bypass filter_unit      (debug)
//   sw[14]   : show test pattern        (debug)
//   sw[15]   : secondary reset
//==============================================================================
`timescale 1ns / 1ps

module top_video_pipeline (
    input  wire        clk_100m,
    input  wire        btnC,
    input  wire [15:0] sw,
    output wire [15:0] led,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire        ov_xclk,
    input  wire        ov_pclk,
    input  wire        ov_vsync,
    input  wire        ov_href,
    input  wire [7:0]  ov_data,
    output wire        ov_reset_n,
    output wire        ov_pwdn,
    inout  wire        ov_sioc,
    inout  wire        ov_siod
);

    //--------------------------------------------------------------------------
    // Reset
    //--------------------------------------------------------------------------
    wire rst_raw = btnC | sw[15];
    reg  [1:0] rst_sync;
    always @(posedge clk_100m) rst_sync <= {rst_sync[0], rst_raw};
    wire rst_n = ~rst_sync[1];

    //--------------------------------------------------------------------------
    // Clocks: 25 MHz pixel clock / camera XCLK
    //--------------------------------------------------------------------------
    wire clk_25m;
    clock_gen u_clkgen (
        .clk_100m (clk_100m),
        .rst_n    (rst_n),
        .clk_25m  (clk_25m),
        .xclk_25m (ov_xclk)
    );

    assign ov_pwdn    = 1'b0;
    assign ov_reset_n = rst_n;

    //--------------------------------------------------------------------------
    // SCCB + init ROM
    //--------------------------------------------------------------------------
    wire       sccb_ready, sccb_start;
    wire [7:0] sccb_slave, sccb_reg_addr, sccb_reg_data;
    wire       cfg_done;

    ov7670_init #(.INPUT_CLK_HZ(25_000_000)) u_init (
        .clk(clk_25m), .rst_n(rst_n), .done(cfg_done),
        .sccb_start(sccb_start), .slave_addr(sccb_slave),
        .reg_addr(sccb_reg_addr), .reg_data(sccb_reg_data),
        .sccb_ready(sccb_ready)
    );

    sccb_master #(.INPUT_CLK_HZ(25_000_000), .SCCB_CLK_HZ(100_000)) u_sccb (
        .clk(clk_25m), .rst_n(rst_n),
        .start(sccb_start), .slave_addr(sccb_slave),
        .reg_addr(sccb_reg_addr), .reg_data(sccb_reg_data),
        .ready(sccb_ready), .sioc(ov_sioc), .siod(ov_siod)
    );

    //--------------------------------------------------------------------------
    // Camera capture: camera is in VGA 640x480, we downsample to 320x240.
    //--------------------------------------------------------------------------
    localparam FRAME_W  = 320;
    localparam FRAME_H  = 240;
    localparam FB_DEPTH = FRAME_W * FRAME_H;      // 76,800
    localparam FB_AW    = 17;                     // ceil(log2(76800))

    wire              cap_we;
    wire [FB_AW-1:0]  cap_waddr;
    wire [11:0]       cap_wdata;

    ov7670_capture #(
        .FRAME_W(FRAME_W), .FRAME_H(FRAME_H),
        .CAM_W  (640),     .CAM_H  (480),
        .ADDR_W (FB_AW)
    ) u_capture (
        .pclk (ov_pclk),
        .vsync(ov_vsync),
        .href (ov_href),
        .data (ov_data),
        .we   (cap_we),
        .waddr(cap_waddr),
        .wdata(cap_wdata)
    );

    //--------------------------------------------------------------------------
    // Frame buffer
    //--------------------------------------------------------------------------
    wire [FB_AW-1:0] fb_raddr;
    wire [11:0]      fb_rdata;

    frame_buffer #(.DATA_W(12), .DEPTH(FB_DEPTH), .ADDR_W(FB_AW)) u_fb (
        .wclk (ov_pclk),
        .we   (cap_we),
        .waddr(cap_waddr),
        .wdata(cap_wdata),
        .rclk (clk_25m),
        .raddr(fb_raddr),
        .rdata(fb_rdata)
    );

    //--------------------------------------------------------------------------
    // VGA sync generator
    //--------------------------------------------------------------------------
    wire [9:0] h_cnt, v_cnt;
    wire       video_on;

    vga_sync u_vga (
        .clk_25m   (clk_25m),
        .rst_n     (rst_n),
        .hsync     (vga_hsync),
        .vsync     (vga_vsync),
        .video_on  (video_on),
        .h_count   (h_cnt),
        .v_count   (v_cnt),
        .pixel_tick()
    );

    // Read one pixel AHEAD so that by the time BRAM returns the data on the
    // next clock edge, the (h_cnt, v_cnt) displayed matches the pixel read.
    // We compute the address using h_cnt+1 (with wrap at line end).
    wire [9:0] h_next = (h_cnt == 10'd799) ? 10'd0 : h_cnt + 10'd1;
    wire [9:0] v_next = (h_cnt == 10'd799) ?
                        ((v_cnt == 10'd524) ? 10'd0 : v_cnt + 10'd1) : v_cnt;

    wire [9:0] src_col_next = h_next[9:1];  // pixel-doubled read
    wire [9:0] src_row_next = v_next[9:1];

    // Saturate src_col/src_row inside the frame so we never read outside the
    // 320x240 window even in blanking.
    wire [9:0] src_col_sat = (src_col_next >= FRAME_W) ? FRAME_W-1 : src_col_next;
    wire [9:0] src_row_sat = (src_row_next >= FRAME_H) ? FRAME_H-1 : src_row_next;

    assign fb_raddr = src_row_sat * FRAME_W + src_col_sat;

    //--------------------------------------------------------------------------
    // Test pattern (debug mode - sw[14] = 1)
    // Generates a clean 8-band colour bar so you can confirm VGA is good.
    //--------------------------------------------------------------------------
    reg [3:0] tp_r, tp_g, tp_b;
    always @* begin
        case (h_cnt[9:7])  // 8 bands of 128 pixels each
            3'd0: {tp_r, tp_g, tp_b} = 12'hFFF; // white
            3'd1: {tp_r, tp_g, tp_b} = 12'hFF0; // yellow
            3'd2: {tp_r, tp_g, tp_b} = 12'h0FF; // cyan
            3'd3: {tp_r, tp_g, tp_b} = 12'h0F0; // green
            3'd4: {tp_r, tp_g, tp_b} = 12'hF0F; // magenta
            3'd5: {tp_r, tp_g, tp_b} = 12'hF00; // red
            3'd6: {tp_r, tp_g, tp_b} = 12'h00F; // blue
            3'd7: {tp_r, tp_g, tp_b} = 12'h000; // black
        endcase
    end

    //--------------------------------------------------------------------------
    // Filter unit
    //--------------------------------------------------------------------------
    wire [3:0] r_filt, g_filt, b_filt;

    filter_unit u_filter (
        .pixel_in (fb_rdata),
        .mode     (sw[2:0]),
        .video_on (video_on),
        .r_out    (r_filt),
        .g_out    (g_filt),
        .b_out    (b_filt)
    );

    //--------------------------------------------------------------------------
    // Output select:
    //   sw[14] = 1 -> test pattern
    //   sw[13] = 1 -> raw frame buffer (no filter) - debug
    //   else       -> filtered camera video
    //--------------------------------------------------------------------------
    reg [3:0] vga_r_reg, vga_g_reg, vga_b_reg;
    always @* begin
        if (!video_on) begin
            vga_r_reg = 4'h0;
            vga_g_reg = 4'h0;
            vga_b_reg = 4'h0;
        end else if (sw[14]) begin
            vga_r_reg = tp_r;
            vga_g_reg = tp_g;
            vga_b_reg = tp_b;
        end else if (sw[13]) begin
            vga_r_reg = fb_rdata[11:8];
            vga_g_reg = fb_rdata[ 7:4];
            vga_b_reg = fb_rdata[ 3:0];
        end else begin
            vga_r_reg = r_filt;
            vga_g_reg = g_filt;
            vga_b_reg = b_filt;
        end
    end

    assign vga_r = vga_r_reg;
    assign vga_g = vga_g_reg;
    assign vga_b = vga_b_reg;

    //--------------------------------------------------------------------------
    // LED status
    //--------------------------------------------------------------------------
    reg [1:0] vsync_sync;
    always @(posedge clk_25m) vsync_sync <= {vsync_sync[0], ov_vsync};
    reg [5:0] vsync_cnt;
    reg       heartbeat;
    always @(posedge clk_25m) begin
        if (!rst_n) begin
            vsync_cnt <= 6'd0;
            heartbeat <= 1'b0;
        end else if (vsync_sync[1] && !vsync_sync[0]) begin
            if (vsync_cnt == 6'd29) begin
                vsync_cnt <= 6'd0;
                heartbeat <= ~heartbeat;
            end else begin
                vsync_cnt <= vsync_cnt + 6'd1;
            end
        end
    end

    assign led[0]    = cfg_done;   // SCCB config finished
    assign led[1]    = heartbeat;  // camera vsync heartbeat
    assign led[4:2]  = sw[2:0];    // filter mode echo
    assign led[13]   = sw[13];
    assign led[14]   = sw[14];
    assign led[15]   = sw[15];
    assign led[12:5] = 8'd0;

endmodule
