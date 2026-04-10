`timescale 1ns/1ps
class alu_generator;
    mailbox #(alu_transaction) gen2driv;

    function new(mailbox #(alu_transaction) gen2driv);
        this.gen2driv = gen2driv;
    endfunction

    task main(input int count);
        alu_transaction g_trans;
       $display("[GENERATOR] Generating %0d transactions...", count);
        repeat(count) begin
            g_trans = new();
            if (!g_trans.randomize()) begin
                //$display("[ERROR] Randomization failed!");
                $finish;
            end
            gen2driv.put(g_trans);
        end
       // $display("[GENERATOR] Generated %0d transactions", count);
    endtask

endclass
