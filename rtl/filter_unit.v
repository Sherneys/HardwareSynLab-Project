//==============================================================================
// filter_unit.v
//------------------------------------------------------------------------------
// Real-time pixel filter. Takes a 12-bit RGB444 pixel as input and produces a
// 12-bit RGB444 pixel as output, according to a 3-bit mode selector driven by
// board switches.
//
// Modes (chosen to satisfy the full-score requirement):
//   3'b000 : raw video passthrough
//   3'b001 : grayscale conversion
//   3'b010 : colour inversion (photographic negative)
//   3'b011 : red channel only   \
//   3'b100 : green channel only  } these three count as ONE filter
//   3'b101 : blue channel only   /  ("colour channel isolation")
//   3'b110 : bonus: threshold (black/white, cutoff at half)
//   3'b111 : bonus: R+B (magenta-only isolation variant)
//
// Purely combinational: one pixel in, one pixel out, no latency beyond the
// frame-buffer read.
//
// Grayscale note
// --------------
// True luma is Y = 0.299R + 0.587G + 0.114B. We approximate with
//   Y ~= (R + 2G + B) / 4
// which is exactly representable with only shifts and adds (no multiplier).
//==============================================================================
`timescale 1ns / 1ps

module filter_unit (
    input  wire [11:0] pixel_in,   // {R[3:0], G[3:0], B[3:0]}
    input  wire [2:0]  mode,
    input  wire        video_on,   // gate outputs during blanking
    output reg  [3:0]  r_out,
    output reg  [3:0]  g_out,
    output reg  [3:0]  b_out
);

    wire [3:0] r_in = pixel_in[11:8];
    wire [3:0] g_in = pixel_in[ 7:4];
    wire [3:0] b_in = pixel_in[ 3:0];

    // Weighted luminance: (R + 2G + B) / 4, result is 4 bits after the shift.
    // Extend to 6 bits to avoid overflow during the sum, then drop low 2 bits.
    wire [5:0] luma6 = {2'b00, r_in} + {1'b0, g_in, 1'b0} + {2'b00, b_in};
    wire [3:0] luma  = luma6[5:2];

    // Threshold at 0x8 (middle of 4-bit range).
    wire       bw    = (luma >= 4'd8);

    always @* begin
        if (!video_on) begin
            r_out = 4'h0;
            g_out = 4'h0;
            b_out = 4'h0;
        end else begin
            case (mode)
                3'b000: begin               // raw
                    r_out = r_in;
                    g_out = g_in;
                    b_out = b_in;
                end
                3'b001: begin               // grayscale
                    r_out = luma;
                    g_out = luma;
                    b_out = luma;
                end
                3'b010: begin               // invert
                    r_out = ~r_in;
                    g_out = ~g_in;
                    b_out = ~b_in;
                end
                3'b011: begin               // red only
                    r_out = r_in;
                    g_out = 4'h0;
                    b_out = 4'h0;
                end
                3'b100: begin               // green only
                    r_out = 4'h0;
                    g_out = g_in;
                    b_out = 4'h0;
                end
                3'b101: begin               // blue only
                    r_out = 4'h0;
                    g_out = 4'h0;
                    b_out = b_in;
                end
                3'b110: begin               // threshold (binary)
                    r_out = {4{bw}};
                    g_out = {4{bw}};
                    b_out = {4{bw}};
                end
                3'b111: begin               // magenta isolation
                    r_out = r_in;
                    g_out = 4'h0;
                    b_out = b_in;
                end
            endcase
        end
    end

endmodule
