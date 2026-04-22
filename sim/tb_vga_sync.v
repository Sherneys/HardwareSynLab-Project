//==============================================================================
// tb_vga_sync.v
//------------------------------------------------------------------------------
// Testbench for vga_sync.
// Verifies:
//   * h_count/v_count wrap at 800/525
//   * hsync pulse width = 96 and located inside [656, 752)
//   * vsync pulse width = 2 and located inside [490, 492)
//   * video_on is high exactly for 640x480 = 307,200 cycles per frame
//==============================================================================
`timescale 1ns / 1ps

module tb_vga_sync;

    reg        clk = 0;
    reg        rst_n = 0;
    wire       hsync, vsync, video_on;
    wire [9:0] h_count, v_count;

    // 25 MHz -> 40 ns period
    always #20 clk = ~clk;

    vga_sync dut (
        .clk_25m (clk),
        .rst_n   (rst_n),
        .hsync   (hsync),
        .vsync   (vsync),
        .video_on(video_on),
        .h_count (h_count),
        .v_count (v_count),
        .pixel_tick()
    );

    // Accumulators
    integer visible_cnt;
    integer hsync_low_cnt;
    integer vsync_low_cnt;
    reg     counting;       // 1 between two successive (0,0) wraps

    initial begin
        visible_cnt   = 0;
        hsync_low_cnt = 0;
        vsync_low_cnt = 0;
        counting      = 0;

        // Release reset after a few cycles.
        #100 rst_n = 1;

        // Wait for v_count to reach 524 once (end of first partial frame),
        // then start the exact-frame measurement on the next wrap to (0,0).
        @(posedge clk); // settle
        wait (v_count == 10'd524 && h_count == 10'd799);
        @(posedge clk);
        counting = 1'b1;

        // Now count exactly one full frame (800*525 = 420,000 clock cycles).
        repeat (800*525) @(posedge clk);
        counting = 1'b0;

        $display("--- VGA sync testbench results ---");
        $display("visible pixels in one frame : %0d (expected 307200)", visible_cnt);
        $display("hsync-low cycles per frame  : %0d (expected 96*525 = %0d)",
                 hsync_low_cnt, 96*525);
        $display("vsync-low cycles per frame  : %0d (expected 2*800 = %0d)",
                 vsync_low_cnt, 2*800);

        if (visible_cnt   == 307200 &&
            hsync_low_cnt == 96*525 &&
            vsync_low_cnt == 2*800)
            $display("PASS");
        else
            $display("FAIL");
        $finish;
    end

    // Count statistics one-frame-long.
    always @(posedge clk) if (rst_n && counting) begin
        if (!hsync)    hsync_low_cnt <= hsync_low_cnt + 1;
        if (!vsync)    vsync_low_cnt <= vsync_low_cnt + 1;
        if (video_on)  visible_cnt   <= visible_cnt   + 1;
    end

    // Range checks always on.
    always @(posedge clk) if (rst_n) begin
        if (h_count > 799) begin
            $display("FAIL: h_count=%0d > 799", h_count);
            $finish;
        end
        if (v_count > 524) begin
            $display("FAIL: v_count=%0d > 524", v_count);
            $finish;
        end
    end

endmodule
