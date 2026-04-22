//==============================================================================
// tb_filter_unit.v
//------------------------------------------------------------------------------
// Exercises all eight filter modes with known input pixels and checks that
// the output matches the expected transformation. Purely combinational so
// the testbench just walks through stimulus with #1 delays.
//==============================================================================
`timescale 1ns / 1ps

module tb_filter_unit;

    reg  [11:0] pixel_in;
    reg  [2:0]  mode;
    reg         video_on;
    wire [3:0]  r_out, g_out, b_out;

    filter_unit dut (
        .pixel_in (pixel_in),
        .mode     (mode),
        .video_on (video_on),
        .r_out    (r_out),
        .g_out    (g_out),
        .b_out    (b_out)
    );

    integer errors = 0;

    task check(input [3:0] er, input [3:0] eg, input [3:0] eb, input [127:0] tag);
        begin
            #1;
            if (r_out !== er || g_out !== eg || b_out !== eb) begin
                $display("FAIL %0s : in=%h mode=%b  got %h%h%h  exp %h%h%h",
                         tag, pixel_in, mode, r_out, g_out, b_out, er, eg, eb);
                errors = errors + 1;
            end else begin
                $display("PASS %0s : in=%h mode=%b  -> %h%h%h",
                         tag, pixel_in, mode, r_out, g_out, b_out);
            end
        end
    endtask

    initial begin
        video_on = 1'b1;

        // -------- blanking forces black --------
        pixel_in = 12'hF0A;  mode = 3'b000;  video_on = 1'b0;
        check(4'h0, 4'h0, 4'h0, "blank  ");
        video_on = 1'b1;

        // -------- raw passthrough --------
        pixel_in = 12'hA5C;  mode = 3'b000;
        check(4'hA, 4'h5, 4'hC, "raw    ");

        // -------- grayscale: Y = (R + 2G + B)/4 --------
        // pixel = 0xF00 -> R=15, G=0, B=0 -> Y = (15+0+0)/4 = 3
        pixel_in = 12'hF00;  mode = 3'b001;
        check(4'h3, 4'h3, 4'h3, "gray R ");

        // pixel = 0x0F0 -> R=0, G=15, B=0 -> Y = (0+30+0)/4 = 7
        pixel_in = 12'h0F0;  mode = 3'b001;
        check(4'h7, 4'h7, 4'h7, "gray G ");

        // pixel = 0xFFF -> Y = (15+30+15)/4 = 15
        pixel_in = 12'hFFF;  mode = 3'b001;
        check(4'hF, 4'hF, 4'hF, "gray W ");

        // -------- invert --------
        pixel_in = 12'hA5C;  mode = 3'b010;
        check(4'h5, 4'hA, 4'h3, "inv    ");

        // -------- red only --------
        pixel_in = 12'hA5C;  mode = 3'b011;
        check(4'hA, 4'h0, 4'h0, "red    ");

        // -------- green only --------
        pixel_in = 12'hA5C;  mode = 3'b100;
        check(4'h0, 4'h5, 4'h0, "green  ");

        // -------- blue only --------
        pixel_in = 12'hA5C;  mode = 3'b101;
        check(4'h0, 4'h0, 4'hC, "blue   ");

        // -------- threshold (bw) --------
        pixel_in = 12'hF00;  mode = 3'b110;  // Y=3 < 8 -> black
        check(4'h0, 4'h0, 4'h0, "th blk ");
        pixel_in = 12'hFFF;  mode = 3'b110;  // Y=15 >= 8 -> white
        check(4'hF, 4'hF, 4'hF, "th wht ");

        // -------- magenta (R+B) --------
        pixel_in = 12'hA5C;  mode = 3'b111;
        check(4'hA, 4'h0, 4'hC, "magent ");

        if (errors == 0) $display("--- filter_unit testbench: ALL PASS ---");
        else             $display("--- filter_unit testbench: %0d FAILURES ---", errors);

        $finish;
    end

endmodule
