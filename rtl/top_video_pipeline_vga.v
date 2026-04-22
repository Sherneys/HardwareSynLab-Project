//==============================================================================
// top_video_pipeline_vga.v   (EXTRA-CREDIT VARIANT - full 640x480)
//------------------------------------------------------------------------------
// Same pipeline as top_video_pipeline.v but configured so that the frame
// buffer stores one pixel per VGA pixel (no pixel-doubling), giving a real
// 640x480 display rather than an upscaled 320x240.
//
// Memory budget
// -------------
//   Basys 3 has 1,800 Kb of block RAM.
//   640 x 480 pixels = 307,200 pixels total.
//   1,800,000 / 307,200 = 5.86 bits/pixel max.
// So we cannot afford full-colour RGB444 (12 bpp) nor even RGB332 (8 bpp).
// The trade-off chosen here is 4-bit grayscale:
//   307,200 x 4 = 1,228,800 bits ≈ 1,200 Kb -> ~35 of 50 BRAM tiles.
//
// The grayscale value is computed at capture time from the camera's RGB565
// output using the approximation Y = (R + 2G + B) / 4 (same as filter_unit).
//
// Filters available in this variant
// ---------------------------------
//   000 : raw grayscale
//   001 : (no-op, same as raw - already grayscale)
//   010 : invert
//   110 : threshold (binary image)
// The colour-channel-isolation filter makes no sense on grayscale storage
// so it is disabled here. Use top_video_pipeline.v for full-colour filters.
//
// How to use: in Vivado, set THIS file as the top module (instead of
// top_video_pipeline.v) to synthesise the 640x480 extra-credit build. The
// constraint file basys3.xdc works unchanged.
//==============================================================================
`timescale 1ns / 1ps

module top_video_pipeline_vga (
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

    // Reset synchroniser
    wire rst_raw = btnC | sw[15];
    reg  [1:0] rst_sync;
    always @(posedge clk_100m) rst_sync <= {rst_sync[0], rst_raw};
    wire rst_n = ~rst_sync[1];

    // Clocks
    wire clk_25m;
    clock_gen u_clkgen (
        .clk_100m(clk_100m), .rst_n(rst_n),
        .clk_25m (clk_25m),  .xclk_25m(ov_xclk)
    );

    assign ov_pwdn    = 1'b0;
    assign ov_reset_n = rst_n;

    // SCCB init --------------------------------------------------------------
    // NOTE: For real 640x480 you will need to reconfigure the OV7670 to VGA
    // output. That means replacing register 0x12 COM7 with 0x00 (VGA+YUV) or
    // 0x04 (VGA+RGB), removing the QVGA scaling writes, and setting 0x0C
    // (COM3) with scaling OFF. See the table inside ov7670_init.v and edit
    // ROM entries 1..9 before synthesising this top module.
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

    // --------------------------------------------------------------------
    // Capture at FULL VGA resolution, storing 4-bit grayscale.
    // --------------------------------------------------------------------
    localparam FRAME_W = 640;
    localparam FRAME_H = 480;
    localparam FB_DEPTH = FRAME_W * FRAME_H; // 307,200
    localparam FB_AW    = 19;                // ceil(log2(307200)) = 19

    // Inline capture logic (variant): reassembles 16-bit RGB565 from the
    // camera, converts to 4-bit grayscale on the fly, and writes one nibble
    // per pixel into the frame buffer. Keeping this inline (vs. a second
    // module) avoids duplicating the file and makes the memory-size
    // contrast with the RGB444 version obvious.
    reg        byte_toggle;
    reg [7:0]  byte_hi;
    reg [9:0]  col;
    reg [9:0]  row;
    reg        cap_we;
    reg [FB_AW-1:0] cap_waddr;
    reg [3:0]  cap_wdata;

    // RGB565 -> 4-bit luma. Take the top 4 bits of each channel (same as
    // RGB444 down-convert), apply (R + 2G + B) / 4 approximation, drop to
    // 4 bits.
    wire [3:0] r4 = byte_hi[7:4];
    wire [3:0] g4 = {byte_hi[2:0], ov_data[7]};
    wire [3:0] b4 = ov_data[4:1];
    wire [5:0] y6 = {2'b00, r4} + {1'b0, g4, 1'b0} + {2'b00, b4};
    wire [3:0] y4 = y6[5:2];

    always @(posedge ov_pclk) begin
        if (ov_vsync) begin
            byte_toggle <= 1'b0;
            col         <= 10'd0;
            row         <= 10'd0;
            cap_we      <= 1'b0;
        end else begin
            cap_we <= 1'b0;
            if (ov_href) begin
                byte_toggle <= ~byte_toggle;
                if (!byte_toggle) begin
                    byte_hi <= ov_data;
                end else begin
                    cap_wdata <= y4;
                    cap_waddr <= row * FRAME_W + col;
                    cap_we    <= (col < FRAME_W) && (row < FRAME_H);
                    if (col < FRAME_W - 1) col <= col + 10'd1;
                end
            end else begin
                if (col != 10'd0) begin
                    col <= 10'd0;
                    if (row < FRAME_H - 1) row <= row + 10'd1;
                end
                byte_toggle <= 1'b0;
            end
        end
    end

    // Frame buffer
    wire [FB_AW-1:0] fb_raddr;
    wire [3:0]       fb_rdata;

    frame_buffer #(.DATA_W(4), .DEPTH(FB_DEPTH), .ADDR_W(FB_AW)) u_fb (
        .wclk(ov_pclk), .we(cap_we), .waddr(cap_waddr), .wdata(cap_wdata),
        .rclk(clk_25m), .raddr(fb_raddr), .rdata(fb_rdata)
    );

    // VGA sync
    wire [9:0] h_cnt, v_cnt;
    wire       video_on;
    vga_sync u_vga (
        .clk_25m(clk_25m), .rst_n(rst_n),
        .hsync(vga_hsync), .vsync(vga_vsync),
        .video_on(video_on), .h_count(h_cnt), .v_count(v_cnt),
        .pixel_tick()
    );

    // Native read address (no pixel-doubling)
    assign fb_raddr = v_cnt * FRAME_W + h_cnt;

    // Grayscale filter selection
    reg [3:0] luma_filt;
    always @* begin
        case (sw[2:0])
            3'b010 : luma_filt = ~fb_rdata;                 // invert
            3'b110 : luma_filt = (fb_rdata >= 4'd8) ? 4'hF : 4'h0; // threshold
            default: luma_filt = fb_rdata;                  // raw/grayscale
        endcase
    end

    assign vga_r = video_on ? luma_filt : 4'h0;
    assign vga_g = video_on ? luma_filt : 4'h0;
    assign vga_b = video_on ? luma_filt : 4'h0;

    // LEDs
    reg [1:0] vsync_sync;
    always @(posedge clk_25m) vsync_sync <= {vsync_sync[0], ov_vsync};
    reg [5:0] vsync_cnt;
    reg       heartbeat;
    always @(posedge clk_25m) begin
        if (!rst_n) begin vsync_cnt <= 0; heartbeat <= 0; end
        else if (vsync_sync[1] && !vsync_sync[0]) begin
            if (vsync_cnt == 6'd29) begin vsync_cnt <= 0; heartbeat <= ~heartbeat; end
            else vsync_cnt <= vsync_cnt + 1;
        end
    end

    assign led[0]    = cfg_done;
    assign led[1]    = heartbeat;
    assign led[4:2]  = sw[2:0];
    assign led[15:5] = 11'd0;

endmodule
