/******************************************************************************
* Copyright (C) 2023 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/

#ifndef __PLATFORM_H_
#define __PLATFORM_H_

#ifndef SDT
#include "source_code.h"
#endif

// ============================================================================
// Platform Initialization Functions
// ============================================================================
void init_platform();
void cleanup_platform();

// // ============================================================================
// // Camera Hardware Control Functions
// // ============================================================================
// int Initialize_Camera_Hardware(void);
// int Initialize_IIC(void);
// int Initialize_OV5640(void);

// // ============================================================================
// // SCCB (I2C) Communication Functions
// // ============================================================================
// int SCCB_WriteRegister(u16 reg, u8 data);

// CNN Filter Control Functions
void set_filter_mode(unsigned int mode);
unsigned int get_filter_mode(void);
void print_filter_menu(void);

// Custom filter functions
void set_custom_kernel(int kernel[9]);
int input_custom_kernel(int kernel[9]);

#endif
