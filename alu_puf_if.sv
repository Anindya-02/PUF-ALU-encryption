`timescale 1ns/1ps

interface alu_puf_if(input logic clk);
    logic        rst_n;
    logic [15:0] a, b;
    logic [3:0]  opcode;
    logic        puf_enable;

    // DUT outputs - ciphertext and handshake only
    logic [31:0] encrypted_result;
    logic        key_ready;

    clocking driver_cb @(posedge clk);
        default input #1step output #1ns;
        output a, b, opcode, puf_enable;
        input  encrypted_result, key_ready;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step output #1ns;
        input a, b, opcode, puf_enable;
        input encrypted_result, key_ready;
    endclocking

    modport DRIVER (
        clocking driver_cb,
        input  clk,
        input  key_ready,
        output rst_n
    );

    modport MONITOR (
        clocking mon_cb,
        input clk, rst_n, key_ready,
        input encrypted_result
    );
endinterface
