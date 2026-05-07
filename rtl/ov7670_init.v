//==============================================================================
// ov7670_init.v   (REVISED)
//------------------------------------------------------------------------------
// Walks a ROM of SCCB writes to configure the OV7670 for:
//     * VGA output (640x480 native) - NO camera-side scaling
//     * RGB565 pixel format, full output range
//     * Default (normal) gamma / AWB / AGC
//
// Rationale for the rewrite
// -------------------------
// The previous ROM simultaneously set COM7[QVGA]=1 AND wrote the DCW/scaling
// registers (0x70-0x73, 0x3E). Those two paths fight each other on some
// OV7670 lots and produce a warped/corrupt pixel stream even though SCCB
// transactions succeed. The classroom-safe approach is to leave the camera
// in native VGA mode and do 2x2 downsampling inside the FPGA (done by
// ov7670_capture.v). That path avoids the scaling registers entirely.
//
// Register values below are the widely-used "OV7670 VGA + RGB565" set. If
// the image is still wrong after this change, the most common follow-up
// fix is MVFP (0x1E): change 0x07 to 0x37 if the image is upside-down.
//==============================================================================
`timescale 1ns / 1ps

module ov7670_init #(
    parameter INPUT_CLK_HZ = 25_000_000
)(
    input  wire       clk,
    input  wire       rst_n,
    output reg        done,
    output reg        sccb_start,
    output wire [7:0] slave_addr,
    output reg  [7:0] reg_addr,
    output reg  [7:0] reg_data,
    input  wire       sccb_ready
);

    assign slave_addr = 8'h42;          // OV7670 write address

    // Wait >= 1 full frame period (16.7 ms @ 60 fps) after reset before writing
    // subsequent registers. 20 ms is conservative and safe.
    localparam integer RESET_DELAY = INPUT_CLK_HZ / 50;

    // -----------------------------------------------------------------
    // Minimal, vetted register set for VGA + RGB565.
    // Sentinel 16'hFFFF marks end of ROM.
    // -----------------------------------------------------------------
    function [15:0] rom;
        input [6:0] idx;
        begin
            case (idx)
                // ---- software reset ----
                0  : rom = 16'h12_80;  // COM7: reset
                // ---- output format: RGB565 ----
                1  : rom = 16'h12_04;  // COM7: RGB output mode, VGA resolution
                2  : rom = 16'h11_00;  // CLKRC: use XCLK directly, no prescale
                3  : rom = 16'h0C_00;  // COM3: no scaling, no DCW
                4  : rom = 16'h3E_00;  // COM14: no scaling, normal pclk
                5  : rom = 16'h8C_00;  // RGB444: disabled (RGB565 selected by COM15)
                6  : rom = 16'h04_00;  // COM1: no CCIR656
                7  : rom = 16'h40_D0;  // COM15: full range [00,FF] + RGB565 format
                8  : rom = 16'h3A_04;  // TSLB: normal output byte order
                9  : rom = 16'h14_18;  // COM9: AGC ceiling 4x (was 16x — R was clipping)
                10 : rom = 16'h4F_80;  // MTX1  — RGB565 colour-correction matrix
                11 : rom = 16'h50_80;  // MTX2    (standard values from OV7670 app note;
                12 : rom = 16'h51_00;  // MTX3     these differ from the YUV BT.601 set
                13 : rom = 16'h52_22;  // MTX4     that was here before and caused the
                14 : rom = 16'h53_5E;  // MTX5     magenta/orange colour cast)
                15 : rom = 16'h54_80;  // MTX6
                16 : rom = 16'h58_1E;  // MTXS: matrix sign bits, auto-coeff OFF (bit7=0)
                17 : rom = 16'h3D_88;  // COM13: gamma ON, UV-saturation-auto OFF (RGB mode)
                18 : rom = 16'h17_13;  // HSTART
                19 : rom = 16'h18_01;  // HSTOP
                20 : rom = 16'h32_B6;  // HREF low bits
                21 : rom = 16'h19_02;  // VSTART
                22 : rom = 16'h1A_7A;  // VSTOP
                23 : rom = 16'h03_0A;  // VREF low bits
                24 : rom = 16'h0E_61;  // COM5
                25 : rom = 16'h0F_4B;  // COM6
                26 : rom = 16'h16_02;  // reserved (leave default)
                27 : rom = 16'h1E_27;  // MVFP: horizontal mirror ON (0x07 normal, 0x37 flip, 0x27 mirror, 0x17 both)
                28 : rom = 16'h21_02;  // ADCCTR1
                29 : rom = 16'h22_91;  // ADCCTR2
                30 : rom = 16'h29_07;  // reserved
                31 : rom = 16'h33_0B;  // CHLF
                32 : rom = 16'h35_0B;  // reserved
                33 : rom = 16'h37_1D;  // ADC
                34 : rom = 16'h38_71;  // ACOM
                35 : rom = 16'h39_2A;  // OFON
                36 : rom = 16'h3C_78;  // COM12: no HREF when VSYNC low
                37 : rom = 16'h4D_40;  // reserved
                38 : rom = 16'h4E_20;  // reserved
                39 : rom = 16'h69_00;  // GFIX
                40 : rom = 16'h6B_0A;  // DBLV: bypass PLL
                41 : rom = 16'h74_10;  // reserved
                42 : rom = 16'h8D_4F;  // reserved magic
                43 : rom = 16'h8E_00;
                44 : rom = 16'h8F_00;
                45 : rom = 16'h90_00;
                46 : rom = 16'h91_00;
                47 : rom = 16'h96_00;
                48 : rom = 16'h9A_80;
                49 : rom = 16'hB0_84;  // magic OmniVision value
                50 : rom = 16'hB1_0C;  // ABLC1
                51 : rom = 16'hB2_0E;
                52 : rom = 16'hB3_82;  // THL_ST
                53 : rom = 16'hB8_0A;
                // ---- AWB OFF: manual gains (more stable across scene content) ----
                54 : rom = 16'h13_E5;  // COM8: AGC+AEC on, AWB OFF (bit1=0)
                // ---- manual white-balance gains ----
                55 : rom = 16'h01_A0;  // BLUE gain  ~1.25x  (filter test: clean signal)
                56 : rom = 16'h02_80;  // RED  gain  ~1.0x   (filter test: was clipping at 1.44x)
                // ---- camera-side noise reduction ----
                57 : rom = 16'h3F_00;  // EDGE: edge enhancement OFF (was amplifying noise)
                58 : rom = 16'h4C_20;  // DNSTH: denoise threshold (stronger, was 0x10)
                59 : rom = 16'h77_0A;  // DENOISE: enable + stronger (was 0x05)
                60 : rom = 16'h41_38;  // COM16: AWB-gain enable + denoise enable bit
                // ---- contrast / brightness ----
                61 : rom = 16'h56_40;  // CONTRAS: 1.0x = default (was 0x50, amplified noise)
                62 : rom = 16'h55_00;  // BRIGHT: no brightness offset
                default: rom = 16'hFF_FF;
            endcase
        end
    endfunction

    // ------------------------------------------------------------------
    // Walker FSM (same as before)
    // ------------------------------------------------------------------
    localparam S_DELAY  = 2'd0,
               S_ISSUE  = 2'd1,
               S_WAIT   = 2'd2,
               S_FINISH = 2'd3;

    reg [1:0]  state;
    reg [6:0]  rom_idx;
    reg [19:0] delay_cnt;

    wire [15:0] cur = rom(rom_idx);

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_DELAY;
            rom_idx    <= 7'd0;
            delay_cnt  <= RESET_DELAY[19:0];
            sccb_start <= 1'b0;
            reg_addr   <= 8'h00;
            reg_data   <= 8'h00;
            done       <= 1'b0;
        end else begin
            sccb_start <= 1'b0;

            case (state)
                S_DELAY: begin
                    if (delay_cnt == 20'd0) state <= S_ISSUE;
                    else                    delay_cnt <= delay_cnt - 20'd1;
                end

                S_ISSUE: begin
                    if (cur == 16'hFFFF) begin
                        state <= S_FINISH;
                    end else if (sccb_ready) begin
                        reg_addr   <= cur[15:8];
                        reg_data   <= cur[ 7:0];
                        sccb_start <= 1'b1;
                        state      <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (sccb_ready && !sccb_start) begin
                        if (rom_idx == 7'd0) begin
                            // After the software-reset write, wait again.
                            delay_cnt <= RESET_DELAY[19:0];
                            state     <= S_DELAY;
                        end else begin
                            state <= S_ISSUE;
                        end
                        rom_idx <= rom_idx + 7'd1;
                    end
                end

                S_FINISH: done <= 1'b1;

                default: state <= S_DELAY;
            endcase
        end
    end

endmodule
