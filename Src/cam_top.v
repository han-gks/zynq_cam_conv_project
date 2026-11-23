`timescale 1ns/10ps

module top (
    // Clock & reset
    input wire            PL_CLK_100MHZ,
    input wire            iRsn,
    
    // 필터 선택
    input wire [2:0]      filter_select,

    // Custom 필터 계수 (AXI-Lite 레지스터에서 들어옴)
    input wire signed [7:0] custom_k0,
    input wire signed [7:0] custom_k1,
    input wire signed [7:0] custom_k2,
    input wire signed [7:0] custom_k3,
    input wire signed [7:0] custom_k4,
    input wire signed [7:0] custom_k5,
    input wire signed [7:0] custom_k6,
    input wire signed [7:0] custom_k7,
    input wire signed [7:0] custom_k8,
    
    // 카메라 인터페이스
    inout wire            CAMERA_SCCB_SCL,
    inout wire            CAMERA_SCCB_SDA,
    input wire            CAMERA_PCLK,
    input wire  [7:0]     CAMERA_DATA,
    output wire           CAMERA_RESETn,
    input wire            CAMERA_HSYNC,
    input wire            CAMERA_VSYNC,
    output wire           CAMERA_PWDN,
    output wire           CAMERA_MCLK,
    
    // LCD 출력
    output wire           TFT_DCLK,
    output wire           TFT_BACKLIGHT,
    output wire           TFT_DE,
    output wire           TFT_HSYNC,
    output wire           TFT_VSYNC,
    output wire [4:0]     TFT_B_DATA,
    output wire [5:0]     TFT_G_DATA,
    output wire [4:0]     TFT_R_DATA
);

    // =====================================================
    // Reset 동기화
    // =====================================================
    wire                wRsn;
    
    Rst_sync rst_synchronizer (
        .clk_i          (PL_CLK_100MHZ),
        .sig_i          (iRsn),
        .sig_o          (wRsn)
    );

    // =====================================================
    // 클럭 생성
    // =====================================================
    clk_gen2    CLK_GEN_MAIN(
        .clk_i(PL_CLK_100MHZ),
        .rst_n(wRsn),
        .count_i(16'h0001),
        .clk_o(CAMERA_MCLK)
    );//25MHz
    
    clk_gen2    CLK_GEN_TFTLCD(
        .clk_i(CAMERA_MCLK),
        .rst_n(wRsn),
        .count_i(16'h0001),
        .clk_o(TFT_DCLK)
    );

    // =====================================================
    // camera_to_ram (카메라 데이터 수신)
    // =====================================================
    wire                cam_wr_en_w;
    wire [16:0]         cam_wr_addr_w;
    wire [15:0]         cam_wr_data_w;  // RGB565
    wire                cam_frame_done_w;

    camera_to_ram CAMEARA_TO_RAM(
        .clk_i(CAMERA_PCLK),
        .sw_i(1'b1),
        .cam_vsync_i(CAMERA_VSYNC),
        .cam_hsync_i(CAMERA_HSYNC),
        .cam_data_i(CAMERA_DATA),
        .ram_wr_en_o(cam_wr_en_w),
        .ram_wr_addr_o(cam_wr_addr_w),
        .ram_wr_data_o(cam_wr_data_w),
        .frame_done_o   (cam_frame_done_w)
    );

    // =====================================================
    // buf_controller (Double Buffer 관리)
    // 변경: CAMERA_PCLK 입력 추가
    // =====================================================
    wire [16:0]         conv_rd_addr_w;
    wire                conv_rd_en_w;
    wire [15:0]         conv_rd_data_w;  // RGB565
    wire                conv_start_w;
    wire                tft_lcd_done_w;
    
    buf_controller BUF_CONTROLLER(
        .clk_100mhz     (PL_CLK_100MHZ),
        .clk_pclk       (CAMERA_PCLK),      // ← 추가: 카메라 클럭
        .rst_n          (wRsn),
        
        // 카메라 (PCLK 도메인)
        .cam_frame_done (cam_frame_done_w),
        .cam_wr_en_req  (cam_wr_en_w),
        .cam_wr_addr    (cam_wr_addr_w),
        .cam_wr_data    (cam_wr_data_w),
        
        // InBuf (100MHz 도메인)
        .conv_rd_addr   (conv_rd_addr_w),
        .conv_rd_en     (conv_rd_en_w),
        .conv_rd_data   (conv_rd_data_w),
        .conv_start     (conv_start_w),
        
        // Conv Done
        .tft_lcd_done   (tft_lcd_done_w)
    );

    // =====================================================
    // InBuf (3x3 Window 생성) - RGB565
    // =====================================================
    wire [15:0]         wPixel0, wPixel1, wPixel2;  // RGB565
    wire [15:0]         wPixel3, wPixel4, wPixel5;
    wire [15:0]         wPixel6, wPixel7, wPixel8;
    wire                wInBufValid;
    wire [8:0]          wInBufRow;
    wire [8:0]          wInBufCol;
    wire                wInBufDone;
    
    InBuf u_InBuf (
        .iClk           (PL_CLK_100MHZ),
        .iRst_n         (wRsn),
        .iStart         (conv_start_w),              // ← 추가
        
        // 외부 BRAM
        .iRdData        (conv_rd_data_w),           // ← 추가 (RGB565)
        .oRdAddr        (conv_rd_addr_w),           // ← 추가
        .oRdEn          (conv_rd_en_w),               // ← 추가
        
        // 3x3 Window (RGB565)
        .oPix00         (wPixel0),
        .oPix01         (wPixel1),
        .oPix02         (wPixel2),
        .oPix10         (wPixel3),
        .oPix11         (wPixel4),
        .oPix12         (wPixel5),
        .oPix20         (wPixel6),
        .oPix21         (wPixel7),
        .oPix22         (wPixel8),
        
        .oValid         (wInBufValid),
        .oRow           (wInBufRow),
        .oCol           (wInBufCol),
        .oDone          (wInBufDone)
    );

    // =====================================================
    // Pxl565to888 
    // =====================================================
    wire [23:0]         w888Pixel0, w888Pixel1, w888Pixel2;  // RGB888
    wire [23:0]         w888Pixel3, w888Pixel4, w888Pixel5;
    wire [23:0]         w888Pixel6, w888Pixel7, w888Pixel8;

    wire                w5to8Valid;
    wire [8:0]          wRowDelay, wColDelay;

    Pxl565to888 u_Pxl565to888 (
        .iClk           (PL_CLK_100MHZ),
        .iRsn           (wRsn),
        
        .iValid         (wInBufValid),
        .iRow           (wInBufRow),
        .iCol           (wInBufCol),
        
        // InBuf에서 (RGB565)
        .i565Pixel0     (wPixel0),
        .i565Pixel1     (wPixel1),
        .i565Pixel2     (wPixel2),
        .i565Pixel3     (wPixel3),
        .i565Pixel4     (wPixel4),
        .i565Pixel5     (wPixel5),
        .i565Pixel6     (wPixel6),
        .i565Pixel7     (wPixel7),
        .i565Pixel8     (wPixel8),
        
        .oValid         (w5to8Valid),
        .oRow           (wRowDelay),
        .oCol           (wColDelay),
        
        .o888Pixel0     (w888Pixel0),
        .o888Pixel1     (w888Pixel1),
        .o888Pixel2     (w888Pixel2),
        .o888Pixel3     (w888Pixel3),
        .o888Pixel4     (w888Pixel4),
        .o888Pixel5     (w888Pixel5),
        .o888Pixel6     (w888Pixel6),
        .o888Pixel7     (w888Pixel7),
        .o888Pixel8     (w888Pixel8)
    );


    // =====================================================
    // ConvRelu (Convolution + ReLU) - RGB565
    // =====================================================
    wire                wConvReluValid;
    wire [16:0]         wConvReluAddr;
    wire [23:0]         wConvReluPixel;  // RGB565
    
    ConvRelu u_ConvRelu (
        .iClk           (PL_CLK_100MHZ),
        .iRsn           (wRsn),
        .iDone          (tft_lcd_done_w),

        .filter_select  (filter_select),    // 수정: iSwitch → filter_select

        // Custom 필터 계수 (top 입력에서 받음)
        .custom_k0      (custom_k0),
        .custom_k1      (custom_k1),
        .custom_k2      (custom_k2),
        .custom_k3      (custom_k3),
        .custom_k4      (custom_k4),
        .custom_k5      (custom_k5),
        .custom_k6      (custom_k6),
        .custom_k7      (custom_k7),
        .custom_k8      (custom_k8),
        
        // InBuf에서 (RGB565)
        .iPixel0        (w888Pixel0),
        .iPixel1        (w888Pixel1),
        .iPixel2        (w888Pixel2),
        .iPixel3        (w888Pixel3),
        .iPixel4        (w888Pixel4),
        .iPixel5        (w888Pixel5),
        .iPixel6        (w888Pixel6),
        .iPixel7        (w888Pixel7),
        .iPixel8        (w888Pixel8),
        
        .iValid         (w5to8Valid),
        .iRow           (wRowDelay),
        .iCol           (wColDelay),
        
        // PixelConversion으로 (RGB565)
        .oValid         (wConvReluValid),
        .oAddr          (wConvReluAddr),
        .oPixel         (wConvReluPixel)
    );

    // =====================================================
    // PixelConversion (Bypass) - RGB565
    // =====================================================
    wire [16:0]         wAddrA;
    wire [15:0]         wRgb565;
    wire                wCsnA;
    
    PixelConversion u_PixelConversion (
        .iClk           (PL_CLK_100MHZ),
        .iRsn           (wRsn),
        .iAddr          (wConvReluAddr),
        .iVal           (wConvReluValid),
        .iRgb888        (wConvReluPixel),         // 수정: iRgb888 → iRgb565
        
        .oCsnA          (wCsnA),
        .oRgb565        (wRgb565),
        .oAddrA         (wAddrA)
        //.oDone          (pixel_conv_done_w) // buf_controller로 연결
    );
    

    // =====================================================
    // OutBuf (Dual Port BRAM) - RGB565
    // =====================================================
    wire [16:0]         wAddrB;
    wire                wCsnB;
    wire [15:0]         wRdDt;
    
    blk_mem_gen_0 u_dpram (
        // Write Port (100MHz)
        .addra          (wAddrA),
        .clka           (PL_CLK_100MHZ),
        .dina           (wRgb565),
        .ena            (!wCsnA),
        .wea            (!wCsnA),
        
        // Read Port (100MHz, TFT_DCLK enable)
        .addrb          (wAddrB),
        .clkb           (TFT_DCLK),
        .doutb          (wRdDt),
        .enb            (!wCsnB)
    );

    // =====================================================
    // ram_to_lcd (LCD 출력)
    // =====================================================
    ram_to_lcd u_RAMTOLCD (
        .clk_i          (TFT_DCLK),
        .rst_n          (wRsn),
        .ram_rd_csn_o   (wCsnB),
        .ram_rd_addr_o  (wAddrB),
        .ram_rd_data_i  (wRdDt),
        
        .LCD_hsync_o    (TFT_HSYNC),
        .LCD_vsync_o    (TFT_VSYNC),
        .LCD_R_o        (TFT_R_DATA),
        .LCD_G_o        (TFT_G_DATA),
        .LCD_B_o        (TFT_B_DATA),

        .Done_o         (tft_lcd_done_w)
    );

    // =====================================================
    // LCD 제어 신호
    // =====================================================
    assign TFT_BACKLIGHT = 1'b1;
    assign TFT_DE        = 1'b1;

endmodule