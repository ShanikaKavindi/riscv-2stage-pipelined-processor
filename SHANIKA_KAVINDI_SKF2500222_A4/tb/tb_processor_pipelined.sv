`timescale 1ns/1ps


module processor_tb_pipelined;
  parameter int WIDTH = 32;
  parameter string MEM_FILE = "program_pipelined.hex";
  parameter int CLK_PERIOD = 10;          // ns (pipelined clock)
  parameter int TIMEOUT_CYCLES = 10000;

  // This program's last instruction is "jal x0, 0" at PC = 0x40 (decimal 64).
  parameter int END_PC = 64;

  reg  clock = 0;
  reg  reset = 1;
  reg  memEn = 0;
  reg  [WIDTH-1:0] memData = 0;
  reg  [WIDTH-1:0] memAddr = 0;
  wire [WIDTH-1:0] gp, a7, a0;

  // DUT: 2-stage pipelined, NO forwarding (software hazard avoidance)
  processor #(.WIDTH(WIDTH), .FORWARDING(0)) dut (
    .clock(clock),
    .reset(reset),
    .memEn(memEn),
    .memData(memData),
    .memAddr(memAddr),
    .gp(gp),
    .a7(a7),
    .a0(a0)
  );

  integer i;
  integer cycle_count = 0;

  // Clock
  always #(CLK_PERIOD/2) clock = ~clock;

  initial begin
    #1;
    $display("[%0t] Loading memory from %s ...", $time, MEM_FILE);
    $readmemh(MEM_FILE, dut.mainMemory);

    // Clear registers
    for (i = 0; i < 32; i = i + 1)
      dut.registers[i] = 32'b0;

    // Reset for two rising edges
    reset = 1;
    repeat (2) @(posedge clock);
    reset = 0;
    $display("[%0t] Released reset, pipelined processor running.", $time);
  end

  // Completion / timeout monitor
  always @(posedge clock) begin
    if (!reset) begin
      cycle_count = cycle_count + 1;

      // Stop when we have reached the infinite loop AND the final result is visible.
      if ((dut.pc == END_PC) && (a0 == 32'd144)) begin
        $display("[%0t] DONE: PC=0x%0h, a0=144 (F12). Cycles=%0d", $time, dut.pc, cycle_count);
        $finish;
      end

      if (cycle_count > TIMEOUT_CYCLES) begin
        $display("[%0t] TIMEOUT after %0d cycles. PC=0x%0h a0=%0d gp=%0d", $time, cycle_count, dut.pc, a0, gp);
        $finish;
      end
    end
  end
endmodule
