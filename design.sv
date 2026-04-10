`timescale 1ns/1ps

// ==========================================================
// PUF STAGE
// ==========================================================
module puf_stage (
    input logic p0_in, p1_in, chall_bit,
    output logic p0_out, p1_out
);
    assign p0_out = (chall_bit) ? p1_in : p0_in;
    assign p1_out = (chall_bit) ? p0_in : p1_in;
endmodule

// ==========================================================
// ARBITER PUF
// ==========================================================
module arbiter_puf #(parameter WIDTH = 8) (
    input logic trig,
    input logic [WIDTH-1:0] chall,
    output logic resp
);
    logic [WIDTH:0] path0, path1;
    assign path0[0] = trig;
    assign path1[0] = trig;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin : stages
            puf_stage stage_inst (
                .p0_in(path0[i]),    .p1_in(path1[i]),
                .chall_bit(chall[i]),
                .p0_out(path0[i+1]), .p1_out(path1[i+1])
            );
        end
    endgenerate

    always_latch begin
        if      (path0[WIDTH]) resp = 1'b1;
        else if (path1[WIDTH]) resp = 1'b0;
    end
endmodule

// ==========================================================
// COMBINATIONAL ALU
// ==========================================================
module alu (
    input  [15:0] a, b,
    input  [3:0]  s,
    output reg [31:0] out
);
    always @(*) begin
        case(s)
            4'b0000: out = a + b;
            4'b0001: out = a - b;
            4'b0010: out = a * b;
            4'b0011: out = b != 0 ? a / b  : 32'hFFFFFFFF;
            4'b0100: out = b != 0 ? a % b  : 32'hFFFFFFFF;
            4'b0101: out = {31'b0, a && b};
            4'b0110: out = {31'b0, a || b};
            4'b0111: out = {31'b0, !a};
            4'b1000: out = {16'b0, ~a};
            4'b1001: out = {16'b0, a & b};
            4'b1010: out = {16'b0, a | b};
            4'b1011: out = {16'b0, a ^ b};
            4'b1100: out = a << 1;
            4'b1101: out = a >> 1;
            4'b1110: out = a + 1;
            4'b1111: out = a - 1;
        endcase
    end
endmodule

// ==========================================================
// CHALLENGE GENERATOR
// ==========================================================
module challenge_generator (
    input  [15:0] a, b,
    input  [3:0]  opcode,
    output [31:0] challenge
);
    assign challenge = {opcode, a, b[11:0]};
endmodule


module secure_alu (
    input  clk,
    input  rst_n,
    input  [15:0] a, b,
    input  [3:0]  opcode,
    input         puf_enable,

    // PUF behavioral model injection (testbench use only)
    input  [3:0]  puf_key_override,
    input         puf_override_enable,

    // Outputs: ciphertext + handshake only
    output reg [31:0] encrypted_result,
    output reg        key_ready
);

    // ÷8 clock enable
    reg [2:0] clk_div_cnt;
    wire alu_clk_en = (clk_div_cnt == 3'b000);

    // Pipeline registers
    reg [15:0] a_reg, b_reg;
    reg [3:0]  opcode_reg;
    reg [15:0] a_latched, b_latched;
    reg [3:0]  opcode_latched;

    // Internal-only registers (not ports)
    reg [31:0] alu_result;
    reg [31:0] puf_key;
    reg [31:0] key_buffer;
    reg        result_valid;
    reg        input_sampled;
    reg [1:0]  state;
    reg [3:0]  rotation_count;
    reg [31:0] current_challenge;
    reg [31:0] alu_captured;
    reg [31:0] challenge_latched;
    logic       puf_trig;

    wire [31:0] alu_out;
    alu alu_inst (.a(a_latched), .b(b_latched), .s(opcode_latched), .out(alu_out));

    wire [31:0] base_challenge;
    challenge_generator chall_gen (
        .a(a_reg), .b(b_reg), .opcode(opcode_reg),
        .challenge(base_challenge)
    );

    logic [7:0] puf_challenge [0:3];
    logic       puf_resp [0:3];

    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : puf_array
            arbiter_puf #(.WIDTH(8)) puf_inst (
                .trig(puf_trig),
                .chall(puf_challenge[i]),
                .resp(puf_resp[i])
            );
        end
    endgenerate

    wire [31:0] rotated_challenge =
        (current_challenge << (rotation_count * 4)) |
        (current_challenge >> (32 - rotation_count * 4));

    assign puf_challenge[0] = rotated_challenge[7:0];
    assign puf_challenge[1] = rotated_challenge[15:8];
    assign puf_challenge[2] = rotated_challenge[23:16];
    assign puf_challenge[3] = rotated_challenge[31:24];

    localparam IDLE    = 2'b00;
    localparam GEN_KEY = 2'b01;
    localparam DONE    = 2'b10;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg             <= 16'b0;
            b_reg             <= 16'b0;
            opcode_reg        <= 4'b0;
            a_latched         <= 16'b0;
            b_latched         <= 16'b0;
            opcode_latched    <= 4'b0;
            alu_result        <= 32'b0;
            key_ready         <= 1'b0;
            encrypted_result  <= 32'b0;
            puf_key           <= 32'b0;
            state             <= IDLE;
            rotation_count    <= 4'b0;
            key_buffer        <= 32'b0;
            alu_captured      <= 32'b0;
            current_challenge <= 32'b0;
            challenge_latched <= 32'b0;
            puf_trig          <= 1'b0;
            clk_div_cnt       <= 3'b0;
            result_valid      <= 1'b0;
            input_sampled     <= 1'b0;
        end else begin
            clk_div_cnt  <= clk_div_cnt + 1;
            result_valid <= 1'b0;

            a_reg      <= a;
            b_reg      <= b;
            opcode_reg <= opcode;

            case (state)

                IDLE: begin
                    key_ready      <= 0;
                    rotation_count <= 0;
                    key_buffer     <= 32'b0;
                    puf_trig       <= 1'b0;

                    if (alu_clk_en) begin
                        if (!input_sampled) begin
                            a_latched         <= a_reg;
                            b_latched         <= b_reg;
                            opcode_latched    <= opcode_reg;
                            challenge_latched <= base_challenge;
                            input_sampled     <= 1'b1;
                        end else begin
                            input_sampled <= 1'b0;
                            alu_result    <= alu_out;   // stays internal
                            puf_key       <= 32'b0;
                            result_valid  <= 1'b1;

                            if (puf_enable) begin
                                // Suppress plaintext output until encryption is done
                                encrypted_result  <= 32'b0;
                                state             <= GEN_KEY;
                                alu_captured      <= alu_out;
                                current_challenge <= challenge_latched;
                                puf_trig          <= 1'b1;
                            end else begin
                                // Non-encrypted path: output is plaintext ALU result
                                encrypted_result <= alu_out;
                            end
                        end
                    end
                end

                GEN_KEY: begin
                    if (rotation_count < 8) begin
                        if (puf_override_enable) begin
                            key_buffer[rotation_count*4 + 0] <= puf_key_override[0];
                            key_buffer[rotation_count*4 + 1] <= puf_key_override[1];
                            key_buffer[rotation_count*4 + 2] <= puf_key_override[2];
                            key_buffer[rotation_count*4 + 3] <= puf_key_override[3];
                        end
                        rotation_count <= rotation_count + 1;
                    end else begin
                        puf_key          <= key_buffer;            // internal
                        encrypted_result <= alu_captured ^ key_buffer; // only XOR output is exposed
                        key_ready        <= 1'b1;
                        puf_trig         <= 1'b0;
                        state            <= DONE;
                    end
                end

                DONE: begin
                    if (alu_clk_en) begin
                        state         <= IDLE;
                        key_ready     <= 1'b0;
                        input_sampled <= 1'b0;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
