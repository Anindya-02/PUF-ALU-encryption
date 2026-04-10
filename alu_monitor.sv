`timescale 1ns/1ps
class alu_monitor;
    virtual alu_puf_if.MONITOR aluif;
    mailbox #(alu_transaction) mon2sb;
    event driven;
    event sampled;

    function new(mailbox #(alu_transaction) mon2sb,
                 virtual alu_puf_if.MONITOR aluif, event driven, sampled);
        this.mon2sb  = mon2sb;
        this.aluif   = aluif;
        this.driven  = driven;
        this.sampled = sampled;
    endfunction

    task main(input int count);
        alu_transaction m_trans;
        bit is_puf_operation;
       // $display("[MONITOR] Starting...");

        repeat(count) begin
            m_trans = new();
            @(driven);
           // $display("[%0t] MONITOR: Driver triggered event", $time);
            @(aluif.mon_cb);
            is_puf_operation = aluif.mon_cb.puf_enable;

            if (is_puf_operation) begin
               // $display("[%0t] MONITOR: PUF operation - waiting for key_ready...", $time);
                if (aluif.key_ready === 1'b1) begin
                    wait(aluif.key_ready === 1'b0);
                   // $display("[%0t] MONITOR: key_ready deasserted", $time);
                end
                wait(aluif.key_ready === 1'b1);
              //  $display("[%0t] MONITOR: key_ready asserted!", $time);

                // Only ciphertext is observable from the interface
                m_trans.encrypted_result = aluif.encrypted_result;

            end else begin
                $display("[%0t] MONITOR: ALU-only - waiting for result_valid...", $time);
                // result_valid is internal; access via hierarchical reference
                wait(testbench.dut.result_valid === 1'b1);
                @(aluif.mon_cb);
                m_trans.encrypted_result = aluif.mon_cb.encrypted_result;
            end

            mon2sb.put(m_trans);
            -> sampled;
           // $display("[MONITOR] Sampled: Enc=%08h", m_trans.encrypted_result);
        end
        //$display("[MONITOR] Completed %0d transactions", count);
    endtask
endclass
