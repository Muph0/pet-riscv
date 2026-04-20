//Copyright (C)2014-2026 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.12.02 (64-bit) 
//Created Time: 2026-04-20 18:29:30
create_clock -name ext_osc -period 37.037 -waveform {0 18.518} [get_ports {clk27}] -add
