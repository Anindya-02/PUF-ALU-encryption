`timescale 1ns/1ps

`include "alu_puf_if.sv"
`include "alu_env.sv"

module testbench;

    logic clk;
    initial clk = 0;
    always #5 clk = ~clk;

    alu_puf_if aluif(clk);

    // PUF injection wires - driven by TB behavioral model, wired to DUT directly
    reg [3:0] puf_key_override;
    reg       puf_override_enable;

    secure_alu dut(
        .clk                (clk),
        .rst_n              (aluif.rst_n),
        .a                  (aluif.a),
        .b                  (aluif.b),
        .opcode             (aluif.opcode),
        .puf_enable         (aluif.puf_enable),
        .puf_key_override   (puf_key_override),
        .puf_override_enable(puf_override_enable),
        .encrypted_result   (aluif.encrypted_result),
        .key_ready          (aluif.key_ready)
    );

    // ==========================================================
    // PUF Delay Model - 4 paths × 8 stages, base=0.75ns
    // ==========================================================
    real delay_p0_straight[0:3][0:7];
    real delay_p0_cross[0:3][0:7];
    real delay_p1_straight[0:3][0:7];
    real delay_p1_cross[0:3][0:7];

    int seed;

    initial begin
        seed = 117;
        //$display("[TB] Initializing 4-path PUF delay model (base=0.75ns, seed=%0d)", seed);
        for (int path = 0; path < 4; path++) begin
            for (int stage = 0; stage < 8; stage++) begin
                delay_p0_straight[path][stage] = 0.75 + ($dist_normal(seed,0,50)/1000.0);
                delay_p0_cross[path][stage]    = 0.75 + ($dist_normal(seed,0,50)/1000.0);
                delay_p1_straight[path][stage] = 0.75 + ($dist_normal(seed,0,50)/1000.0);
                delay_p1_cross[path][stage]    = 0.75 + ($dist_normal(seed,0,50)/1000.0);
            end
        end
       // $display("[TB] PUF delay model initialized");
    end

    // ==========================================================
    // PUF Key Injection Logic
    // Internal DUT signals via hierarchical references
    // ==========================================================
    reg [31:0] puf_key_precomputed;
    reg        key_computed;

    function bit compute_puf_bit(input bit [7:0] challenge, input int path_idx);
        real d0, d1;
        d0 = 0.0; d1 = 0.0;
        for (int i = 0; i < 8; i++) begin
            d0 += challenge[i] ? delay_p0_cross[path_idx][i]    : delay_p0_straight[path_idx][i];
            d1 += challenge[i] ? delay_p1_cross[path_idx][i]    : delay_p1_straight[path_idx][i];
        end
        return (d0 < d1) ? 1'b1 : 1'b0;
    endfunction

    function bit [31:0] compute_puf_key(input bit [31:0] base_challenge);
        bit [31:0] key, rotated;
        bit [7:0]  slice[0:3];
        for (int rot = 0; rot < 8; rot++) begin
            rotated   = (base_challenge << (rot*4)) | (base_challenge >> (32 - rot*4));
            slice[0]  = rotated[7:0];
            slice[1]  = rotated[15:8];
            slice[2]  = rotated[23:16];
            slice[3]  = rotated[31:24];
            key[rot*4+0] = compute_puf_bit(slice[0], 0);
            key[rot*4+1] = compute_puf_bit(slice[1], 1);
            key[rot*4+2] = compute_puf_bit(slice[2], 2);
            key[rot*4+3] = compute_puf_bit(slice[3], 3);
        end
        return key;
    endfunction

    always @(negedge clk) begin
        if (!aluif.rst_n) begin
            puf_override_enable = 1'b0;
            puf_key_override    = 4'b0;
            key_computed        = 0;
            puf_key_precomputed = 32'b0;

        end else begin
            if (dut.state == 2'b01) begin  // GEN_KEY

                if (!key_computed) begin
                    //$display("[%0t] TB-PUF: Entering GEN_KEY, challenge=%08h",
                      //       $time, dut.current_challenge);
                    puf_key_precomputed = compute_puf_key(dut.current_challenge);
                    key_computed        = 1;
                   // $display("[%0t] TB-PUF: Precomputed key=%08h", $time, puf_key_precomputed);
                end

                if (dut.rotation_count < 8) begin
                    puf_override_enable = 1'b1;
                    puf_key_override    = {
                        puf_key_precomputed[dut.rotation_count*4 + 3],
                        puf_key_precomputed[dut.rotation_count*4 + 2],
                        puf_key_precomputed[dut.rotation_count*4 + 1],
                        puf_key_precomputed[dut.rotation_count*4 + 0]
                    };
                end else begin
                    puf_override_enable = 1'b0;
                end

            end else begin
                if (key_computed)
                  //  $display("[%0t] TB-PUF: Exiting GEN_KEY state", $time);
                puf_override_enable = 1'b0;
                puf_key_override    = 4'b0;
                key_computed        = 0;
            end
        end
    end

    // ==========================================================
    // Test Execution
    // ==========================================================
    int    count = 50;
    alu_env env;

    initial begin
        $display("========================================");
        $display("  ALU-PUF 4-PATH TESTBENCH START");
        $display("========================================");

        aluif.rst_n         = 0;
        aluif.a             = 0;
        aluif.b             = 0;
        aluif.opcode        = 0;
        aluif.puf_enable    = 0;
        puf_override_enable = 0;
        puf_key_override    = 0;

        env = new(aluif);
        env.main(count);
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, testbench);
    end

    initial begin
        #1000;
       // $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
