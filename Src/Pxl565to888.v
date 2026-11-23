`timescale 1ns/10ps

module Pxl565to888 (

  // Clock & reset
  input                 iClk,          // Rising edge
  input                 iRsn,          // Sync. & low reset

  input                 iValid,          
  input  [8:0]          iRow,        
  input  [8:0]          iCol,

  input  [15:0]         i565Pixel0,
  input  [15:0]         i565Pixel1,  
  input  [15:0]         i565Pixel2,
  input  [15:0]         i565Pixel3,
  input  [15:0]         i565Pixel4,
  input  [15:0]         i565Pixel5,
  input  [15:0]         i565Pixel6,
  input  [15:0]         i565Pixel7,
  input  [15:0]         i565Pixel8,


  output                oValid,         
  output [8:0]          oRow,         
  output [8:0]          oCol,

  output [23:0]         o888Pixel0,
  output [23:0]         o888Pixel1,         
  output [23:0]         o888Pixel2,  
  output [23:0]         o888Pixel3,  
  output [23:0]         o888Pixel4,  
  output [23:0]         o888Pixel5,  
  output [23:0]         o888Pixel6,  
  output [23:0]         o888Pixel7,  
  output [23:0]         o888Pixel8 
  
  
);

  // wire & reg declaration      
  reg                   rValid;
  reg    [8:0]          rRow;
  reg    [8:0]          rCol;
  reg    [23:0]         r888Pixel[0:8];
  
  integer i;


  always @(posedge iClk) begin
    if(!iRsn) begin
        rValid <= 0;                // 변경: rR5, rG6, rB5 → rData
        rRow   <= 9'b0;
        rCol   <= 9'b0;
        for(i=0; i<9; i=i+1) begin
            r888Pixel[i] <= 0;
        end
    end 
    else if( iValid ) begin
        rValid <= iValid;
        rRow   <= iRow;
        rCol   <= iCol;
        //R_8 = (R_5 << 3) | (R_5)
        //G_8 = (G_6 << 2) | (G_)
        //B_8 = (B_5 << 3) | (B_5)

        r888Pixel[0] <= {i565Pixel0[15:11], i565Pixel0[15:13],
                         i565Pixel0[10:5],  i565Pixel0[10:9],
                         i565Pixel0[4:0],  i565Pixel0[4:2]};

        r888Pixel[1] <= {i565Pixel1[15:11], i565Pixel1[15:13],
                         i565Pixel1[10:5], i565Pixel1[10:9],
                         i565Pixel1[4:0]   , i565Pixel1[4:2]};
        
        r888Pixel[2] <= {i565Pixel2[15:11], i565Pixel2[15:13],
                         i565Pixel2[10:5], i565Pixel2[10:9],
                         i565Pixel2[4:0], i565Pixel2[4:2]};
        
        r888Pixel[3] <= {i565Pixel3[15:11], i565Pixel3[15:13],
                         i565Pixel3[10:5], i565Pixel3[10:9],
                         i565Pixel3[4:0], i565Pixel3[4:2]  };
        
        r888Pixel[4] <= {i565Pixel4[15:11], i565Pixel4[15:13],
                         i565Pixel4[10:5], i565Pixel4[10:9],
                         i565Pixel4[4:0], i565Pixel4[4:2]  };
        
        r888Pixel[5] <= {i565Pixel5[15:11], i565Pixel5[15:13],
                         i565Pixel5[10:5], i565Pixel5[10:9],
                         i565Pixel5[4:0], i565Pixel5[4:2]  };

        r888Pixel[6] <= {i565Pixel6[15:11], i565Pixel6[15:13],
                         i565Pixel6[10:5], i565Pixel6[10:9],
                         i565Pixel6[4:0], i565Pixel6[4:2]  };

        r888Pixel[7] <= {i565Pixel7[15:11], i565Pixel7[15:13],
                         i565Pixel7[10:5], i565Pixel7[10:9],
                         i565Pixel7[4:0], i565Pixel7[4:2]  };

        r888Pixel[8] <= {i565Pixel8[15:11], i565Pixel8[15:13],
                         i565Pixel8[10:5], i565Pixel8[10:9],
                         i565Pixel8[4:0], i565Pixel8[4:2]  };
    end
  end



  /************************************************************
  // Output Assignment
  ************************************************************/

  assign oValid      = rValid;
  assign oRow        = rRow;              
  assign oCol        = rCol;
  assign o888Pixel0  = r888Pixel[0];
  assign o888Pixel1  = r888Pixel[1];
  assign o888Pixel2  = r888Pixel[2];
  assign o888Pixel3  = r888Pixel[3];
  assign o888Pixel4  = r888Pixel[4];
  assign o888Pixel5  = r888Pixel[5];
  assign o888Pixel6  = r888Pixel[6];
  assign o888Pixel7  = r888Pixel[7];
  assign o888Pixel8  = r888Pixel[8];
  

endmodule