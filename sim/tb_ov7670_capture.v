//==============================================================================
// tb_ov7670_capture.v   (LINEAR + 2×2 BOX AVERAGING)
//------------------------------------------------------------------------------
// Tests the RGB565→RGB444 capture module with 2×2 box-average downsampling.
//
// Mini frame: CAM_W=8, CAM_H=4 → after 2×2 box-avg → FRAME_W=4, FRAME_H=2
//   Each output pixel = average of 4 camera pixels:
//     out(cc, cr) = avg( cam(2cc, 2cr),   cam(2cc+1, 2cr),
//                        cam(2cc, 2cr+1), cam(2cc+1, 2cr+1) )
//   Writes happen at the END of the second row of each vertical pair
//   (cam_row[0]==1), at linear address: out_row * FRAME_W + out_col.
//
// 8 writes total: 4 output cols × 2 output rows.
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

    // ── Per-pixel RGB444 extraction (matches DUT byte order) ─────────────────
    // Testbench drives both bytes = b, so high == low and the formula is
    // byte-order independent: {b[7:4], b[2:0], b[7], b[4:1]}.
    function [11:0] rgb_of_pixel(input integer pix_col, input integer pix_row);
        reg [7:0] b;
        begin
            b = (pix_row * CAM_W + pix_col) & 8'hFF;
            rgb_of_pixel = { b[7:4], b[2:0], b[7], b[4:1] };
        end
    endfunction

    // ── Expected 2×2 box average for output (cc, cr) ────────────────────────
    // Mimics the DUT's two-stage truncating arithmetic exactly:
    //   h_avg(top)    = (p(2cc,2cr)   + p(2cc+1,2cr))   / 2     ← stored in line buf
    //   h_avg(bottom) = (p(2cc,2cr+1) + p(2cc+1,2cr+1)) / 2     ← computed at write
    //   box          = (h_avg_top + h_avg_bottom) / 2
    function [11:0] expect_box(input integer cc, input integer cr);
        reg [11:0] p_tl, p_tr, p_bl, p_br;
        // 5-bit intermediates to mimic DUT's {1'b0, x} + {1'b0, y} arithmetic
        reg [4:0]  ht_r, ht_g, ht_b, hb_r, hb_g, hb_b;
        reg [3:0]  bx_r, bx_g, bx_b;
        begin
            p_tl = rgb_of_pixel(2*cc,   2*cr);
            p_tr = rgb_of_pixel(2*cc+1, 2*cr);
            p_bl = rgb_of_pixel(2*cc,   2*cr+1);
            p_br = rgb_of_pixel(2*cc+1, 2*cr+1);
            // top-row horizontal average (stored in line buffer)
            ht_r = ({1'b0, p_tl[11:8]} + {1'b0, p_tr[11:8]}) >> 1;
            ht_g = ({1'b0, p_tl[ 7:4]} + {1'b0, p_tr[ 7:4]}) >> 1;
            ht_b = ({1'b0, p_tl[ 3:0]} + {1'b0, p_tr[ 3:0]}) >> 1;
            // bottom-row horizontal average (computed in phase 3 of odd row)
            hb_r = ({1'b0, p_bl[11:8]} + {1'b0, p_br[11:8]}) >> 1;
            hb_g = ({1'b0, p_bl[ 7:4]} + {1'b0, p_br[ 7:4]}) >> 1;
            hb_b = ({1'b0, p_bl[ 3:0]} + {1'b0, p_br[ 3:0]}) >> 1;
            // box average = vertical avg of the two horizontal averages
            // Use only the low 4 bits of ht_*/hb_* (DUT discards bit 4 by
            // taking [4:1] of the 5-bit sum, which is identical to /2 of a
            // 4-bit value when the sum's MSB is the carry).
            bx_r = ({1'b0, ht_r[3:0]} + {1'b0, hb_r[3:0]}) >> 1;
            bx_g = ({1'b0, ht_g[3:0]} + {1'b0, hb_g[3:0]}) >> 1;
            bx_b = ({1'b0, ht_b[3:0]} + {1'b0, hb_b[3:0]}) >> 1;
            expect_box = {bx_r, bx_g, bx_b};
        end
    endfunction

    // ── Expected write sequence (linear, box-averaged) ──────────────────────
    // 8 writes: out row 0 then out row 1, cols 0..3.
    localparam EXPECTED_WRITES = 8;

    reg [16:0] exp_addr [0:7];
    reg [11:0] exp_data [0:7];
    initial begin
        // out row 0 (cam_rows 0,1) writes happen at end of cam_row 1
        exp_addr[0] = 17'd0; exp_data[0] = expect_box(0, 0);
        exp_addr[1] = 17'd1; exp_data[1] = expect_box(1, 0);
        exp_addr[2] = 17'd2; exp_data[2] = expect_box(2, 0);
        exp_addr[3] = 17'd3; exp_data[3] = expect_box(3, 0);
        // out row 1 (cam_rows 2,3) writes happen at end of cam_row 3
        exp_addr[4] = 17'd4; exp_data[4] = expect_box(0, 1);
        exp_addr[5] = 17'd5; exp_data[5] = expect_box(1, 1);
        exp_addr[6] = 17'd6; exp_data[6] = expect_box(2, 1);
        exp_addr[7] = 17'd7; exp_data[7] = expect_box(3, 1);
    end

    integer pixels_seen = 0;
    integer errors      = 0;

    always @(posedge pclk) if (we) begin
        if (pixels_seen >= EXPECTED_WRITES) begin
            $display("FAIL: unexpected extra write #%0d  addr=%0d data=0x%03x",
                     pixels_seen, waddr, wdata);
            errors = errors + 1;
        end else begin
            if (waddr !== exp_addr[pixels_seen]) begin
                $display("FAIL write[%0d]: waddr=%0d (expected %0d)",
                         pixels_seen, waddr, exp_addr[pixels_seen]);
                errors = errors + 1;
            end
            if (wdata !== exp_data[pixels_seen]) begin
                $display("FAIL write[%0d]: wdata=0x%03x (expected 0x%03x)",
                         pixels_seen, wdata, exp_data[pixels_seen]);
                errors = errors + 1;
            end
        end
        pixels_seen = pixels_seen + 1;
    end

    reg [15:0] px;
    integer cam_row_i, cam_col_i;

    initial begin
        // VSYNC pulse
        #200 vsync = 1'b1;
        repeat (4) @(posedge pclk);
        vsync = 1'b0;
        repeat (4) @(posedge pclk);   // blanking

        for (cam_row_i = 0; cam_row_i < CAM_H; cam_row_i = cam_row_i + 1) begin
            href = 1'b1;
            for (cam_col_i = 0; cam_col_i < CAM_W; cam_col_i = cam_col_i + 1) begin
                px = (cam_row_i * CAM_W + cam_col_i) & 8'hFF;
                px = px | (px << 8);   // both bytes identical → byte-order-independent
                @(negedge pclk) data = px[15:8];   // byte 0 (HIGH byte)
                @(posedge pclk);
                @(negedge pclk) data = px[7:0];    // byte 1 (LOW byte)
                @(posedge pclk);
            end
            @(negedge pclk) href = 1'b0;
            repeat (4) @(posedge pclk);
        end

        repeat (4) @(posedge pclk);

        $display("--- ov7670_capture testbench (2x2 box averaging) ---");
        $display("writes seen : %0d (expected %0d)", pixels_seen, EXPECTED_WRITES);
        if (pixels_seen == EXPECTED_WRITES && errors == 0)
            $display("PASS");
        else
            $display("FAIL  writes=%0d  errors=%0d", pixels_seen, errors);
        $finish;
    end

endmodule
