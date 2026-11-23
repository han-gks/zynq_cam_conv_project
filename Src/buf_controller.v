`timescale 1ns / 10ps

module buf_controller(
    // 시스템 클럭
    input wire          clk_100mhz,         // 100MHz (Conv 도메인)
    input wire          clk_pclk,           // CAMERA_PCLK (~24MHz) ← 추가
    input wire          rst_n,
    
    // 카메라 신호 (PCLK 도메인) - 동기화 제거
    input wire          cam_frame_done,     // camera_to_ram의 frame_done_o
    input wire          cam_wr_en_req,      // camera_to_ram의 ram_wr_en_o
    input wire [16:0]   cam_wr_addr,        // camera_to_ram의 ram_wr_addr_o (직접 연결)
    input wire [15:0]   cam_wr_data,        // camera_to_ram의 ram_wr_data_o (직접 연결)
    
    // InBuf 인터페이스 (100MHz 도메인)
    input wire [16:0]   conv_rd_addr,       // InBuf의 oRdAddr
    input wire          conv_rd_en,         // InBuf의 oRdEn
    output wire [15:0]  conv_rd_data,       // InBuf의 iRdData
    
    // Conv 제어
    input wire          tft_lcd_done,       // PixelConversion의 Done
    output reg          conv_start          // InBuf의 iStart
);

// =====================================================
// FSM States
// =====================================================
localparam S_IDLE           = 2'b00;
localparam S_CAM_WRITE_A    = 2'b01;    // Conv 끝남, 카메라 BufA 쓰는 중
localparam S_CAM_WRITE_B    = 2'b10;    // Conv 끝남, 카메라 BufB 쓰는 중
localparam S_WAIT_FRAME     = 2'b11;    // 카메라 끝남, Conv 읽는 중

reg [1:0] rCurState, rNxtState;

// =====================================================
// CDC: frame_done만 동기화 (단일 비트)
// 주소/데이터는 BRAM이 처리하므로 동기화 불필요!
// =====================================================

// Frame Done 동기화 (PCLK → 100MHz)
reg frame_done_sync1, frame_done_sync2;
//reg cam_wr_en_req_sync1, cam_wr_en_req_sync2;

wire frame_done_event;

always @(posedge clk_100mhz or negedge rst_n) begin
    if (!rst_n) begin
        frame_done_sync1  <= 1'b0;
        frame_done_sync2  <= 1'b0;

        //cam_wr_en_req_sync1 <= 1'b0;
        //cam_wr_en_req_sync2 <= 1'b0;

    end else begin
        frame_done_sync1  <= cam_frame_done;
        frame_done_sync2  <= frame_done_sync1;

        //cam_wr_en_req_sync1 <= cam_wr_en_req;
        //cam_wr_en_req_sync2 <= cam_wr_en_req_sync1;

    end
end

// Rising edge 감지 (0→1)
assign frame_done_event = frame_done_sync1 & ~frame_done_sync2;

// TFT LCD Done 레지스터
reg r_tft_lcd_done;

// =====================================================
// 제어 신호
// =====================================================
reg cam_buf_sel;       // 0=A, 1=B (카메라가 쓰는 버퍼)
reg conv_buf_sel;      // 0=A, 1=B (Conv가 읽는 버퍼)
reg cam_wr_enable;     // 카메라 Write 허용

// =====================================================
// FSM - Part 1: State Register
// =====================================================
always @(posedge clk_100mhz or negedge rst_n) begin
    if (!rst_n) begin
        rCurState <= S_IDLE;
    end else begin
        rCurState <= rNxtState;
    end
end

// Conv 버퍼 선택 + Start (상태 진입 감지)
reg [1:0] rCurState_d;

always @(posedge clk_100mhz) begin
    if (!rst_n) begin
        rCurState_d <= S_IDLE;
    end else begin
        rCurState_d <= rCurState;
    end
end

wire state_changed = (rCurState != rCurState_d);

// =====================================================
// FSM - Part 2: Next State Logic
// =====================================================
always @(*) begin
    rNxtState = rCurState;
    
    case (rCurState)
        S_IDLE: begin
            rNxtState = S_CAM_WRITE_A;
        end
        
        S_CAM_WRITE_A: begin
            // 카메라가 BufA에 쓰는 중, Conv는 BufB 읽는 중
            if (frame_done_event) begin
                rNxtState = S_WAIT_FRAME;
            end
        end
        
        S_CAM_WRITE_B: begin
            // 카메라가 BufB에 쓰는 중, Conv는 BufA 읽는 중
            if (frame_done_event) begin
                rNxtState = S_WAIT_FRAME;
            end
        end
        
        S_WAIT_FRAME: begin
            // 카메라 끝남, Conv 읽는 중
            // tft_lcd_done 기다림
            if (r_tft_lcd_done && frame_done_event) begin
                // Conv 끝남! 역할 교체
                if (cam_buf_sel == 1'b0) begin
                    // 카메라는 BufA에 썼음 → 다음엔 BufB에 쓰기
                    // Conv는 BufA 읽기 시작
                    rNxtState = S_CAM_WRITE_B;
                end else begin
                    // 카메라는 BufB에 썼음 → 다음엔 BufA에 쓰기
                    // Conv는 BufB 읽기 시작
                    rNxtState = S_CAM_WRITE_A;
                end
            end
        end
        
        default: begin
            rNxtState = S_IDLE;
        end
    endcase
end

// =====================================================
// FSM - Part 3: Output Logic
// =====================================================

// 카메라 버퍼 선택
always @(posedge clk_100mhz) begin
    if (!rst_n) begin
        cam_buf_sel <= 1'b0;
    end else begin
        case (rCurState)
            S_IDLE, S_CAM_WRITE_A: begin
                cam_buf_sel <= 1'b0;  // BufA
            end
            S_CAM_WRITE_B: begin
                cam_buf_sel <= 1'b1;  // BufB
            end
            S_WAIT_FRAME: begin
                // 버퍼 유지
                cam_buf_sel <= cam_buf_sel;
            end
        endcase
    end
end

// 카메라 Write Enable
always @(posedge clk_100mhz) begin
    if (!rst_n) begin
        cam_wr_enable <= 1'b0;
    end else begin
        case (rCurState)
            S_CAM_WRITE_A, S_CAM_WRITE_B: begin
                cam_wr_enable <= 1'b1;  // 쓰기 허용
            end
            S_WAIT_FRAME: begin
                cam_wr_enable <= 1'b0;  // 대기 중 쓰기 금지 (보호)
            end
            default: begin
                cam_wr_enable <= 1'b0;
            end
        endcase
    end
end


// Conv 버퍼 선택 + Start
always @(posedge clk_100mhz) begin
    if (!rst_n) begin
        conv_buf_sel <= 1'b1;
        conv_start <= 1'b0;
    end else begin
        case (rCurState)
            S_CAM_WRITE_A: begin
                // 카메라 BufA 쓰기 + Conv BufB 읽기
                if (state_changed && (rCurState_d != S_IDLE)) begin
                    conv_buf_sel <= 1'b1;  // BufB 읽기
                    conv_start <= 1'b1;    // 시작!
                end else begin
                    conv_start <= 1'b0;
                end
            end
            
            S_CAM_WRITE_B: begin
                // 카메라 BufB 쓰기 + Conv BufA 읽기
                if (state_changed) begin
                    conv_buf_sel <= 1'b0;  // BufA 읽기
                    conv_start <= 1'b1;
                end else begin
                    conv_start <= 1'b0;
                end
            end
            
            default: begin
                conv_start <= 1'b0;
            end
        endcase
    end
end

// TFT LCD Done 래치
always @(posedge clk_100mhz) begin
    if (!rst_n) begin
        r_tft_lcd_done <= 1'b0;
    end else if (tft_lcd_done) begin
        r_tft_lcd_done <= 1'b1;
    end else if (state_changed) begin
        r_tft_lcd_done <= 1'b0;
    end
end

// =====================================================
// BRAM 제어 신호 (간소화)
// True Dual Port BRAM 사용
// =====================================================

// Buffer A 제어
wire bufA_wr_en;    // Write Enable (PCLK 도메인)
wire bufA_rd_en;    // Read Enable (100MHz 도메인)

// Write: 카메라가 BufA를 선택했을 때만
assign bufA_wr_en = (cam_buf_sel == 1'b0) && cam_wr_enable && cam_wr_en_req;

// Read: Conv가 BufA를 선택했을 때만
assign bufA_rd_en = (conv_buf_sel == 1'b0) && conv_rd_en;

// Buffer B 제어
wire bufB_wr_en;    // Write Enable (PCLK 도메인)
wire bufB_rd_en;    // Read Enable (100MHz 도메인)

// Write: 카메라가 BufB를 선택했을 때만
assign bufB_wr_en = (cam_buf_sel == 1'b1) && cam_wr_enable && cam_wr_en_req;

// Read: Conv가 BufB를 선택했을 때만
assign bufB_rd_en = (conv_buf_sel == 1'b1) && conv_rd_en;

// Read Data MUX: Conv가 읽는 버퍼에서 데이터
wire [15:0] bufA_dout, bufB_dout;
assign conv_rd_data = (conv_buf_sel == 1'b0) ? bufA_dout : bufB_dout;

// =====================================================
// True Dual Port BRAM 인스턴스
// Port A: Write (PCLK 도메인)
// Port B: Read (100MHz 도메인)
// =====================================================

InputMemory_A u_BufA (
    // Write Port (PCLK 도메인) - 카메라 쓰기
    .clka   (clk_pclk),         // ← 변경: PCLK 사용
    .ena    (bufA_wr_en),       // Write Enable만 사용
    .wea    (bufA_wr_en),       // Write Enable
    .addra  (cam_wr_addr),      // ← 직접 연결 (동기화 불필요!)
    .dina   (cam_wr_data),      // ← 직접 연결 (동기화 불필요!)
    
    // Read Port (100MHz 도메인) - Conv 읽기
    .clkb   (clk_100mhz),
    .enb    (bufA_rd_en),
    .addrb  (conv_rd_addr),
    .doutb  (bufA_dout)
);

InputMemory_B u_BufB (
    // Write Port (PCLK 도메인) - 카메라 쓰기
    .clka   (clk_pclk),         // ← 변경: PCLK 사용
    .ena    (bufB_wr_en),
    .wea    (bufB_wr_en),
    .addra  (cam_wr_addr),      // ← 직접 연결 (동기화 불필요!)
    .dina   (cam_wr_data),      // ← 직접 연결 (동기화 불필요!)
    
    // Read Port (100MHz 도메인) - Conv 읽기
    .clkb   (clk_100mhz),
    .enb    (bufB_rd_en),
    .addrb  (conv_rd_addr),
    .doutb  (bufB_dout)
);

endmodule