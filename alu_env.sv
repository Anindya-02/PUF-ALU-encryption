`timescale 1ns/1ps
`include "alu_transaction.sv"
`include "alu_generator.sv"
`include "alu_driver.sv"
`include "alu_monitor.sv"
`include "alu_scoreboard.sv"

class alu_env;
    mailbox #(alu_transaction) gen2driv;
    mailbox #(alu_transaction) driv2sb;
    mailbox #(alu_transaction) mon2sb;

    alu_generator  gen;
    alu_driver     drv;
    alu_monitor    mon;
    alu_scoreboard scb;

    event driven;
    event sampled;

    virtual alu_puf_if aluif;

    function new(virtual alu_puf_if aluif);
        this.aluif = aluif;

        gen2driv = new();
        driv2sb  = new();
        mon2sb   = new();

        gen = new(gen2driv);
        drv = new(gen2driv, driv2sb, aluif.DRIVER, driven, sampled);
        mon = new(mon2sb, aluif.MONITOR, driven, sampled);
        scb = new(driv2sb, mon2sb);
    endfunction

    task main(input int count);
        fork
            gen.main(count);
            drv.main(count);
            mon.main(count);
            scb.main(count);
        join
        $finish;
    endtask

endclass
