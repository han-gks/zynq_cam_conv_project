/**********************************************************************
  - Project          : 2025 Advanced project(~251117)
  - File name        : ConvReLU.v
  - Description      : Convolution + ReLU activation
  - Owner            : ByeongDo.Hwang
  - Revision history : 1) 2025.11.10 : Initial release
**********************************************************************/

// clk == 6.25MHz
// 100MGz iClk -> 6.25MHz wEnClk
// Button push == 0 , release == 1
// zero padding @ 3x3window module


`timescale 1ns/10ps

module PixelConversion (

  // Clock & reset
  input                 iClk,          // Rising edge
  input                 iRsn,          // Sync. & low reset

  input                 iVal,          // Valid signal
  input  [16:0]         iAddr,         // Address (0 ~ 130559)
  input  [23:0]         iRgb888,       // RGB888 format


  output                oCsnA,         // Chip select (active low)
  output [16:0]         oAddrA,        // Write address
  output [15:0]         oRgb565        // RGB565 format
  
  //output                oDone          // Frame conversion done
  
  
);



  // wire & reg declaration      

  reg    [4:0]          rR5;
  reg    [5:0]          rG6;
  reg    [4:0]          rB5;

  reg                   rCsn;
  reg    [16:0]         rAddr;
  //reg                   rDone;
  
  // Frame completion detection
  parameter LAST_ADDR = 17'd130559;  // 480×272 - 1


  always @(posedge iClk) begin
    if(!iRsn) begin
        rR5   <= 5'd0;
        rG6   <= 6'd0;
        rB5   <= 5'd0;
        rAddr <= 17'd0;
        rCsn  <= 1'b1;
        //rDone <= 1'b0;
    end else if( iVal ) begin
        
        // RGB888 → RGB565 conversion
        rR5   <= iRgb888[23:19];
        rG6   <= iRgb888[15:10];
        rB5   <= iRgb888[7:3];
        rAddr <= iAddr;
        rCsn  <= 0;             // Enable write
    end
    else begin
        rCsn  <= 1;             // Disable write
    end
  end



  /************************************************************
  // Conversion
  ************************************************************/

  assign oCsnA   = rCsn;
  assign oRgb565 = {rR5, rG6, rB5};
  assign oAddrA  = rAddr;
  

endmodule
