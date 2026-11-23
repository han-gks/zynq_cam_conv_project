`timescale 1ns / 10ps

module Rst_sync(
    input              clk_i,
    input              sig_i,      // ✓ 추가
    output             sig_o
);
    


    reg        rDelay1,rDelay2;
    
    // 카운터
    always @(posedge clk_i) begin
        rDelay2 <= rDelay1;
        rDelay1 <= sig_i;     
    end
        
    
    assign sig_o = rDelay2;

    
endmodule