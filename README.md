# riscv-2stage-pipelined-processor
2-stage pipelined RISC-V processor in SystemVerilog with hazard handling, forwarding, and performance comparison against a single-cycle CPU.


This project implements a **2-stage pipelined RISC-V processor** using SystemVerilog. It includes both a **single-cycle CPU** and a **pipelined processor**, allowing performance comparison and analysis.

The processor executes a Fibonacci program (n = 12) and verifies correct functionality through simulation.


Architecture
- **Stage 1:** Instruction Fetch (IF), Instruction Decode (ID), Execute (EXE)  
- **Stage 2:** Memory Access (MEM), Write Back (WB)  

The design demonstrates how pipelining improves performance by overlapping instruction execution.

Features
- 2-stage pipelined CPU design  
- Single-cycle reference processor  
- Hazard handling using:
  - Instruction scheduling  
  - Optional data forwarding  
- Execution of Fibonacci program  
- Simulation and waveform verification  

Pipeline Hazards
- **Data Hazards:** Managed using NOPs (software scheduling) or forwarding  
- **Control Hazards:** Reduced by early branch resolution  
- **Structural Hazards:** Considered in unified memory model  

Simulation
The design is verified using SystemVerilog testbenches.

Performance Comparison

| Implementation | Clock Period | Cycles | Total Time |
|---------------|-------------|--------|------------|
| Single-cycle  | 20 ns       | 77     | 1540 ns    |
| Pipeline (no forwarding) | 10 ns | 78 | 780 ns |
| Pipeline (with forwarding) | 10 ns | 77 | 770 ns |

Achieves approximately **2× speedup** compared to single-cycle processor.

 Project Structure
src/ → Processor design files
tb/ → Testbenches
programs/ → Program files (Fibonacci)
convert.py → Instruction format converter


How to Run (Vivado)

1. Add `src/*.sv` as Design Sources  
2. Add a testbench from `tb/` as Simulation Source  
3. Add corresponding `.hex` file from `programs/`  
4. Run simulation  
5. Observe waveform and register outputs  

Tools & Technologies
- SystemVerilog  
- Vivado Simulator  
- Digital Design / Computer Architecture  

Future Improvements
- Multi-stage pipelining (5-stage pipeline)  
- Cache memory integration  
- Branch prediction techniques  
- Performance optimization  

Author
**Shanika Kavindi**  
GitHub: https://github.com/ShanikaKavindi  

License
This project is for educational purposes.

