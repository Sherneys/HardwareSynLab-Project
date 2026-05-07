//==============================================================================
// vga_sync.v
//------------------------------------------------------------------------------
// VGA 640x480 @ 60Hz timing generator for the Basys 3 board.
//
// Industry-standard VESA timing (pixel clock = 25.175 MHz, we use 25 MHz which
// is close enough for all modern monitors):
//
//              Visible  Front  Sync  Back   Total
//   Horizontal   640     16     96    48     800
//   Vertical     480     10      2    33     525
//
// Output:
//   hsync/vsync : active-LOW sync pulses driven to the VGA connector
//   h_count/v_count : current pixel/line counters (0-based)
//   video_on    : HIGH only inside the 640x480 visible region
//   pixel_tick  : one 25 MHz clock pulse per pixel (equal to clk here)
//
// The downstream VGA output logic should gate the RGB channels with video_on
// or drive them to 0 outside the visible area, otherwise the monitor may
// show garbage during blanking.
//==============================================================================
`timescale 1ns / 1ps

module vga_sync #(
    parameter H_VISIBLE   = 640,
    parameter H_FRONT     = 16,
    parameter H_SYNC      = 96,
    parameter H_BACK      = 48,
    parameter V_VISIBLE   = 480,
    parameter V_FRONT     = 10,
    parameter V_SYNC      = 2,
    parameter V_BACK      = 33
)(
    input  wire        clk_25m,    // 25 MHz pixel clock
    input  wire        rst_n,      // active-low synchronous reset
    output reg         hsync,      // active-low
    output reg         vsync,      // active-low
    output wire        video_on,   // 1 inside visible area
    output wire [9:0]  h_count,    // 0..799
    output wire [9:0]  v_count,    // 0..524
    output wire        pixel_tick  // 25 MHz tick (== clk_25m edge)
);

    localparam H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK; // 800
    localparam V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK; // 525

    // Horizontal sync range: [H_VISIBLE+H_FRONT, H_VISIBLE+H_FRONT+H_SYNC)
    localparam H_SYNC_START = H_VISIBLE + H_FRONT;                 // 656
    localparam H_SYNC_END   = H_VISIBLE + H_FRONT + H_SYNC;        // 752
    // Vertical sync range: [V_VISIBLE+V_FRONT, V_VISIBLE+V_FRONT+V_SYNC)
    localparam V_SYNC_START = V_VISIBLE + V_FRONT;                 // 490
    localparam V_SYNC_END   = V_VISIBLE + V_FRONT + V_SYNC;        // 492

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    // Pixel counter: wraps every H_TOTAL pixels.
    // Line counter: increments when h_cnt wraps, wraps every V_TOTAL lines.
    always @(posedge clk_25m) begin
        if (!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 10'd0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 10'd0;
                else
                    v_cnt <= v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    // Registered sync outputs (avoid combinational glitches to the VGA pins).
    // VGA spec: hsync/vsync are active-LOW for 640x480@60Hz.
    always @(posedge clk_25m) begin
        if (!rst_n) begin
            hsync <= 1'b1;
            vsync <= 1'b1;
        end else begin
            hsync <= ~((h_cnt >= H_SYNC_START) && (h_cnt < H_SYNC_END));
            vsync <= ~((v_cnt >= V_SYNC_START) && (v_cnt < V_SYNC_END));
        end
    end

    reg video_on_reg;
    always @(posedge clk_25m) begin
        if (!rst_n)
            video_on_reg <= 1'b0;
        else
            video_on_reg <= (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);
    end

    assign video_on   = video_on_reg;
    assign h_count    = h_cnt;
    assign v_count    = v_cnt;
    assign pixel_tick = 1'b1; // every rising edge of clk_25m is a pixel

endmodule
