`timescale 1ns/1ps
class alu_driver;
    virtual alu_puf_if.DRIVER aluif;
    mailbox #(alu_transaction) gen2driv;
    mailbox #(alu_transaction) driv2sb;
    event driven;
    event sampled;

    function new(mailbox #(alu_transaction) gen2driv, driv2sb,
                 virtual alu_puf_if.DRIVER aluif, event driven, sampled);
        this.gen2driv = gen2driv;
        this.driv2sb  = driv2sb;
        this.aluif    = aluif;
        this.driven   = driven;
        this.sampled  = sampled;
    endfunction

    task reset();
       // $display("[DRIVER] Applying reset...");
        aluif.rst_n = 0;
        repeat(5) @(aluif.driver_cb);
        aluif.rst_n = 1;
        repeat(2) @(aluif.driver_cb);
        //$display("[DRIVER] Reset complete");
    endtask

    task wait_for_idle_phase();
        // input_sampled is internal to DUT - hierarchical reference
        if (testbench.dut.input_sampled === 1'b1) begin
            wait(testbench.dut.input_sampled === 1'b0);
        end
        @(aluif.driver_cb);
    endtask

    task main(input int count);
        alu_transaction d_trans;
        //$display("[DRIVER] Starting...");
        reset();

        repeat(count) begin
            d_trans = new();
            gen2driv.get(d_trans);
            wait_for_idle_phase();
            @(aluif.driver_cb);
            aluif.driver_cb.a          <= d_trans.a;
            aluif.driver_cb.b          <= d_trans.b;
            aluif.driver_cb.opcode     <= d_trans.opcode;
            aluif.driver_cb.puf_enable <= d_trans.puf_enable;
            driv2sb.put(d_trans);
            -> driven;

            @(sampled);
            //$display("[%0t] DRIVER: Monitor finished sampling", $time);

            @(aluif.driver_cb);
            aluif.driver_cb.puf_enable <= 0;

            if (d_trans.puf_enable) begin
                @(posedge aluif.clk);
                if (aluif.key_ready === 1'b1) begin
                    wait(aluif.key_ready === 1'b0);
                end
              //  $display("[%0t] DRIVER: key_ready cleared, DUT back in IDLE", $time);
                @(aluif.driver_cb);
            end

            //$display("[DRIVER] Driven: A=%04h B=%04h Op=%01h PUF=%b",
            //         d_trans.a, d_trans.b, d_trans.opcode, d_trans.puf_enable);
        end
       // $display("[DRIVER] Completed %0d transactions", count);
    endtask
endclass
