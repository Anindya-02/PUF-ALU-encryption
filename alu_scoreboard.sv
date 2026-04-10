`timescale 1ns/1ps

class alu_scoreboard;
    mailbox #(alu_transaction) driv2sb;
    mailbox #(alu_transaction) mon2sb;

    // PUF delay model - 4 paths × 8 stages
    real delay_p0_straight[0:3][0:7];
    real delay_p0_cross[0:3][0:7];
    real delay_p1_straight[0:3][0:7];
    real delay_p1_cross[0:3][0:7];

    int pass_count;
    int fail_count;

    function new(mailbox #(alu_transaction) driv2sb, mon2sb);
        this.driv2sb  = driv2sb;
        this.mon2sb   = mon2sb;
        pass_count    = 0;
        fail_count    = 0;

        // Mirror TB delay model for independent key reconstruction
        for (int path = 0; path < 4; path++) begin
            for (int stage = 0; stage < 8; stage++) begin
                delay_p0_straight[path][stage] = testbench.delay_p0_straight[path][stage];
                delay_p0_cross[path][stage]    = testbench.delay_p0_cross[path][stage];
                delay_p1_straight[path][stage] = testbench.delay_p1_straight[path][stage];
                delay_p1_cross[path][stage]    = testbench.delay_p1_cross[path][stage];
            end
        end
        $display("[SCOREBOARD] Initialized with 4-path PUF delay model");
    endfunction

    // -------------------------------------------------------
    // Expected ALU result (plaintext) - computed internally,
    // never read from DUT outputs
    // -------------------------------------------------------
    function bit [31:0] calc_alu(input bit [15:0] a, b, input bit [3:0] s);
        case (s)
            4'b0000: return a + b;
            4'b0001: return a - b;
            4'b0010: return a * b;
            4'b0011: return (b != 0) ? (a / b)  : 32'hFFFFFFFF;
            4'b0100: return (b != 0) ? (a % b)  : 32'hFFFFFFFF;
            4'b0101: return {31'b0, (a != 0) && (b != 0)};
            4'b0110: return {31'b0, (a != 0) || (b != 0)};
            4'b0111: return {31'b0, (a == 0)};
            4'b1000: return {16'b0, ~a};
            4'b1001: return {16'b0, a & b};
            4'b1010: return {16'b0, a | b};
            4'b1011: return {16'b0, a ^ b};
            4'b1100: return a << 1;
            4'b1101: return a >> 1;
            4'b1110: return a + 1;
            4'b1111: return a - 1;
        endcase
    endfunction

    // -------------------------------------------------------
    // Expected PUF key - reconstructed from delay model,
    // never read from DUT outputs
    // -------------------------------------------------------
    function bit calc_puf_bit(input bit [7:0] challenge, input int path_idx);
        real d0, d1;
        d0 = 0.0; d1 = 0.0;
        for (int i = 0; i < 8; i++) begin
            d0 += challenge[i] ? delay_p0_cross[path_idx][i] : delay_p0_straight[path_idx][i];
            d1 += challenge[i] ? delay_p1_cross[path_idx][i] : delay_p1_straight[path_idx][i];
        end
        return (d0 < d1) ? 1'b1 : 1'b0;
    endfunction

    function bit [31:0] calc_puf_key(input bit [31:0] base_challenge);
        bit [31:0] puf_key, rotated;
        bit [7:0]  slice[0:3];
        for (int rot = 0; rot < 8; rot++) begin
            rotated   = (base_challenge << (rot*4)) | (base_challenge >> (32 - rot*4));
            slice[0]  = rotated[7:0];
            slice[1]  = rotated[15:8];
            slice[2]  = rotated[23:16];
            slice[3]  = rotated[31:24];
            puf_key[rot*4+0] = calc_puf_bit(slice[0], 0);
            puf_key[rot*4+1] = calc_puf_bit(slice[1], 1);
            puf_key[rot*4+2] = calc_puf_bit(slice[2], 2);
            puf_key[rot*4+3] = calc_puf_bit(slice[3], 3);
        end
        return puf_key;
    endfunction


    function bit [31:0] calc_encrypted(
        input bit [15:0] a, b,
        input bit [3:0]  opcode,
        input bit        puf_enable
    );
        bit [31:0] alu_res, puf_key, base_challenge;
        alu_res        = calc_alu(a, b, opcode);
        base_challenge = {opcode, a, b[11:0]};
        if (puf_enable) begin
            puf_key = calc_puf_key(base_challenge);
            return alu_res ^ puf_key;
        end else begin
            return alu_res;   // no encryption
        end
    endfunction

    task main(input int count);
        alu_transaction d_trans, m_trans;
        bit [31:0] expected_enc;
        bit enc_pass;

        $display("========================================");
        $display("  SCOREBOARD TEST STARTS");
        $display("========================================");

        repeat(count) begin
            d_trans = new();
            driv2sb.get(d_trans);

            m_trans = new();
            mon2sb.get(m_trans);

            // Compute expected ciphertext entirely within scoreboard
            expected_enc = calc_encrypted(d_trans.a, d_trans.b,
                                          d_trans.opcode, d_trans.puf_enable);

            enc_pass = (m_trans.encrypted_result === expected_enc);

            if (enc_pass) begin
                pass_count++;
                $display("[PASS] A=%04h B=%04h Op=%01h PUF=%b | Enc(expected)=%08h Enc(got)=%08h",
                         d_trans.a, d_trans.b, d_trans.opcode, d_trans.puf_enable,
                         expected_enc, m_trans.encrypted_result);
            end else begin
                fail_count++;
                $display("[FAIL] A=%04h B=%04h Op=%01h PUF=%b | Enc(expected)=%08h Enc(got)=%08h",
                         d_trans.a, d_trans.b, d_trans.opcode, d_trans.puf_enable,
                         expected_enc, m_trans.encrypted_result);
            end
        end

        $display("========================================");
        $display("  SCOREBOARD FINAL REPORT");
        $display("========================================");
        $display("  Total PASS: %0d", pass_count);
        $display("  Total FAIL: %0d", fail_count);
        if ((pass_count + fail_count) > 0)
            $display("  Success Rate: %0.2f%%",
                     (pass_count * 100.0) / (pass_count + fail_count));
        $display("========================================");
    endtask

endclass
