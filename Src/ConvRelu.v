`timescale 1ns/10ps

module ConvRelu(
   input           iClk,    // 100MHz
   input           iRsn,
   input           iDone,

   // 버튼 입력: 커널 선택용
   input   [2:0]   filter_select,

   input signed [7:0] custom_k0,
   input signed [7:0] custom_k1,
   input signed [7:0] custom_k2,
   input signed [7:0] custom_k3,
   input signed [7:0] custom_k4,
   input signed [7:0] custom_k5,
   input signed [7:0] custom_k6,
   input signed [7:0] custom_k7,
   input signed [7:0] custom_k8,

   input   [23:0]  iPixel0,
   input   [23:0]  iPixel1,
   input   [23:0]  iPixel2,
   input   [23:0]  iPixel3,
   input   [23:0]  iPixel4,
   input   [23:0]  iPixel5,
   input   [23:0]  iPixel6,
   input   [23:0]  iPixel7,
   input   [23:0]  iPixel8,

   input           iValid,
   input   [8:0]   iRow,
   input   [8:0]   iCol,

   output  reg         oValid,
   output  reg  [16:0] oAddr,
   output  reg  [23:0] oPixel
);

    // ------------------------------------------------------------
    // 커널 선택 모드
    //  wMode = {iBtn2, iBtn0}
    //    2'b00 : Sharpen
    //    2'b01 : Edge Enhance
    //    2'b1x : Bypass
    // ------------------------------------------------------------
    //wire [1:0] wMode = {iBtn1, iBtn0};
    wire [2:0] wMode = filter_select;
    
    // ------------------------------------------------------------
    // Shadow Register: 실제 연산에 사용될 필터 계수
    // ------------------------------------------------------------
    reg signed [7:0] rK0, rK1, rK2;
    reg signed [7:0] rK3, rK4, rK5;
    reg signed [7:0] rK6, rK7, rK8;

    // ------------------------------------------------------------
    // Update Trigger: 프레임 완료 시에만 필터 업데이트
    // ------------------------------------------------------------
    wire wUpdateTrigger = (iDone == 1'b1);

    // ------------------------------------------------------------
    // Sharpen:
    //   0  -1   0
    //  -1   5  -1
    //   0  -1   0
    //
    // Edge Enchance:
    //  -1  -1  -1
    //  -1   9  -1
    //  -1  -1  -1
    //
    // Bypass:
    //   0   0   0
    //   0   1   0
    //   0   0   0

    // Custom:
    //   custom_k0  custom_k1  custom_k2
    //   custom_k3  custom_k4  custom_k5
    //   custom_k6  custom_k7  custom_k8
    // ------------------------------------------------------------

    // ------------------------------------------------------------
    // 필터 계수 업데이트 로직 (Shadow Register Update)
    // 프레임이 끝날 때만 새로운 필터 계수로 업데이트
    // ------------------------------------------------------------
    always @(posedge iClk) begin
        if (!iRsn) begin
            // Reset 시 기본값 (Bypass)
            rK0 <= 8'sd0; rK1 <= 8'sd0; rK2 <= 8'sd0;
            rK3 <= 8'sd0; rK4 <= 8'sd1; rK5 <= 8'sd0;
            rK6 <= 8'sd0; rK7 <= 8'sd0; rK8 <= 8'sd0;
        end
        else if (wUpdateTrigger) begin
            case (wMode)
                3'b000: begin // Sharpen
                    rK0 <= 8'sd0;  rK1 <= -8'sd1; rK2 <= 8'sd0;
                    rK3 <= -8'sd1; rK4 <= 8'sd5;  rK5 <= -8'sd1;
                    rK6 <= 8'sd0;  rK7 <= -8'sd1; rK8 <= 8'sd0;
                end
                3'b001: begin // Edge Enhance
                    rK0 <= -8'sd1; rK1 <= -8'sd1; rK2 <= -8'sd1;
                    rK3 <= -8'sd1; rK4 <= 8'sd9;  rK5 <= -8'sd1;
                    rK6 <= -8'sd1; rK7 <= -8'sd1; rK8 <= -8'sd1;
                end
                3'b010: begin // Bypass
                    rK0 <= 8'sd0; rK1 <= 8'sd0; rK2 <= 8'sd0;
                    rK3 <= 8'sd0; rK4 <= 8'sd1; rK5 <= 8'sd0;
                    rK6 <= 8'sd0; rK7 <= 8'sd0; rK8 <= 8'sd0;
                end
                3'b011: begin // Custom (AXI 레지스터에서 받은 값)
                    rK0 <= custom_k0;
                    rK1 <= custom_k1;
                    rK2 <= custom_k2;
                    rK3 <= custom_k3;
                    rK4 <= custom_k4;
                    rK5 <= custom_k5;
                    rK6 <= custom_k6;
                    rK7 <= custom_k7;
                    rK8 <= custom_k8;
                end
                default: begin // Bypass
                    rK0 <= 8'sd0; rK1 <= 8'sd0; rK2 <= 8'sd0;
                    rK3 <= 8'sd0; rK4 <= 8'sd1; rK5 <= 8'sd0;
                    rK6 <= 8'sd0; rK7 <= 8'sd0; rK8 <= 8'sd0;
                end
            endcase
        end
    end

    // wire signed [7:0] K0 =
    //     (wMode == 2'b00)  ?      8'sd0       :    // Sharpen
    //     (wMode == 2'b01)  ?      -8'sd1      :    // Edge
    //     (wMode == 3'b011) ?      custom_k0   :    // Custom
    //                              8'sd0;           // Bypass

    // wire signed [7:0] K1 =
    //     (wMode == 2'b00)  ?     -8'sd1       :    // Sharpen
    //     (wMode == 2'b01)  ?     -8'sd1       :    // Edge
    //     (wMode == 3'b011) ?     custom_k1    :    // Custom
    //                             8'sd0;            // Bypass

    // wire signed [7:0] K2 =
    //     (wMode == 2'b00)  ?     8'sd0        :
    //     (wMode == 2'b01)  ?     -8'sd1       :
    //     (wMode == 3'b011) ?     custom_k2    :
    //                             8'sd0;

    // wire signed [7:0] K3 =
    //     (wMode == 2'b00)  ?     -8'sd1       :
    //     (wMode == 2'b01)  ?     -8'sd1       :
    //     (wMode == 3'b011) ?     custom_k3    :
    //                             8'sd0;

    // wire signed [7:0] K4 =
    //     (wMode == 2'b00)  ?     8'sd5        :
    //     (wMode == 2'b01)  ?     8'sd9        :
    //     (wMode == 3'b011) ?     custom_k4    :
    //                             8'sd1;            // Bypass     


    // wire signed [7:0] K5 =
    //     (wMode == 2'b00)  ?     -8'sd1       :
    //     (wMode == 2'b01)  ?     -8'sd1       :
    //     (wMode == 3'b011) ?     custom_k5    :
    //                             8'sd0;

    // wire signed [7:0] K6 =
    //     (wMode == 2'b00)  ?     8'sd0        :
    //     (wMode == 2'b01)  ?     -8'sd1       :
    //     (wMode == 3'b011) ?     custom_k6    :
    //                             8'sd0;

    // wire signed [7:0] K7 =
    //     (wMode == 2'b00)  ?     -8'sd1       :
    //     (wMode == 2'b01)  ?     -8'sd1       :
    //     (wMode == 3'b011) ?     custom_k7    :
    //                             8'sd0;

    // wire signed [7:0] K8 =
    //     (wMode == 2'b00)  ?     8'sd0        :
    //     (wMode == 2'b01)  ?     -8'sd1       :
    //     (wMode == 3'b011) ?     custom_k8    :
    //                             8'sd0;


//    localparam signed [7:0] K0 = 0;
//    localparam signed [7:0] K1 = -1;
//    localparam signed [7:0] K2 = 0;
//    localparam signed [7:0] K3 = -1;
//    localparam signed [7:0] K4 = 5;
//    localparam signed [7:0] K5 = -1;
//    localparam signed [7:0] K6 = 0;
//    localparam signed [7:0] K7 = -1;
//    localparam signed [7:0] K8 = 0;

//    localparam signed [7:0] K0 = -1;
//    localparam signed [7:0] K1 = -1;
//    localparam signed [7:0] K2 = -1;
//    localparam signed [7:0] K3 = -1;
//    localparam signed [7:0] K4 = 9;
//    localparam signed [7:0] K5 = -1;
//    localparam signed [7:0] K6 = -1;
//    localparam signed [7:0] K7 = -1;
//    localparam signed [7:0] K8 = -1;

    localparam IMG_WIDTH = 10'd480;

    // ------------------------------------------------------------
    // Pipeline Stage 1
    // ------------------------------------------------------------
    reg        rValid1;
    reg [8:0]  rRow1;
    reg [8:0]  rCol1;
    reg [23:0] rPixel0, rPixel1, rPixel2;
    reg [23:0] rPixel3, rPixel4, rPixel5;
    reg [23:0] rPixel6, rPixel7, rPixel8;

    always @(posedge iClk) begin
        if (!iRsn) begin
            rPixel0 <= 24'b0;
            rPixel1 <= 24'b0;
            rPixel2 <= 24'b0;
            rPixel3 <= 24'b0;
            rPixel4 <= 24'b0;
            rPixel5 <= 24'b0;
            rPixel6 <= 24'b0;
            rPixel7 <= 24'b0;
            rPixel8 <= 24'b0;
            rValid1 <= 1'b0;
            rRow1   <= 9'd0;
            rCol1   <= 9'd0;
        end
        else begin
            rValid1 <= iValid;
            if (iValid) begin
                rPixel0 <= iPixel0;
                rPixel1 <= iPixel1;
                rPixel2 <= iPixel2;
                rPixel3 <= iPixel3;
                rPixel4 <= iPixel4;
                rPixel5 <= iPixel5;
                rPixel6 <= iPixel6;
                rPixel7 <= iPixel7;
                rPixel8 <= iPixel8;
                rRow1   <= iRow;
                rCol1   <= iCol;
            end
        end
    end

    // ------------------------------------------------------------
    // Pipeline Stage 2: Convolution
    // ------------------------------------------------------------
    reg        rValid2;
    reg [8:0]  rRow2;
    reg [8:0]  rCol2;
    reg signed [15:0] rConvR;
    reg signed [15:0] rConvG;
    reg signed [15:0] rConvB;

    always @(posedge iClk) begin
        if (!iRsn) begin
            rConvR  <= 16'b0;
            rConvG  <= 16'b0;
            rConvB  <= 16'b0;
            rValid2 <= 1'b0;
            rRow2   <= 9'd0;
            rCol2   <= 9'd0;
        end
        else begin
            rValid2 <= rValid1;
            if (rValid1) begin
                rConvR <= $signed({1'b0, rPixel0[23:16]}) * rK0 +
                          $signed({1'b0, rPixel1[23:16]}) * rK1 +
                          $signed({1'b0, rPixel2[23:16]}) * rK2 +
                          $signed({1'b0, rPixel3[23:16]}) * rK3 +
                          $signed({1'b0, rPixel4[23:16]}) * rK4 +
                          $signed({1'b0, rPixel5[23:16]}) * rK5 +
                          $signed({1'b0, rPixel6[23:16]}) * rK6 +
                          $signed({1'b0, rPixel7[23:16]}) * rK7 +
                          $signed({1'b0, rPixel8[23:16]}) * rK8;

                rConvG <= $signed({1'b0, rPixel0[15:8]}) * rK0 +
                          $signed({1'b0, rPixel1[15:8]}) * rK1 +
                          $signed({1'b0, rPixel2[15:8]}) * rK2 +
                          $signed({1'b0, rPixel3[15:8]}) * rK3 +
                          $signed({1'b0, rPixel4[15:8]}) * rK4 +
                          $signed({1'b0, rPixel5[15:8]}) * rK5 +
                          $signed({1'b0, rPixel6[15:8]}) * rK6 +
                          $signed({1'b0, rPixel7[15:8]}) * rK7 +
                          $signed({1'b0, rPixel8[15:8]}) * rK8;

                rConvB <= $signed({1'b0, rPixel0[7:0]}) * rK0 +
                          $signed({1'b0, rPixel1[7:0]}) * rK1 +
                          $signed({1'b0, rPixel2[7:0]}) * rK2 +
                          $signed({1'b0, rPixel3[7:0]}) * rK3 +
                          $signed({1'b0, rPixel4[7:0]}) * rK4 +
                          $signed({1'b0, rPixel5[7:0]}) * rK5 +
                          $signed({1'b0, rPixel6[7:0]}) * rK6 +
                          $signed({1'b0, rPixel7[7:0]}) * rK7 +
                          $signed({1'b0, rPixel8[7:0]}) * rK8;

                rRow2 <= rRow1;
                rCol2 <= rCol1;
            end
        end
    end

    // ------------------------------------------------------------
    // Pipeline Stage 3: ReLU + clipping
    // ------------------------------------------------------------
    reg        rValid3;
    reg [8:0]  rRow3;
    reg [8:0]  rCol3;
    reg [7:0]  rReluR;
    reg [7:0]  rReluG;
    reg [7:0]  rReluB;

    always @(posedge iClk) begin
        if (!iRsn) begin
            rReluR  <= 8'b0;
            rReluG  <= 8'b0;
            rReluB  <= 8'b0;
            rValid3 <= 1'b0;
            rRow3   <= 9'd0;
            rCol3   <= 9'd0;
        end
        else begin
            rValid3 <= rValid2;
            if (rValid2) begin
                rReluR <= (rConvR >= 16'sd255) ? 8'd255 :
                          (rConvR <= 16'sd0  ) ? 8'd0   :
                          rConvR[7:0];

                rReluG <= (rConvG >= 16'sd255) ? 8'd255 :
                          (rConvG <= 16'sd0  ) ? 8'd0   :
                          rConvG[7:0];

                rReluB <= (rConvB >= 16'sd255) ? 8'd255 :
                          (rConvB <= 16'sd0  ) ? 8'd0   :
                          rConvB[7:0];

                rRow3 <= rRow2;
                rCol3 <= rCol2;
            end
        end
    end

    // ------------------------------------------------------------
    // Pipeline Stage 4: Output with address
    // ------------------------------------------------------------
    wire [17:0] wAddrFull = rRow3 * IMG_WIDTH + rCol3;

    always @(posedge iClk) begin
        if (!iRsn) begin
            oValid <= 1'b0;
            oAddr  <= 17'd0;
            oPixel <= 24'b0;
        end
        else begin
            oValid <= rValid3;
            if (rValid3) begin
                oPixel <= {rReluR, rReluG, rReluB};
                oAddr  <= wAddrFull[16:0];
            end
        end
    end

endmodule

