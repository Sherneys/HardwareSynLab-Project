//==============================================================================
// top_video_pipeline_vga.v   (EXTRA-CREDIT VARIANT - full 640x480 RGB121)
//------------------------------------------------------------------------------
// Real 640x480 frame buffer with 4-bit RGB121 colour (1 bit R + 2 bits G + 1 bit B
// = 16 distinct colours). Same memory budget as the previous grayscale variant,
// just packed differently.
//
// Memory budget
// -------------
//   Basys 3 has 1,800 Kb of BRAM. 640 × 480 = 307,200 pixels.
//   307,200 × 4 = 1,228,800 bits  ≈  1,200 Kb  →  ~35 of 50 BRAM tiles.
//
// Why RGB121 (and not full colour)?
//   We have only 5.86 bits/pixel available for full VGA. RGB444 (12 bpp) needs
//   3.7 Mb — over 2× the BRAM. RGB121 fits the same memory as 4-bit grayscale
//   but gives crude colour: 2 reds × 4 greens × 2 blues = 16 colours, similar
//   to early 1980s VGA / EGA palettes.
//
// Pixel format in BRAM (4 bits per pixel):
//   bit 3   : R   (0 = no red,    1 = full red)
//   bit 2:1 : G   (00 = no green, 11 = full green, 4 levels)
//   bit 0   : B   (0 = no blue,   1 = full blue)
//
// Capture extracts the top bit of R, top 2 bits of G, top bit of B from the
// RGB565 stream. Display expands those 4 bits back to RGB444 for the DAC.
//
// Filters available
//   000 : raw colour
//   001 : grayscale (Y = (R + 2G + B) / 4)
//   010 : invert
//   110 : threshold (binary)
// Colour-channel isolation filters are skipped here (only 1 bit of R/B
// makes them useless). Use top_video_pipeline.v for full-RGB filtering.
//
// How to use: in Vivado, set THIS file as top instead of top_video_pipeline.v.
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

    // Reset (centre pushbutton btnC, synchronised into 100 MHz domain)
    reg  [1:0] rst_sync;
    always @(posedge clk_100m) rst_sync <= {rst_sync[0], btnC};
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
    // ov7670_init.v already programs the camera for native VGA + RGB565 +
    // manual white-balance gains + denoise, so no edits are needed here.
    // Building this variant: in Vivado, set top_video_pipeline_vga as the
    // top-level module (Sources → right-click → Set as Top), re-synthesize.
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

    // Inline capture (RGB565 -> RGB121, 1 nibble per VGA pixel).
    // Phase 0 saves the HIGH byte (RRRRRGGG); phase 1 has the LOW byte
    // (GGGBBBBB) on ov_data. We pack the top bits of each channel:
    //   bit 3   : R   = byte_hi[7]                  (top bit of R[4:0])
    //   bit 2:1 : G   = byte_hi[2:1]                (top 2 bits of G[5:0])
    //   bit 0   : B   = ov_data[4]                  (top bit of B[4:0])
    reg        byte_toggle;
    reg [7:0]  byte_hi;
    reg [9:0]  col;
    reg [9:0]  row;
    reg        cap_we;
    reg [FB_AW-1:0] cap_waddr;
    reg [3:0]  cap_wdata;
    reg [FB_AW-1:0] waddr_lin;

    wire       r1 = byte_hi[7];
    wire [1:0] g2 = byte_hi[2:1];
    wire       b1 = ov_data[4];
    wire [3:0] rgb121 = {r1, g2, b1};

    always @(posedge ov_pclk) begin
        if (ov_vsync) begin
            byte_toggle <= 1'b0;
            col         <= 10'd0;
            row         <= 10'd0;
            cap_we      <= 1'b0;
            waddr_lin   <= {FB_AW{1'b0}};
        end else begin
            cap_we <= 1'b0;
            if (ov_href) begin
                byte_toggle <= ~byte_toggle;
                if (!byte_toggle) begin
                    byte_hi <= ov_data;
                end else begin
                    cap_wdata <= rgb121;
                    if (waddr_lin < FB_DEPTH) begin
                        cap_waddr <= waddr_lin;
                        cap_we    <= 1'b1;
                        waddr_lin <= waddr_lin + {{(FB_AW-1){1'b0}}, 1'b1};
                    end
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

    // Look one pixel ahead to compensate for BRAM's 1-cycle read latency.
    // Without this, the image is shifted 1 pixel right and the leftmost
    // column shows garbage from the last blanking-period BRAM read.
    wire [9:0] h_rd_next = (h_cnt == 10'd799) ? 10'd0 : h_cnt + 10'd1;
    wire [9:0] v_rd_next = (h_cnt == 10'd799) ?
                           ((v_cnt == 10'd524) ? 10'd0 : v_cnt + 10'd1) : v_cnt;
    wire [9:0] h_rd_sat  = (h_rd_next >= 10'd640) ? 10'd639 : h_rd_next;
    wire [9:0] v_rd_sat  = (v_rd_next >= 10'd480) ? 10'd479 : v_rd_next;
    // 640 = 512 + 128, avoid runtime multiplier
    wire [FB_AW-1:0] row_x640 = (v_rd_sat << 9) + (v_rd_sat << 7);
    assign fb_raddr = row_x640 + {{(FB_AW-10){1'b0}}, h_rd_sat};

    // Decode RGB121 nibble back into RGB444 channels for the VGA DAC:
    //   R: 1 bit -> 0x0 or 0xF
    //   G: 2 bits -> 0x0 / 0x5 / 0xA / 0xF (mapped 4 levels across full range)
    //   B: 1 bit -> 0x0 or 0xF
    wire [3:0] r_dec = {4{fb_rdata[3]}};
    wire [3:0] g_dec = {fb_rdata[2:1], fb_rdata[2:1]};
    wire [3:0] b_dec = {4{fb_rdata[0]}};

    // (R + 2G + B) / 4 luma for grayscale and threshold filters
    wire [5:0] y6   = {2'b00, r_dec} + {1'b0, g_dec, 1'b0} + {2'b00, b_dec};
    wire [3:0] luma = y6[5:2];

    reg [3:0] r_out, g_out, b_out;
    always @* begin
        case (sw[2:0])
            3'b010: begin                              // invert
                r_out = ~r_dec;
                g_out = ~g_dec;
                b_out = ~b_dec;
            end
            3'b001: begin                              // grayscale
                r_out = luma;
                g_out = luma;
                b_out = luma;
            end
            3'b110: begin                              // threshold (binary)
                r_out = (luma >= 4'd8) ? 4'hF : 4'h0;
                g_out = (luma >= 4'd8) ? 4'hF : 4'h0;
                b_out = (luma >= 4'd8) ? 4'hF : 4'h0;
            end
            default: begin                             // raw colour
                r_out = r_dec;
                g_out = g_dec;
                b_out = b_dec;
            end
        endcase
    end

    assign vga_r = video_on ? r_out : 4'h0;
    assign vga_g = video_on ? g_out : 4'h0;
    assign vga_b = video_on ? b_out : 4'h0;

    // LEDs
    reg [1:0] vsync_sync;
    always @(posedge clk_25m) vsync_sync <= {vsync_sync[0], ov_vsync};
    reg [5:0] vsync_cnt;
    reg       heartbeat;
    always @(posedge clk_25m) begin
        if (!rst_n) begin vsync_cnt <= 0; heartbeat <= 0; end
        else if (!vsync_sync[1] && vsync_sync[0]) begin
            if (vsync_cnt == 6'd29) begin vsync_cnt <= 0; heartbeat <= ~heartbeat; end
            else vsync_cnt <= vsync_cnt + 1;
        end
    end

    assign led[0]    = cfg_done;   // SCCB config finished
    assign led[1]    = heartbeat;  // camera vsync heartbeat
    assign led[4:2]  = sw[2:0];    // filter mode echo
    assign led[15:5] = 11'd0;

endmodule
