`timescale 1ns / 10ps

module clk_gen2(
    input               clk_i,
    input               rst_n,      // ← 추가
    input   [15:0]      count_i,
    output              clk_o
);
    
    reg     [15:0]  sig_count;
    reg             sig_clk_out;
    
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            sig_count <= 16'd0;
        end else begin
            if (sig_count == count_i) begin
                sig_count <= 16'd0;
            end else begin
                sig_count <= sig_count + 1;
            end
        end
    end
    
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            sig_clk_out <= 1'b0;
        end else begin
            if (sig_count == count_i) begin
                sig_clk_out <= ~sig_clk_out;
            end
        end
    end
    
    assign clk_o = sig_clk_out;
    
endmodule