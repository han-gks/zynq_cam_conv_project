`timescale 1ns / 10ps

module ram_to_lcd(
    input               clk_i,      // 6.25MHz TFT_DCLK (변경!)
    input               rst_n,
    // iEnClk 제거
    
    output  [16:0]      ram_rd_addr_o,
    output              ram_rd_csn_o,
    input   [15:0]      ram_rd_data_i,
    
    output              LCD_hsync_o,
    output              LCD_vsync_o,
    output  [4:0]       LCD_R_o,
    output  [5:0]       LCD_G_o,
    output  [4:0]       LCD_B_o,

    output              Done_o
);
    
    reg     [15:0]  h_count;
    reg             hsync;
    reg             hsync_delay1;
    reg             hsync_delay2;
    
    reg     [15:0]  v_count;
    reg             vsync;
    reg             vsync_delay1;
    reg             vsync_delay2;
    
    reg     [16:0]  ram_rd_addr;
    reg     [15:0]  ram_rd_data;
    
    reg             ram_rd_csn;
    
    reg     [4:0]   lcd_r;
    reg     [5:0]   lcd_g;
    reg     [4:0]   lcd_b;

    reg             done;
    reg             done_delay;

    // =====================================================
    // Hsync/Vsync 생성 (iEnClk 제거 - 항상 동작)
    // =====================================================
    always @(posedge clk_i) begin
        if (!rst_n) begin
            h_count <= 16'd0;
            v_count <= 16'd0;
            hsync <= 1'b0;
            vsync <= 1'b0;
        end else begin
            if (h_count < 40) begin
                hsync <= 1'b0;
                h_count <= h_count + 1;
            end else if ((h_count >= 40) && (h_count < 522)) begin
                hsync <= 1'b1;
                h_count <= h_count + 1;
            end else begin
                hsync <= 1'b0;
                h_count <= 16'd0;
                
                if (v_count < 10) begin
                    vsync <= 1'b0;
                    v_count <= v_count + 1;
                end else if ((v_count >= 10) && (v_count < 284)) begin
                    vsync <= 1'b1;
                    v_count <= v_count + 1;
                end else begin
                    vsync <= 1'b0;
                    v_count <= 16'd0;
                end
            end
        end
    end
    
    // =====================================================
    // RAM 주소 생성 (iEnClk 제거 - 항상 동작)
    // =====================================================
    always @(posedge clk_i) begin
        if (!rst_n) begin
            ram_rd_addr <= 17'd0;
            ram_rd_csn <= 1'b1;
        end else begin
            if (vsync == 1'b0) begin
                ram_rd_addr <= 17'd0;
                ram_rd_csn <= 1'b1;
            end else begin
                if ((v_count >= 12) && (v_count < 284)) begin
                    if ((h_count >= 42) && (h_count < 522)) begin
                        ram_rd_addr <= ram_rd_addr + 1;
                        ram_rd_csn <= 1'b0;    // 활성화
                    end else begin
                        ram_rd_csn <= 1'b1;    // 비활성화
                    end
                end else begin
                    ram_rd_csn <= 1'b1;    // 비활성화
                end
            end
        end
    end

    // =====================================================
    // Done 신호 생성 (iEnClk 제거 - 항상 동작)
    // =====================================================
    always @(posedge clk_i) begin
        if (!rst_n) begin
            done_delay <= 1'b0;
            done <= 1'b0;
        end else begin
            if (ram_rd_addr == 17'h1fe00) begin
                done <= 1'b1;                
            end else begin
                done <= 1'b0;
            end
            done_delay <= done;
        end
    end
    
    assign ram_rd_addr_o = ram_rd_addr;
    assign ram_rd_csn_o = ram_rd_csn;
    
    // =====================================================
    // Sync 신호 지연 (iEnClk 제거 - 항상 동작)
    // =====================================================
    always @(negedge clk_i) begin
        if (!rst_n) begin
            hsync_delay1 <= 1'b0;
            hsync_delay2 <= 1'b0;
            vsync_delay1 <= 1'b0;
            vsync_delay2 <= 1'b0;
        end else begin
            hsync_delay1 <= hsync;
            hsync_delay2 <= hsync_delay1;
            
            vsync_delay1 <= vsync;
            vsync_delay2 <= vsync_delay1;
        end
    end
    
    assign LCD_hsync_o = hsync_delay2;
    assign LCD_vsync_o = vsync_delay2;
    
    // =====================================================
    // RAM 데이터 래치 (iEnClk 제거 - 항상 동작)
    // =====================================================
    always @(posedge clk_i) begin
        if (!rst_n) begin
            ram_rd_data <= 16'd0;
        end else begin
            if (v_count == 12) begin
                if (h_count == 43) begin
                    ram_rd_data <= 16'd1;
                end else if (h_count == 522) begin
                    ram_rd_data <= 16'd1;
                end else begin
                    ram_rd_data <= ram_rd_data_i;
                end
            end else if (v_count == 283) begin
                if (h_count == 43) begin
                    ram_rd_data <= 16'd1;
                end else if (h_count == 522) begin
                    ram_rd_data <= 16'd1;
                end else begin
                    ram_rd_data <= ram_rd_data_i;
                end
            end else begin
                ram_rd_data <= ram_rd_data_i;
            end
        end
    end
    
    // =====================================================
    // RGB 출력 (iEnClk 제거 - 항상 동작)
    // =====================================================
    always @(negedge clk_i) begin
        if (!rst_n) begin
            lcd_r <= 5'd0;
            lcd_g <= 6'd0;
            lcd_b <= 5'd0;
        end else begin
            lcd_r <= ram_rd_data[4:0];
            lcd_g <= ram_rd_data[10:5];
            lcd_b <= ram_rd_data[15:11];
        end
    end
    
    assign LCD_R_o = lcd_r;
    assign LCD_G_o = lcd_g;
    assign LCD_B_o = lcd_b;
    
    assign Done_o = (done & ~done_delay);

endmodule