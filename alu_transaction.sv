`timescale 1ns/1ps
class alu_transaction;
    // Driven inputs
    rand bit [15:0] a, b;
    rand bit [3:0]  opcode;
    rand bit        puf_enable;

    bit [31:0] encrypted_result;

    function new();
        a                = 0;
        b                = 0;
        opcode           = 0;
        puf_enable       = 0;
        encrypted_result = 0;
    endfunction

    // Avoid division by zero
    constraint div_constraint {
        (opcode == 4'h3 || opcode == 4'h4) -> b != 0;
    }

    // 100% PUF enabled (encryption always on)
    constraint puf_bias {
        puf_enable dist {0 := 0, 1 := 100};
    }

    function void display(string prefix = "");
        $display("%s A=%04h B=%04h Op=%01h PUF=%b | Enc=%08h",
                 prefix, a, b, opcode, puf_enable, encrypted_result);
    endfunction

endclass
