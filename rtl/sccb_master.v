//==============================================================================
// sccb_master.v
//------------------------------------------------------------------------------
// SCCB (Serial Camera Control Bus) master. SCCB is an OmniVision-branded
// variant of I2C; for the OV7670 the differences that matter are:
//   * No ACK bit is required on writes (transmitter drives a "don't care"
//     9th cycle, receiver ignores it). We still generate the cycle.
//   * Clock rate: <= 400 kHz (we run at ~100 kHz which is very conservative).
//
// This module performs ONE 3-phase write at a time:
//     START | slave_addr(7) + W(1) | ign | reg_addr(8) | ign | reg_data(8) | ign | STOP
// The OV7670 slave write address is 0x42 (8-bit form).
//
// Handshake:
//   start   : pulse high for one clk cycle to begin a transaction
//   ready   : high when idle / between transactions
// While 'ready' is low the master is busy.
//==============================================================================
`timescale 1ns / 1ps

module sccb_master #(
    parameter INPUT_CLK_HZ = 25_000_000,  // clk frequency
    parameter SCCB_CLK_HZ  = 100_000      // target SIOC frequency
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,        // begin a new 3-phase write
    input  wire [7:0]  slave_addr,   // 0x42 for OV7670 writes
    input  wire [7:0]  reg_addr,
    input  wire [7:0]  reg_data,
    output reg         ready,        // high when idle
    // SCCB pins (tri-stated via open-drain style: we only pull LOW)
    inout  wire        sioc,         // SCL equivalent
    inout  wire        siod          // SDA equivalent
);

    // Quarter-bit tick: the SCCB waveform is easiest to express as a 4-phase
    // state machine per bit, so we generate 4x the bit clock.
    localparam integer QUARTER_TICKS = INPUT_CLK_HZ / (SCCB_CLK_HZ * 4);

    reg [15:0] tick_cnt;
    reg        q_tick;   // one-cycle strobe every quarter bit

    always @(posedge clk) begin
        if (!rst_n) begin
            tick_cnt <= 16'd0;
            q_tick   <= 1'b0;
        end else if (tick_cnt == QUARTER_TICKS - 1) begin
            tick_cnt <= 16'd0;
            q_tick   <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 16'd1;
            q_tick   <= 1'b0;
        end
    end

    // Open-drain drivers: drive LOW or release (Z).
    reg sioc_oe;   // 1 => drive 0, 0 => release
    reg siod_oe;
    assign sioc = sioc_oe ? 1'b0 : 1'bz;
    assign siod = siod_oe ? 1'b0 : 1'bz;

    // State machine: 30 bit-phases total (START, 3*9 bits, STOP).
    // Each phase has 4 quarter-ticks; the SDA setup/hold requirements of
    // SCCB are comfortably met by changing SDA on q=0 and sampling SCL
    // high between q=1 and q=2.
    localparam S_IDLE  = 3'd0,
               S_START = 3'd1,
               S_PHASE = 3'd2,   // streaming bits
               S_STOP  = 3'd3,
               S_DONE  = 3'd4;

    reg [2:0]  state;
    reg [5:0]  bit_idx;     // 0..26 (27 bits total: 3 bytes incl. dont-care)
    reg [1:0]  q_phase;     // 0..3 inside one bit

    // Serialize the three bytes into a 27-bit stream. The 9th, 18th, 27th bit
    // positions are the "don't care" slots (would be ACK in real I2C).
    wire [26:0] tx_stream = { slave_addr, 1'b1,   // byte 1 + dc
                              reg_addr,   1'b1,   // byte 2 + dc
                              reg_data,   1'b1 }; // byte 3 + dc

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            bit_idx  <= 6'd0;
            q_phase  <= 2'd0;
            sioc_oe  <= 1'b0;
            siod_oe  <= 1'b0;
            ready    <= 1'b1;
        end else begin
            case (state)
                S_IDLE: begin
                    sioc_oe <= 1'b0;      // bus idle = both lines high
                    siod_oe <= 1'b0;
                    ready   <= 1'b1;
                    if (start) begin
                        ready   <= 1'b0;
                        state   <= S_START;
                        q_phase <= 2'd0;
                    end
                end

                // START condition: SDA falls while SCL is high.
                S_START: if (q_tick) begin
                    case (q_phase)
                        2'd0: begin sioc_oe <= 1'b0; siod_oe <= 1'b0; end // both high
                        2'd1: begin sioc_oe <= 1'b0; siod_oe <= 1'b1; end // SDA ↓
                        2'd2: begin sioc_oe <= 1'b1; siod_oe <= 1'b1; end // SCL ↓
                        2'd3: begin
                            sioc_oe <= 1'b1;
                            // drive first data bit
                            siod_oe <= ~tx_stream[26];
                            bit_idx <= 6'd0;
                            state   <= S_PHASE;
                        end
                    endcase
                    q_phase <= q_phase + 2'd1;
                end

                // Bit streaming: SDA changes while SCL is low, then SCL pulses high.
                S_PHASE: if (q_tick) begin
                    case (q_phase)
                        2'd0: begin
                            // SCL low, present next bit on SDA
                            sioc_oe <= 1'b1;
                            siod_oe <= ~tx_stream[26 - bit_idx];
                        end
                        2'd1: begin
                            sioc_oe <= 1'b0;  // SCL rising
                            siod_oe <= ~tx_stream[26 - bit_idx];
                        end
                        2'd2: begin
                            sioc_oe <= 1'b0;  // SCL still high, SDA stable
                            siod_oe <= ~tx_stream[26 - bit_idx];
                        end
                        2'd3: begin
                            sioc_oe <= 1'b1;  // SCL going low again
                            siod_oe <= ~tx_stream[26 - bit_idx];
                            if (bit_idx == 6'd26) begin
                                state   <= S_STOP;
                                q_phase <= 2'd0;
                            end else begin
                                bit_idx <= bit_idx + 6'd1;
                            end
                        end
                    endcase
                    if (!(q_phase == 2'd3 && bit_idx == 6'd26))
                        q_phase <= q_phase + 2'd1;
                end

                // STOP condition: SDA rises while SCL is high.
                S_STOP: if (q_tick) begin
                    case (q_phase)
                        2'd0: begin sioc_oe <= 1'b1; siod_oe <= 1'b1; end // SCL low, SDA low
                        2'd1: begin sioc_oe <= 1'b0; siod_oe <= 1'b1; end // SCL ↑
                        2'd2: begin sioc_oe <= 1'b0; siod_oe <= 1'b0; end // SDA ↑
                        2'd3: begin
                            sioc_oe <= 1'b0;
                            siod_oe <= 1'b0;
                            state   <= S_DONE;
                        end
                    endcase
                    q_phase <= q_phase + 2'd1;
                end

                S_DONE: begin
                    ready <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
