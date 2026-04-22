//==============================================================================
// ov7670_capture.v   (REVISED)
//------------------------------------------------------------------------------
// Reassembles RGB565 pixels from the OV7670 parallel output and writes them
// into a 320x240 RGB444 frame buffer.
//
// Key differences from the previous version
// -----------------------------------------
// 1.  Camera is assumed to be in NATIVE VGA mode (640x480). We downsample
//     2x2 on the FPGA side by keeping only pixels where both col and row
//     are even. This removes the dependency on the fragile DCW/scaling
//     registers in the camera config.
//
// 2.  Byte alignment is reset on three safe events, in priority order:
//         * rising edge of VSYNC  (start of vblank)
//         * HREF low              (horizontal blanking)
//     Mid-line HREF glitches can no longer cause persistent byte swap,
//     because each new line's byte pair starts with byte_toggle=0 by
//     construction.
//
// 3.  Address is a LINEAR counter that only advances when we actually
//     write. No runtime multiplier needed.
//
// 4.  Mutually-exclusive if/else if/else branches - no conflicting
//     non-blocking assignments to byte_toggle.
//
// In RGB565 the OV7670 sends the HIGH byte first, LOW byte second:
//     byte_hi = RRRRR GGG         byte_lo = GGG BBBBB
//   -> R4 = byte_hi[7:4]
//   -> G4 = { byte_hi[2:0], byte_lo[7] }
//   -> B4 = byte_lo[4:1]
//==============================================================================
`timescale 1ns / 1ps

module ov7670_capture #(
    parameter FRAME_W  = 320,   // frame-buffer width   (after downsample)
    parameter FRAME_H  = 240,   // frame-buffer height  (after downsample)
    parameter CAM_W    = 640,   // camera output width  (VGA)
    parameter CAM_H    = 480,   // camera output height (VGA)
    parameter ADDR_W   = 17
)(
    input  wire              pclk,
    input  wire              vsync,   // active-HIGH pulse between frames
    input  wire              href,    // HIGH for one line of pixels
    input  wire [7:0]        data,

    output reg               we,
    output reg  [ADDR_W-1:0] waddr,
    output reg  [11:0]       wdata
);

    // Previous-cycle values, for edge detection.
    reg              vsync_d;
    reg              href_d;

    // Byte-assembly state
    reg              byte_toggle;   // 0 = next byte is hi, 1 = next byte is lo
    reg [7:0]        byte_hi;

    // Frame-position counters (in camera's NATIVE 640x480 coordinate space)
    reg [10:0]       cam_col;       // 0..639
    reg [9:0]        cam_row;       // 0..479

    // Linear address counter - advances only when a pixel is actually written
    reg [ADDR_W-1:0] waddr_lin;

    // Localparam for the total number of pixels in the frame buffer
    localparam integer FB_DEPTH = FRAME_W * FRAME_H;

    always @(posedge pclk) begin
        vsync_d <= vsync;
        href_d  <= href;
        we      <= 1'b0;           // default: no write this cycle

        // Priority 1: VSYNC high = new frame incoming. Reset everything.
        if (vsync) begin
            cam_col     <= 11'd0;
            cam_row     <= 10'd0;
            byte_toggle <= 1'b0;
            waddr_lin   <= {ADDR_W{1'b0}};
        end
        // Priority 2: HREF just fell (line just ended). Advance to next line.
        else if (href_d && !href) begin
            cam_col     <= 11'd0;
            byte_toggle <= 1'b0;
            if (cam_row < CAM_H - 1) cam_row <= cam_row + 10'd1;
        end
        // Priority 3: Between lines - sit idle, make sure we're aligned.
        else if (!href) begin
            byte_toggle <= 1'b0;
        end
        // Priority 4: HREF high = active pixel data
        else begin
            if (byte_toggle == 1'b0) begin
                // First byte of the pair (high byte).
                byte_hi     <= data;
                byte_toggle <= 1'b1;
            end else begin
                // Second byte of the pair - we now have a full pixel.
                byte_toggle <= 1'b0;

                // Downsample 2x2: keep ONLY where both cam_col and cam_row
                // are even. This converts 640x480 into 320x240 without
                // touching the camera's internal scaling.
                if (cam_col[0] == 1'b0 && cam_row[0] == 1'b0 &&
                    waddr_lin < FB_DEPTH[ADDR_W-1:0]) begin
                    wdata     <= { byte_hi[7:4],
                                   byte_hi[2:0], data[7],
                                   data[4:1] };
                    waddr     <= waddr_lin;
                    we        <= 1'b1;
                    waddr_lin <= waddr_lin + { {(ADDR_W-1){1'b0}}, 1'b1 };
                end

                // Advance the camera-space column counter every pixel pair.
                if (cam_col < CAM_W - 1) cam_col <= cam_col + 11'd1;
            end
        end
    end

endmodule
