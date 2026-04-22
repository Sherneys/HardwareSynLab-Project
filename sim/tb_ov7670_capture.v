//==============================================================================
// tb_ov7670_capture.v   (REVISED)
//------------------------------------------------------------------------------
// Tests the revised capture module that downsamples 2x2 (camera in native
// VGA mode -> FPGA keeps only even-row, even-col pixels).
//
// We simulate a tiny frame of CAM_W=8, CAM_H=4 → after 2x2 downsampling
// that becomes FRAME_W=4, FRAME_H=2 → 8 total pixels written.
//==============================================================================
`timescale 1ns / 1ps

module tb_ov7670_capture;

    reg pclk = 0;  always #20 pclk = ~pclk;  // 25 MHz

    reg        vsync = 0;
    reg        href  = 0;
    reg [7:0]  data  = 8'h00;
    wire       we;
    wire [16:0] waddr;
    wire [11:0] wdata;

    localparam CAM_W   = 8;
    localparam CAM_H   = 4;
    localparam FRAME_W = 4;
    localparam FRAME_H = 2;

    ov7670_capture #(
        .FRAME_W(FRAME_W), .FRAME_H(FRAME_H),
        .CAM_W  (CAM_W),   .CAM_H  (CAM_H),
        .ADDR_W (17)
    ) dut (
        .pclk (pclk),
        .vsync(vsync),
        .href (href),
        .data (data),
        .we   (we),
        .waddr(waddr),
        .wdata(wdata)
    );

    integer pixels_seen = 0;
    integer errors      = 0;

    // Compute expected RGB444 for a camera pixel at (cam_col, cam_row).
    // We inject pixel value = cam_row*CAM_W + cam_col, replicated into both bytes:
    //   byte_hi = byte_lo = idx[7:0]
    //   rgb565  = {byte_hi, byte_lo}
    //   R4 = byte_hi[7:4],  G4 = {byte_hi[2:0], byte_lo[7]},  B4 = byte_lo[4:1]
    function [11:0] expect_rgb444(input integer cam_col, input integer cam_row);
        reg [7:0] b;
        begin
            b = (cam_row*CAM_W + cam_col) & 8'hFF;
            expect_rgb444 = { b[7:4], b[2:0], b[7], b[4:1] };
        end
    endfunction

    integer cam_row, cam_col;
    integer expected_idx;

    // Monitor writes
    always @(posedge pclk) if (we) begin
        // The linear write order is: for even cam_row, for even cam_col.
        // With CAM_W=8 and CAM_H=4 we expect to see 8 writes:
        //   cam_row=0, cam_col = 0, 2, 4, 6  -> addr 0,1,2,3
        //   cam_row=2, cam_col = 0, 2, 4, 6  -> addr 4,5,6,7
        case (pixels_seen)
            0 : if (waddr !== 0 || wdata !== expect_rgb444(0, 0)) errors = errors + 1;
            1 : if (waddr !== 1 || wdata !== expect_rgb444(2, 0)) errors = errors + 1;
            2 : if (waddr !== 2 || wdata !== expect_rgb444(4, 0)) errors = errors + 1;
            3 : if (waddr !== 3 || wdata !== expect_rgb444(6, 0)) errors = errors + 1;
            4 : if (waddr !== 4 || wdata !== expect_rgb444(0, 2)) errors = errors + 1;
            5 : if (waddr !== 5 || wdata !== expect_rgb444(2, 2)) errors = errors + 1;
            6 : if (waddr !== 6 || wdata !== expect_rgb444(4, 2)) errors = errors + 1;
            7 : if (waddr !== 7 || wdata !== expect_rgb444(6, 2)) errors = errors + 1;
            default: errors = errors + 1;
        endcase
        pixels_seen = pixels_seen + 1;
    end

    reg [15:0] px;

    initial begin
        // VSYNC pulse to reset frame counters
        #200 vsync = 1'b1;
        repeat (4) @(posedge pclk);
        vsync = 1'b0;

        // Horizontal blanking before first line
        repeat (4) @(posedge pclk);

        // Drive CAM_H lines of CAM_W camera pixels
        for (cam_row = 0; cam_row < CAM_H; cam_row = cam_row + 1) begin
            href = 1'b1;
            for (cam_col = 0; cam_col < CAM_W; cam_col = cam_col + 1) begin
                px = (cam_row*CAM_W + cam_col) & 8'hFF;
                px = px | (px << 8);   // both bytes the same

                // byte HIGH on first pclk edge
                @(negedge pclk) data = px[15:8];
                @(posedge pclk);
                // byte LOW on second pclk edge
                @(negedge pclk) data = px[7:0];
                @(posedge pclk);
            end
            @(negedge pclk) href = 1'b0;
            repeat (4) @(posedge pclk);   // horizontal blanking
        end

        repeat (4) @(posedge pclk);

        $display("--- ov7670_capture testbench (revised) ---");
        $display("pixels written : %0d (expected %0d)",
                 pixels_seen, FRAME_W * FRAME_H);
        if (pixels_seen == FRAME_W * FRAME_H && errors == 0)
            $display("PASS");
        else
            $display("FAIL  pixels=%0d  errors=%0d", pixels_seen, errors);
        $finish;
    end

endmodule
