`timescale 1ns / 1ps

module InBuf(
    input               iClk,
    input               iRst_n,
    input               iStart,         // ← 추가: buf_controller의 conv_start
    
    // 외부 BRAM 인터페이스 (추가)
    input [15:0]        iRdData,        // ← 추가: buf_controller의 conv_rd_data (RGB565)
    output wire [16:0]  oRdAddr,        // ← 추가: buf_controller의 conv_rd_addr
    output wire         oRdEn,          // ← 추가: buf_controller의 conv_rd_en
    
    // 3x3 Window 출력 (RGB565로 변경)
    output reg [15:0]   oPix00, oPix01, oPix02,
    output reg [15:0]   oPix10, oPix11, oPix12,
    output reg [15:0]   oPix20, oPix21, oPix22,
    output reg          oValid,
    output reg [8:0]    oRow,
    output reg [8:0]    oCol,
    output reg          oDone
);

    // 이미지 파라미터
    localparam WIDTH = 480;
    localparam HEIGHT = 272;
    
    // BRAM 인터페이스
    reg [16:0] rBramAddr;
    wire [15:0] wBramData;             // 변경: 24bit → 16bit (RGB565)
    reg rBramEn;

    // BRAM IP 인스턴스 제거!
    // InputMemory_RGB888 제거
    
    // 외부 데이터를 그대로 사용 (RGB565)
    assign wBramData = iRdData;        // RGB565 그대로
    
    // 외부 출력
    assign oRdAddr = rBramAddr;
    assign oRdEn = rBramEn;

    // 3x3 Window Register (RGB565)
    reg [15:0] rWindow [0:8];          // 변경: 24bit → 16bit
    /*
        [0] [1] [2]    top-left,    top-center,    top-right
        [3] [4] [5]    middle-left, middle-center, middle-right
        [6] [7] [8]    bottom-left, bottom-center, bottom-right
    */
    
    // 현재 위치
    reg [8:0] rCol;  // 0~479
    reg [8:0] rRow;  // 0~271
    
    // FSM 상태
    reg [3:0] rCurState, rNxtState;
    localparam S_IDLE          = 3'd0;
    localparam S_ADDR_SETUP    = 3'd1;
    localparam S_LOAD_WINDOW   = 3'd2;
    localparam S_OUTPUT        = 3'd3;
    localparam S_SHIFT         = 3'd4;
    localparam S_DONE          = 3'd5;
    
    // 100MHz 카운터
    reg [4:0] rCycleCount;
    
    // 읽기 인덱스
    reg [3:0] rReadIdx;
    
    // 읽은 데이터 임시 저장 (RGB565)
    reg [15:0] rReadBuf [0:8];         // 변경: 24bit → 16bit
    
    // 경계 조건
    wire is_first_row = (rRow == 9'd0);
    wire is_last_row  = (rRow == HEIGHT - 1);
    wire is_first_col = (rCol == 9'd0);
    wire is_last_col  = (rCol == WIDTH - 1);
    
    integer i;

    //=========================================================================
    // Part 1: State Register
    //=========================================================================
    always @(posedge iClk or negedge iRst_n) begin
        if (!iRst_n) begin
            rCurState <= S_IDLE;
        end else begin
            rCurState <= rNxtState;
        end
    end

    //=========================================================================
    // Part 2: Next State Logic (수정)
    //=========================================================================
    always @(*) begin
        rNxtState = rCurState;
        
        case (rCurState)
            S_IDLE: begin
                if (iStart) begin              // ← 수정: iStart 대기
                    rNxtState = S_ADDR_SETUP;
                end
                // else: 계속 대기
            end
            
            S_ADDR_SETUP: begin
                rNxtState = S_LOAD_WINDOW;
            end
            
            S_LOAD_WINDOW: begin
                if (rCycleCount == 5'd27) begin
                    rNxtState = S_OUTPUT;
                end
            end
            
            S_OUTPUT: begin
                if (is_last_col) begin
                    if (is_last_row) begin
                        rNxtState = S_DONE;
                    end else begin
                        rNxtState = S_ADDR_SETUP;
                    end
                end else begin
                    rNxtState = S_SHIFT;
                end
            end
            
            S_SHIFT: begin
                if (rCycleCount == 5'd8) begin
                    rNxtState = S_OUTPUT;
                end
            end
            
            S_DONE: begin
                rNxtState = S_IDLE;            // ← 수정: Done 후 IDLE로
            end
            
            default: begin
                rNxtState = S_IDLE;
            end
        endcase
    end

    //=========================================================================
    // Part 3: Control Logic (100MHz)
    //=========================================================================
    always @(posedge iClk or negedge iRst_n) begin
        if (!iRst_n) begin
            rBramAddr <= 17'd0;
            rBramEn <= 1'b0;
            rCol <= 9'd0;
            rRow <= 9'd0;
            oCol <= 9'd0;
            oRow <= 9'd0;
            rCycleCount <= 5'd0;
            rReadIdx <= 4'd0;
            oValid <= 1'b0;
            oDone <= 1'b0;
            
            for (i = 0; i < 9; i = i + 1) begin
                rReadBuf[i] <= 16'd0;          // 변경: 24'd0 → 16'd0
            end
            
        end else begin
            case (rCurState)
            
                S_IDLE: begin
                    rRow <= 9'd0;
                    // rCol <= 9'd0;              // ← 추가: 초기화
                    rCycleCount <= 5'd0;
                    rReadIdx <= 4'd0;
                    oValid <= 1'b0;
                    oDone <= 1'b0;
                end
                
                //=========================================================
                // 주소 설정 전용
                //=========================================================       
                S_ADDR_SETUP: begin
                    oValid <= 1'b0;
                    // 현재 (rRow, rCol)의 top-left 주소 설정
                    if (rRow == 0 || rCol == 0) begin
                        rBramAddr <= 17'd0;  // padding
                    end else begin
                        rBramAddr <= (rRow - 1) * WIDTH + (rCol - 1);
                    end
                    rBramEn <= 1'b1;
                    rCycleCount <= 5'd0;
                    rReadIdx <= 4'd0;
                end    
                
                
                //=========================================================
                // 9개 윈도우 읽기
                // Cycle 0,1: 대기 (BRAM latency)
                // Cycle 2: 데이터 저장 + 다음 주소 설정
                //=========================================================
                S_LOAD_WINDOW: begin
                    rCycleCount <= rCycleCount + 1'b1;

                    case (rCycleCount % 3)
                        2'd0: begin
                            // Cycle 0: 대기
                            rBramEn <= 1'b1;
                        end
                        
                        2'd1: begin
                            // Cycle 1: BRAM latency 대기
                            rBramEn <= 1'b1;
                        end
                        
                        2'd2: begin
                            // Cycle 2: 데이터 저장 + 다음 주소 설정
                            
                            // 현재 데이터 저장 (RGB565)
                            if (rRow == 0 && rReadIdx < 4'd3) begin
                                rReadBuf[rReadIdx] <= 16'd0;   // 변경: 24'd0 → 16'd0
                            end else if (rCol == 0 && (rReadIdx == 4'd0 || rReadIdx == 4'd3 || rReadIdx == 4'd6)) begin
                                rReadBuf[rReadIdx] <= 16'd0;
                            end else if (rCol + 1 >= WIDTH && (rReadIdx == 4'd2 || rReadIdx == 4'd5 || rReadIdx == 4'd8)) begin
                                rReadBuf[rReadIdx] <= 16'd0;
                            end else if (rRow + 1 >= HEIGHT && rReadIdx >= 4'd6) begin
                                rReadBuf[rReadIdx] <= 16'd0;
                            end else begin
                                rReadBuf[rReadIdx] <= wBramData;  // RGB565
                            end
                            
                            rReadIdx <= rReadIdx + 1'b1;
                            
                            // 다음 주소 설정 (rReadIdx 기준, 다음은 rReadIdx+1)
                            case (rReadIdx)
                                4'd0: begin  // 다음: idx 1 (top-center)
                                    if (rRow == 0) begin
                                        rBramAddr <= 17'd0;
                                    end else begin
                                        rBramAddr <= (rRow - 1) * WIDTH + rCol;
                                    end
                                    rBramEn <= 1'b1;
                                end
                                4'd1: begin  // 다음: idx 2 (top-right)
                                    if (rRow == 0 || rCol + 1 >= WIDTH) begin
                                        rBramAddr <= 17'd0;
                                    end else begin
                                        rBramAddr <= (rRow - 1) * WIDTH + (rCol + 1);
                                    end
                                    rBramEn <= 1'b1;
                                end
                                4'd2: begin  // 다음: idx 3 (middle-left)
                                    if (rCol == 0) begin
                                        rBramAddr <= 17'd0;
                                    end else begin
                                        rBramAddr <= rRow * WIDTH + (rCol - 1);
                                    end
                                    rBramEn <= 1'b1;
                                end
                                4'd3: begin  // 다음: idx 4 (middle-center)
                                    rBramAddr <= rRow * WIDTH + rCol;
                                    rBramEn <= 1'b1;
                                end
                                4'd4: begin  // 다음: idx 5 (middle-right)
                                    if (rCol + 1 >= WIDTH) begin
                                        rBramAddr <= 17'd0;
                                    end else begin
                                        rBramAddr <= rRow * WIDTH + (rCol + 1);
                                    end
                                    rBramEn <= 1'b1;
                                end
                                4'd5: begin  // 다음: idx 6 (bottom-left)
                                    if (rRow + 1 >= HEIGHT || rCol == 0) begin
                                        rBramAddr <= 17'd0;
                                    end else begin
                                        rBramAddr <= (rRow + 1) * WIDTH + (rCol - 1);
                                    end
                                    rBramEn <= 1'b1;
                                end
                                4'd6: begin  // 다음: idx 7 (bottom-center)
                                    if (rRow + 1 >= HEIGHT) begin
                                        rBramAddr <= 17'd0;
                                    end else begin
                                        rBramAddr <= (rRow + 1) * WIDTH + rCol;
                                    end
                                    rBramEn <= 1'b1;
                                end
                                4'd7: begin  // 다음: idx 8 (bottom-right)
                                    if (rRow + 1 >= HEIGHT || rCol + 1 >= WIDTH) begin
                                        rBramAddr <= 17'd0;
                                    end else begin
                                        rBramAddr <= (rRow + 1) * WIDTH + (rCol + 1);
                                    end
                                    rBramEn <= 1'b1;
                                end
                                4'd8: begin  // 마지막, 더 이상 읽을 주소 없음
                                    rBramEn <= 1'b0;
                                end
                            endcase
                        end
                    endcase

                    //=========================================================
                    // 윈도우 레지스터에 복사
                    //=========================================================
                    if (rCycleCount == 5'd27) begin
                        // 마지막 사이클: Window 복사
                        for (i = 0; i < 9; i = i + 1) begin
                            rWindow[i] <= rReadBuf[i];
                        end
                        rReadIdx <= 4'd0;
                        rCycleCount <= 5'd0;
                    end
                end
                
                //=========================================================
                // 윈도우 출력 (RGB565)
                //=========================================================
                S_OUTPUT: begin
                
                    // 현재 윈도우 출력 (RGB565)
                    oPix00 <= rWindow[0];
                    oPix01 <= rWindow[1];
                    oPix02 <= rWindow[2];
                    oPix10 <= rWindow[3];
                    oPix11 <= rWindow[4];
                    oPix12 <= rWindow[5];
                    oPix20 <= rWindow[6];
                    oPix21 <= rWindow[7];
                    oPix22 <= rWindow[8];
                    oValid <= 1'b1;
                    oRow <= rRow;      
                    oCol <= rCol;
                    
                    
                    if (!is_last_col) begin
                        // 가로 이동
                        rCol <= rCol + 1'b1;
                        rCycleCount <= 5'd0;
                        rReadIdx <= 4'd0;
                        
                        // 다음 윈도우 첫 주소 설정 (top-right of next window)
                        if (rRow == 0 || rCol + 2 >= WIDTH) begin
                            rBramAddr <= 17'd0;
                        end else begin
                            rBramAddr <= (rRow - 1) * WIDTH + (rCol + 2);
                        end
                        rBramEn <= 1'b1;
                        
                    end else begin
                        // 행 끝
                        
                        if (!is_last_row) begin
                            // 다음 행 준비
                            rRow <= rRow + 1'b1;
                            rCol <= 9'd0;
                            rCycleCount <= 5'd0;
                            rReadIdx <= 4'd0;
                            // 주소 설정은 S_ADDR_SETUP에서!
                        end
                    end
                end
                
                //=========================================================
                // 3개 픽셀 읽기 & Shift (RGB565)
                //=========================================================
                S_SHIFT: begin
                    oValid <= 1'b0;
                    case (rCycleCount % 3)
                        2'd0: begin
                            // Cycle 0: 대기
                            rBramEn <= 1'b1;
                        end
                        
                        2'd1: begin
                            // Cycle 1: BRAM latency
                            rBramEn <= 1'b1;
                        end
                        
                        2'd2: begin
                            // Cycle 2: 데이터 저장 + shift + 다음 주소
                            
                            if (rReadIdx == 4'd0) begin
                                // Shift left
                                rWindow[0] <= rWindow[1];
                                rWindow[1] <= rWindow[2];
                                rWindow[3] <= rWindow[4];
                                rWindow[4] <= rWindow[5];
                                rWindow[6] <= rWindow[7];
                                rWindow[7] <= rWindow[8];
                                
                                // New top-right (RGB565)
                                if (rRow == 0 || rCol + 1 >= WIDTH) begin
                                    rWindow[2] <= 16'd0;   // 변경: 24'd0 → 16'd0
                                end else begin
                                    rWindow[2] <= wBramData;
                                end
                                
                                // 다음 주소: middle-right
                                if (rCol + 1 >= WIDTH) begin
                                    rBramAddr <= 17'd0;
                                end else begin
                                    rBramAddr <= rRow * WIDTH + (rCol + 1);
                                end
                                rBramEn <= 1'b1;
                                
                            end else if (rReadIdx == 4'd1) begin
                                // New middle-right (RGB565)
                                if (rCol + 1 >= WIDTH) begin
                                    rWindow[5] <= 16'd0;
                                end else begin
                                    rWindow[5] <= wBramData;
                                end
                                
                                // 다음 주소: bottom-right
                                if (rRow + 1 >= HEIGHT || rCol + 1 >= WIDTH) begin
                                    rBramAddr <= 17'd0;
                                end else begin
                                    rBramAddr <= (rRow + 1) * WIDTH + (rCol + 1);
                                end
                                rBramEn <= 1'b1;
                                
                            end else if (rReadIdx == 4'd2) begin
                                // New bottom-right (RGB565)
                                if (rRow + 1 >= HEIGHT || rCol + 1 >= WIDTH) begin
                                    rWindow[8] <= 16'd0;
                                end else begin
                                    rWindow[8] <= wBramData;
                                end
                                
                                rBramEn <= 1'b0;
                            end
                            
                            rReadIdx <= rReadIdx + 1'b1;
                        end
                    endcase
                    
                    rCycleCount <= rCycleCount + 1'b1;
                    
                    if (rCycleCount == 5'd8) begin
                        rCycleCount <= 5'd0;
                        rReadIdx <= 4'd0;
                    end
                end
                
                //=========================================================
                // 완료
                //=========================================================
                S_DONE: begin
                    oValid <= 1'b0;
                    oDone <= 1'b1;
                    rBramEn <= 1'b0;
                end
                
                default: begin
                end
            endcase
        end
    end

endmodule