#include <stdio.h>
#include <stdlib.h>  // atoi() 사용
#include <string.h>  // strtok(), strncpy() 사용
#include "source_code.h"
#include "xil_printf.h"
#include "xil_io.h"
#include <xparameters.h>
#include "xil_cache.h"
#include "sleep.h"
#include "xiic.h"
#include "CamConfigData.h"

/*    For UART Config start    */
#ifdef STDOUT_IS_16550
 #include "xuartns550_l.h"
 #define UART_BAUD 9600
#endif

void enable_caches()
{
#ifdef __PPC__
    Xil_ICacheEnableRegion(CACHEABLE_REGION_MASK);
    Xil_DCacheEnableRegion(CACHEABLE_REGION_MASK);
#elif __MICROBLAZE__
#ifdef XPAR_MICROBLAZE_USE_ICACHE
    Xil_ICacheEnable();
#endif
#ifdef XPAR_MICROBLAZE_USE_DCACHE
    Xil_DCacheEnable();
#endif
#endif
}

void disable_caches()
{
#ifdef __MICROBLAZE__
#ifdef XPAR_MICROBLAZE_USE_DCACHE
    Xil_DCacheDisable();
#endif
#ifdef XPAR_MICROBLAZE_USE_ICACHE
    Xil_ICacheDisable();
#endif
#endif
}

void init_uart()
{
#ifdef STDOUT_IS_16550
    XUartNs550_SetBaud(STDOUT_BASEADDR, XPAR_XUARTNS550_CLOCK_HZ, UART_BAUD);
    XUartNs550_SetLineControlReg(STDOUT_BASEADDR, XUN_LCR_8_DATA_BITS);
#endif
}

void init_platform()
{
    enable_caches();
    init_uart();
}

void cleanup_platform()
{
    disable_caches();
}
/*    For UART Config end    */

// ============================================================================
// Hardware Address Definitions
// ============================================================================

#define AXI_IIC_ADDRESS        0xA0010000
#define AXI_GPIO_ADDRESS       0xA0000000
#define AXI_LITE_CNN_BASEADDR  0xA0020000  // CNN Filter Control

// ============================================================================
// Camera (OV5640) Configuration
// ============================================================================

#define IIC_DEVICE_ID      0
#define OV5640_IIC_ADDR    0x78  // 8bit: 0x78=Write, 0x79=Read → 7bit: 0x3C

XIic Iic;

/**
 * SCCB Write Register (16bit Address + 8bit Data)
 */
int SCCB_WriteRegister(u16 reg, u8 data) {
    u8 buf[3];
    int Status;
    //int BytesSent;

    buf[0] = (reg >> 8) & 0xFF;  // High byte
    buf[1] = reg & 0xFF;         // Low byte
    buf[2] = data;

    Status = XIic_Send(AXI_IIC_ADDRESS, OV5640_IIC_ADDR >> 1, buf, 3, XIIC_STOP);
    if (Status != 3) {
        printf("SCCB Write Error: reg=0x%04X, data=0x%02X, Status=%d\r\n", reg, data, Status);
        return XST_FAILURE;
    }

    // // Interrupt Mode 사용
    // BytesSent = XIic_MasterSend(&Iic, buf, 3);
    
    // if (BytesSent != 3) {
    //     printf("SCCB Error: reg=0x%04X, sent=%d\r\n", reg, BytesSent);
    //     return XST_FAILURE;
    // }

    while (XIic_IsIicBusy(AXI_IIC_ADDRESS));
    return XST_SUCCESS;
}

/**
 * OV5640 Full Initialization Sequence
 */
int Initialize_OV5640() {
    int status;
    extern const iic_ov5640_t Config[];

    int num_regs = sizeof(Config) / sizeof(Config[0]);
    
    printf("Starting OV5640 initialization...\r\n");
    
    for (int i = 0; i < num_regs; i++) {
        status = SCCB_WriteRegister(Config[i].RegOffset, Config[i].RegData);
        if (status != XST_SUCCESS) {
            printf("Failed at index %d, Reg=0x%04X\r\n", i, Config[i].RegOffset);
            return status;
        }
    }

    printf("OV5640 Initialization complete. %d registers written.\r\n", num_regs);
    return XST_SUCCESS;
}

/**
 * Initialize Camera Hardware (Reset & Power)
 */
int Initialize_Camera_Hardware() {
    printf("Initializing camera hardware...\r\n");
    
    // PWDN=1, RESETn=0
    *(volatile unsigned int*)(AXI_GPIO_ADDRESS) = 0x2;
    usleep(1000);  // 1ms delay
    
    // PWDN=0, RESETn=1 (Release reset)
    *(volatile unsigned int*)(AXI_GPIO_ADDRESS) = 0x1;
    usleep(20000);  // 20ms delay for stabilization
    
    printf("Camera hardware initialized.\r\n");
    return XST_SUCCESS;
}

/**
 * Initialize IIC (I2C) Interface
 */
int Initialize_IIC() {
    XIic_Config *IicConfig;
    int Status;

    printf("Initializing IIC interface...\r\n");

    IicConfig = XIic_LookupConfig(IIC_DEVICE_ID);
    if (IicConfig == NULL) {
        printf("IIC configuration not found!\r\n");
        return XST_FAILURE;
    }

    Status = XIic_CfgInitialize(&Iic, IicConfig, IicConfig->BaseAddress);
    if (Status != XST_SUCCESS) {
        printf("IIC initialization failed!\r\n");
        return XST_FAILURE;
    }

    XIic_Start(&Iic);
    XIic_SetAddress(&Iic, XII_ADDR_TO_SEND_TYPE, OV5640_IIC_ADDR >> 1);
    
    printf("IIC interface initialized.\r\n");
    return XST_SUCCESS;
}

// int Initialize_IIC() {
//     XIic_Config *IicConfig;
//     int Status;

//     printf("Initializing IIC interface...\r\n");

//     // 1. Config 찾기
//     IicConfig = XIic_LookupConfig(IIC_DEVICE_ID);
//     if (IicConfig == NULL) {
//         printf("IIC configuration not found!\r\n");
//         return XST_FAILURE;
//     }

//     printf("IIC Base Address: 0x%08X\r\n", IicConfig->BaseAddress);
//     printf("Expected Address: 0x%08X\r\n", AXI_IIC_ADDRESS);
    
//     // 주소 확인
//     if (IicConfig->BaseAddress != AXI_IIC_ADDRESS) {
//         printf("Address mismatch!\r\n");
//         return XST_FAILURE;
//     }

//     // 2. 초기화
//     Status = XIic_CfgInitialize(&Iic, IicConfig, IicConfig->BaseAddress);
//     if (Status != XST_SUCCESS) {
//         printf("IIC CfgInitialize failed! Status=%d\r\n", Status);
//         return XST_FAILURE;
//     }

//     // 3. IIC 시작
//     Status = XIic_Start(&Iic);
//     if (Status != XST_SUCCESS) {
//         printf("IIC Start failed! Status=%d\r\n", Status);
//         return XST_FAILURE;
//     }
//     printf("IIC Started successfully.\r\n");

//     // 4. Slave 주소 설정
//     Status = XIic_SetAddress(&Iic, XII_ADDR_TO_SEND_TYPE, OV5640_IIC_ADDR >> 1);
//     if (Status != XST_SUCCESS) {
//         printf("IIC SetAddress failed! Status=%d\r\n", Status);
//         return XST_FAILURE;
//     }
//     printf("Slave address set to: 0x%02X\r\n", OV5640_IIC_ADDR >> 1);
    
//     // 5. 상태 확인
//     u32 cr_reg = Xil_In32(AXI_IIC_ADDRESS + 0x100);  // CR 레지스터
//     printf("IIC Control Reg: 0x%08X\r\n", cr_reg);
    
//     printf("IIC interface initialized.\r\n");
//     return XST_SUCCESS;
// }

// ============================================================================
// CNN Filter Control
// ============================================================================

// Filter Mode Definitions
#define FILTER_SHARPEN         0x0  // 3'b000
#define FILTER_EDGE_ENHANCE    0x1  // 3'b001
#define FILTER_BYPASS          0x2  // 3'b010
#define FILTER_CUSTOM          0x3  // 3'b011 

// Register offset for CNN filter control
#define REG0_OFFSET            0x0  // Filter mode (3-bit)

#define REG1_OFFSET            0x4   // Custom K0
#define REG2_OFFSET            0x8   // Custom K1
#define REG3_OFFSET            0xC   // Custom K2
#define REG4_OFFSET            0x10  // Custom K3
#define REG5_OFFSET            0x14  // Custom K4
#define REG6_OFFSET            0x18  // Custom K5
#define REG7_OFFSET            0x1C  // Custom K6
#define REG8_OFFSET            0x20  // Custom K7
#define REG9_OFFSET            0x24  // Custom K8

/**
 * Set CNN filter mode
 */
void set_filter_mode(unsigned int mode)
{
    // Write to AXI-Lite register
    *(volatile unsigned int*)(AXI_LITE_CNN_BASEADDR + REG0_OFFSET) = (mode & 0x7);
    
    printf("Filter mode set to: 0x%X\n\r", mode & 0x7);
    usleep(1000);  // Small delay for propagation
}

/**
 * Get current filter mode
 */
unsigned int get_filter_mode(void)
{
    unsigned int value = *(volatile unsigned int*)(AXI_LITE_CNN_BASEADDR + REG0_OFFSET);
    return (value & 0x7);
}

/**
 * Set custom filter kernel
 */
void set_custom_kernel(int kernel[9])
{
    *(volatile int*)(AXI_LITE_CNN_BASEADDR + REG1_OFFSET) = kernel[0];
    *(volatile int*)(AXI_LITE_CNN_BASEADDR + REG2_OFFSET) = kernel[1];
    *(volatile int*)(AXI_LITE_CNN_BASEADDR + REG3_OFFSET) = kernel[2];
    *(volatile int*)(AXI_LITE_CNN_BASEADDR + REG4_OFFSET) = kernel[3];
    *(volatile int*)(AXI_LITE_CNN_BASEADDR + REG5_OFFSET) = kernel[4];
    *(volatile int*)(AXI_LITE_CNN_BASEADDR + REG6_OFFSET) = kernel[5];
    *(volatile int*)(AXI_LITE_CNN_BASEADDR + REG7_OFFSET) = kernel[6];
    *(volatile int*)(AXI_LITE_CNN_BASEADDR + REG8_OFFSET) = kernel[7];
    *(volatile int*)(AXI_LITE_CNN_BASEADDR + REG9_OFFSET) = kernel[8];
    
    printf("Custom kernel coefficients set:\r\n");
    printf("  [%3d %3d %3d]\r\n", kernel[0], kernel[1], kernel[2]);
    printf("  [%3d %3d %3d]\r\n", kernel[3], kernel[4], kernel[5]);
    printf("  [%3d %3d %3d]\r\n", kernel[6], kernel[7], kernel[8]);
}

/**
 * Input custom kernel one by one
 */
int input_custom_kernel(int kernel[9])
{
    char input[32];
    int value;
    
    printf("\r\nEnter 9 kernel coefficients (one at a time):\r\n");
    printf("Examples: Sharpen [0,-1,0,-1,5,-1,0,-1,0]\r\n");
    printf("          Edge    [-1,-1,-1,-1,8,-1,-1,-1,-1]\r\n\r\n");
    
    const char* positions[9] = {
        "Top-Left    ", "Top-Center  ", "Top-Right   ",
        "Middle-Left ", "Center      ", "Middle-Right",
        "Bottom-Left ", "Bottom-Center", "Bottom-Right"
    };
    
    for(int i = 0; i < 9; i++) {
        printf("K[%d] (%s): ", i, positions[i]);
        scanf("%s", input);
        value = atoi(input);
        kernel[i] = value;
        printf("  -> %d\r\n", value);
    }
    
    return XST_SUCCESS;
}

/**
 * Print filter menu
 */
void print_filter_menu(void)
{
    printf("-------------------------------------------\r\n");
    printf("CNN Image Filter Controller\r\n");
    printf("-------------------------------------------\r\n");
    printf("Select Filter Mode:\r\n");
    printf("  [0] Sharpen Filter\r\n");
    printf("  [1] Edge Enhance Filter\r\n");
    printf("  [2] Bypass (Original Image)\r\n");
    printf("  [3] Custom Filter (enter 9 coefficients)\r\n");
    printf("  [r] Read Current Mode\r\n");
    printf("  [q] Quit\r\n");
    printf("-------------------------------------------\r\n");
    printf("Enter your choice: ");
}

// ============================================================================
// Main Function
// ============================================================================

int main()
{
    char input[32];
    unsigned int current_mode;
    int Status;

    init_platform();
    
    printf("\r\n");
    printf("===========================================\r\n");
    printf("  Camera + CNN Filter System\r\n");
    printf("  with Custom Filter Support\r\n");
    printf("===========================================\r\n");
    printf("\r\n");
    
    // ========================================
    // Step 1: Initialize Camera Hardware
    // ========================================
    Status = Initialize_Camera_Hardware();
    if (Status != XST_SUCCESS) {
        printf("Camera hardware initialization failed!\r\n");
        return XST_FAILURE;
    }
    
    // ========================================
    // Step 2: Initialize IIC Interface
    // ========================================
    Status = Initialize_IIC();
    if (Status != XST_SUCCESS) {
        printf("IIC initialization failed!\r\n");
        return XST_FAILURE;
    }
    
    // ========================================
    // Step 3: Configure OV5640 Camera
    // ========================================
    Status = Initialize_OV5640();
    if (Status != XST_SUCCESS) {
        printf("OV5640 configuration failed!\r\n");
        XIic_Stop(&Iic);
        return XST_FAILURE;
    }
    
    XIic_Stop(&Iic);
    printf("\r\n");
    printf("Camera initialization complete!\r\n");
    printf("\r\n");
    
    // ========================================
    // Step 4: Set Initial Filter Mode
    // ========================================
    set_filter_mode(FILTER_EDGE_ENHANCE);  // Start with bypass mode
    current_mode = get_filter_mode();
    printf("Initial Filter Mode: 0x%X (EDGE_ENHANCE)\r\n", current_mode);
    printf("\r\n");

    // ========================================
    // Step 5: Interactive Filter Control Loop
    // ========================================
    printf("System ready! Starting filter control interface...\r\n");
    printf("\r\n");
    
    while(1) {
        print_filter_menu();
        
        // Get user input
        scanf("%s", input);
        printf("%s\r\n", input);
        
        // Process command
        switch(input[0]) {
            case '0':
                printf("Setting filter to: SHARPEN\r\n");
                set_filter_mode(FILTER_SHARPEN);
                break;
                
            case '1':
                printf("Setting filter to: EDGE ENHANCE\r\n");
                set_filter_mode(FILTER_EDGE_ENHANCE);
                break;
                
            case '2':
                printf("Setting filter to: BYPASS (Original)\r\n");
                set_filter_mode(FILTER_BYPASS);
                break;
            
            case '3':
            {
                int kernel[9];
                if (input_custom_kernel(kernel) == XST_SUCCESS) {
                    set_custom_kernel(kernel);
                    set_filter_mode(FILTER_CUSTOM);
                    printf("\r\nCustom filter applied!\r\n");
                }
                break;
            }

            case 'r':
            case 'R':
                current_mode = get_filter_mode();
                printf("Current Filter Mode: 0x%X\r\n", current_mode);
                switch(current_mode) {
                    case FILTER_SHARPEN:
                        printf("  -> SHARPEN\r\n");
                        break;
                    case FILTER_EDGE_ENHANCE:
                        printf("  -> EDGE ENHANCE\r\n");
                        break;
                    case FILTER_CUSTOM:
                        printf("  -> CUSTOM\r\n");
                        break;
                    default:
                        printf("  -> BYPASS\r\n");
                        break;
                }
                break;
                
            case 'q':
            case 'Q':
                printf("Exiting program...\r\n");
                cleanup_platform();
                return 0;
                
            default:
                printf("Invalid input! Please try again.\r\n");
                break;
        }
        
        printf("\r\n");
        usleep(100000);  // 100ms delay
    }

    cleanup_platform();
    return 0;
}