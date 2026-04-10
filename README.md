# PUF-ALU-encryption
This project explores dynamic ALU encryption scheme via opcodes and operands of an instruction acting as challenge bits for a PUF which generates the encryption key for the ALU result to that instruction. 

It contains the RTL file of an ALU integrated with an arbiter PUF where challenges are generated using simple concatenation. The process variability of the PUFs are modeled by Gaussian distribution in the testbench section. both directed and layered testbench is implemented.
