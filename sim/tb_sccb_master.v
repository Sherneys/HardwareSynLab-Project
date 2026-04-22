//==============================================================================
// tb_sccb_master.v
//------------------------------------------------------------------------------
// Testbench for sccb_master. Captures SIOD bit-by-bit on the rising edge of
// SIOC and checks that we see exactly the 3-phase write we drove in:
//    slave_addr (8) + dc + reg_addr (8) + dc + reg_data (8) + dc
// plus a correct START and STOP condition around it.
//
// We use a small SCCB frequency (by passing a big divider) just to keep
// simulation short.
//==============================================================================
`timescale 1ns / 1ps

module tb_sccb_master;

    reg clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    reg        rst_n       = 0;
    reg        start       = 0;
    reg [7:0]  slave_addr  = 8'h42;
    reg [7:0]  reg_addr    = 8'h12;
    reg [7:0]  reg_data    = 8'h80;
    wire       ready;
    wire       sioc, siod;

    // Model external pull-ups on the bus.
    pullup(sioc);
    pullup(siod);

    sccb_master #(
        .INPUT_CLK_HZ(100_000_000),
        .SCCB_CLK_HZ (1_000_000)     // 1 MHz for faster sim
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .slave_addr (slave_addr),
        .reg_addr   (reg_addr),
        .reg_data   (reg_data),
        .ready      (ready),
        .sioc       (sioc),
        .siod       (siod)
    );

    // Capture: sample SIOD at the middle of the SCL high period.
    reg [31:0] captured = 32'h0;
    integer    bit_cnt  = 0;
    reg        sioc_prev = 1'b1;

    // START/STOP detection: SDA transitions while SCL is high.
    reg start_seen = 1'b0;
    reg stop_seen  = 1'b0;
    reg siod_prev  = 1'b1;

    always @(posedge clk) begin
        // detect SCL rising edge, but only count the first 27 (the data bits).
        // The STOP condition produces an additional SCL rising edge that is
        // NOT a data bit - we ignore it here.
        if (!sioc_prev && sioc && bit_cnt < 27) begin
            captured <= {captured[30:0], siod};
            bit_cnt  <= bit_cnt + 1;
        end
        // START: SDA falls while SCL high
        if (sioc && siod_prev && !siod) start_seen <= 1'b1;
        // STOP: SDA rises while SCL high
        if (sioc && !siod_prev && siod) stop_seen  <= 1'b1;

        sioc_prev <= sioc;
        siod_prev <= siod;
    end

    initial begin
        #100 rst_n = 1;
        #200 @(posedge clk) start <= 1'b1;
             @(posedge clk) start <= 1'b0;

        // Wait until master goes idle again (transaction complete).
        wait (ready == 1'b0);
        wait (ready == 1'b1);
        #10_000;  // let STOP finish

        $display("--- SCCB master testbench ---");
        $display("start condition seen : %b", start_seen);
        $display("stop  condition seen : %b", stop_seen);
        $display("bits captured on SCL rising : %0d (expected 27)", bit_cnt);

        // The low 27 bits of captured should equal
        //   {slave_addr, 1'b1, reg_addr, 1'b1, reg_data, 1'b1}
        // = 0x42, 1, 0x12, 1, 0x80, 1
        // = 0100_0010 1 0001_0010 1 1000_0000 1
        // = 27'b010000101_000100101_100000001
        if (start_seen && stop_seen && bit_cnt == 27 &&
            captured[26:0] == 27'b010000101_000100101_100000001)
            $display("PASS  captured = 27'b%b", captured[26:0]);
        else
            $display("FAIL  captured = 27'b%b", captured[26:0]);

        $finish;
    end

endmodule
