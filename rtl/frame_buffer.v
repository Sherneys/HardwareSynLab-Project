//==============================================================================
// frame_buffer.v
//------------------------------------------------------------------------------
// True dual-port RAM with independent write and read clocks. Synthesises into
// BRAM on Xilinx parts (Vivado recognises this exact coding style).
//
// For 320x240 x 12 bits:
//   DEPTH = 76,800, WIDTH = 12 -> 921,600 bits, ~26 of the 50 BRAM tiles.
//
// For the 640x480 extra-credit mode we store 4-bit grayscale:
//   DEPTH = 307,200, WIDTH = 4  -> 1,228,800 bits, ~35 of the 50 BRAM tiles.
//
// The parameters let top_video_pipeline.v pick either configuration without
// editing this file.
//==============================================================================
`timescale 1ns / 1ps

module frame_buffer #(
    parameter DATA_W = 12,
    parameter DEPTH  = 76800,
    parameter ADDR_W = 17
)(
    // Write port (camera / pclk domain)
    input  wire              wclk,
    input  wire              we,
    input  wire [ADDR_W-1:0] waddr,
    input  wire [DATA_W-1:0] wdata,

    // Read port (VGA / 25 MHz domain)
    input  wire              rclk,
    input  wire [ADDR_W-1:0] raddr,
    output reg  [DATA_W-1:0] rdata
);

    // Inferring BRAM: write-first on one port, read-first on the other is
    // fine because the two ports run on different clocks and share no
    // collision semantics visible to users of this module.
    (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:DEPTH-1];

    // Write
    always @(posedge wclk) begin
        if (we) mem[waddr] <= wdata;
    end

    // Synchronous read (1 clock latency) -> BRAM inference
    always @(posedge rclk) begin
        rdata <= mem[raddr];
    end

    // Optional memory init (all black) for simulation. Xilinx BRAM powers up
    // to zero on real hardware so this is mainly for waveform sanity.
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = {DATA_W{1'b0}};
    end

endmodule
