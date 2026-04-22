//==============================================================================
// tb_frame_buffer.v
//------------------------------------------------------------------------------
// Writes a small test pattern into the frame buffer on wclk, then reads it
// back on rclk and verifies that every location holds the expected value.
// Uses mismatched clock frequencies to shake out any unintended synchronous
// coupling in the RAM inference.
//==============================================================================
`timescale 1ns / 1ps

module tb_frame_buffer;

    reg wclk = 0; always #7  wclk = ~wclk;   // ~71 MHz
    reg rclk = 0; always #20 rclk = ~rclk;   // 25 MHz

    localparam DEPTH = 1024;                 // smaller depth for fast sim
    localparam AW    = 10;
    localparam DW    = 12;

    reg           we    = 0;
    reg  [AW-1:0] waddr = 0;
    reg  [DW-1:0] wdata = 0;
    reg  [AW-1:0] raddr = 0;
    wire [DW-1:0] rdata;

    frame_buffer #(.DATA_W(DW), .DEPTH(DEPTH), .ADDR_W(AW)) dut (
        .wclk(wclk), .we(we), .waddr(waddr), .wdata(wdata),
        .rclk(rclk), .raddr(raddr), .rdata(rdata)
    );

    integer i, errors;

    initial begin
        errors = 0;

        // Write phase: store addr ^ 0xA5C at every location.
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge wclk);
            waddr = i[AW-1:0];
            wdata = (i ^ 12'hA5C);
            we    = 1'b1;
        end
        @(negedge wclk) we = 1'b0;

        // Give the two clocks time to desync/resync before reads.
        #200;

        // Read phase
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge rclk) raddr = i[AW-1:0];
            @(posedge rclk);                 // 1-cycle BRAM latency
            @(negedge rclk);
            if (rdata !== ((i ^ 12'hA5C) & {DW{1'b1}})) begin
                $display("FAIL addr=%0d  got %h  exp %h",
                         i, rdata, ((i ^ 12'hA5C) & {DW{1'b1}}));
                errors = errors + 1;
                if (errors > 5) $finish;
            end
        end

        if (errors == 0) $display("--- frame_buffer testbench: ALL PASS (%0d locations) ---", DEPTH);
        else             $display("--- frame_buffer testbench: %0d ERRORS ---", errors);
        $finish;
    end

endmodule
