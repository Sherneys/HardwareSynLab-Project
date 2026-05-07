//==============================================================================
// ov7670_capture.v   (RGB565 → RGB444 with 2×2 BOX AVERAGING downsample)
//------------------------------------------------------------------------------
// The OV7670 is configured for RGB565 output (COM7=0x04, COM15=0xD0).
// Each camera pixel is two bytes transmitted MSB-first:
//
//   Byte 0 (high): [7:3] = R[4:0]   [2:0] = G[5:3]
//   Byte 1 (low):  [7:5] = G[2:0]   [4:0] = B[4:0]
//
// 2×2 box-average downsample (FRAME_W × FRAME_H, default 320×240):
//   Each output pixel = average of FOUR camera pixels in a 2×2 box.
//   This is a real low-pass filter: noise variance is reduced 4× (=2× σ),
//   and edge information is preserved better than the old "take pixel 0"
//   nearest-neighbour downsample which threw away 75% of the data.
//
// OV7670 RGB565 byte order (TSLB[4]=0, default "normal" ordering):
//   Phase 0 (first  byte): byte_hi = { R[4:0], G[5:3] }   (RRRRRGGG) ← HIGH byte
//   Phase 1 (second byte): data    = { G[2:0], B[4:0] }   (GGGBBBBB) ← LOW byte
//
// RGB565 → RGB444 mapping (top 4 bits of each 5/6-bit channel):
//   R4 = byte_hi[7:4]
//   G4 = {byte_hi[2:0], data[7]}
//   B4 = data[4:1]
//
// Phase counter (4 bytes per camera-pixel-pair = 1 horizontal output sample):
//   phase 0 : HIGH byte of camera pixel 0  → byte_hi
//   phase 1 : LOW  byte of camera pixel 0  → latch RGB444 in pixel0_reg
//   phase 2 : HIGH byte of camera pixel 1  → byte_hi
//   phase 3 : LOW  byte of camera pixel 1  → form h_avg = (pixel0+pixel1)/2
//             • on EVEN cam_row: store h_avg in line_buf[cam_col]
//             • on ODD  cam_row: read line_buf[cam_col] = top_avg,
//                                form box_avg = (top_avg + h_avg) / 2,
//                                write box_avg to BRAM at output addr.
//
// Write address (linear raster):
//   waddr = (cam_row >> 1) * FRAME_W + cam_col   on cam_row[0]=1
//==============================================================================
`timescale 1ns / 1ps

module ov7670_capture #(
    parameter FRAME_W  = 320,
    parameter FRAME_H  = 240,
    parameter CAM_W    = 640,
    parameter CAM_H    = 480,
    parameter ADDR_W   = 17
)(
    input  wire              pclk,
    input  wire              vsync,
    input  wire              href,
    input  wire [7:0]        data,

    output reg               we,
    output reg  [ADDR_W-1:0] waddr,
    output reg  [11:0]       wdata
);

    reg              href_d;
    reg [1:0]        phase;
    reg [7:0]        byte_hi;
    reg [8:0]        cam_col;          // pixel-pair column 0..(FRAME_W-1)
    reg [9:0]        cam_row;          // line counter 0..(CAM_H-1)
    reg [11:0]       pixel0_reg;       // latched RGB of left  pixel of pair

    // ── 320-entry line buffer for top row of each vertical pair ──────────────
    // Distributed RAM: small enough (FRAME_W × 12) that LUT-RAM is cheap
    // and combinational read avoids extra pipeline stages.
    (* ram_style = "distributed" *)
    reg [11:0] line_buf [0:FRAME_W-1];

    // ── Combinational extraction of the CURRENT camera pixel ─────────────────
    // (uses byte_hi saved last cycle + data this cycle)
    wire [3:0] curr_r = byte_hi[7:4];
    wire [3:0] curr_g = {byte_hi[2:0], data[7]};
    wire [3:0] curr_b = data[4:1];
    wire [11:0] curr_rgb = {curr_r, curr_g, curr_b};

    // ── Horizontal average: (pixel0_reg + curr_rgb) / 2, per channel ─────────
    wire [4:0] hsum_r = {1'b0, pixel0_reg[11:8]} + {1'b0, curr_r};
    wire [4:0] hsum_g = {1'b0, pixel0_reg[ 7:4]} + {1'b0, curr_g};
    wire [4:0] hsum_b = {1'b0, pixel0_reg[ 3:0]} + {1'b0, curr_b};
    wire [11:0] h_avg = {hsum_r[4:1], hsum_g[4:1], hsum_b[4:1]};

    // ── Vertical (box) average: (top_avg + h_avg) / 2, per channel ───────────
    wire [11:0] top_avg = line_buf[cam_col];   // distributed-RAM combinational read
    wire [4:0] vsum_r = {1'b0, top_avg[11:8]} + {1'b0, h_avg[11:8]};
    wire [4:0] vsum_g = {1'b0, top_avg[ 7:4]} + {1'b0, h_avg[ 7:4]};
    wire [4:0] vsum_b = {1'b0, top_avg[ 3:0]} + {1'b0, h_avg[ 3:0]};
    wire [11:0] box_avg = {vsum_r[4:1], vsum_g[4:1], vsum_b[4:1]};

    // ── Linear write address: row >> 1 = output row ─────────────────────────
    // FRAME_W is a constant → synthesis implements the multiply as shift-add.
    wire [ADDR_W-1:0] lin_waddr = cam_row[9:1] * FRAME_W + cam_col;

    // ── Capture FSM ──────────────────────────────────────────────────────────
    always @(posedge pclk) begin
        href_d <= href;
        we     <= 1'b0;

        if (vsync) begin
            phase   <= 2'd0;
            cam_col <= 9'd0;
            cam_row <= 10'd0;
        end
        else if (href_d && !href) begin
            // Falling edge of HREF → end of camera line, advance row
            phase   <= 2'd0;
            cam_col <= 9'd0;
            if (cam_row < CAM_H - 1) cam_row <= cam_row + 10'd1;
        end
        else if (!href) begin
            phase <= 2'd0;
        end
        else begin
            case (phase)
                // ── phase 0: HIGH byte of camera pixel 0 ──────────────────────
                2'd0: begin
                    byte_hi <= data;
                    phase   <= 2'd1;
                end

                // ── phase 1: LOW byte of pixel 0 → latch RGB ──────────────────
                2'd1: begin
                    pixel0_reg <= curr_rgb;
                    phase      <= 2'd2;
                end

                // ── phase 2: HIGH byte of camera pixel 1 ──────────────────────
                2'd2: begin
                    byte_hi <= data;
                    phase   <= 2'd3;
                end

                // ── phase 3: LOW byte of pixel 1 → 2×2 box average write ─────
                2'd3: begin
                    if (cam_row[0] == 1'b0) begin
                        // First row of vertical pair → store h_avg in line buf
                        line_buf[cam_col] <= h_avg;
                    end else begin
                        // Second row of vertical pair → write box_avg to BRAM
                        wdata <= box_avg;
                        waddr <= lin_waddr;
                        we    <= 1'b1;
                    end
                    phase <= 2'd0;
                    if (cam_col < FRAME_W - 1)
                        cam_col <= cam_col + 9'd1;
                end
            endcase
        end
    end

endmodule
