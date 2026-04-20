//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12.02 (64-bit)
//IP Version: 1.0
//Part Number: GW2A-LV18PG256C8/I7
//Device: GW2A-18
//Device Version: C
//Created Time: Sun Apr 19 23:01:53 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    Gowin_DP_4Kx32b your_instance_name(
        .douta(douta), //output [31:0] douta
        .doutb(doutb), //output [31:0] doutb
        .clka(clka), //input clka
        .ocea(ocea), //input ocea
        .cea(cea), //input cea
        .reseta(reseta), //input reseta
        .wrea(wrea), //input wrea
        .clkb(clkb), //input clkb
        .oceb(oceb), //input oceb
        .ceb(ceb), //input ceb
        .resetb(resetb), //input resetb
        .wreb(wreb), //input wreb
        .ada(ada), //input [11:0] ada
        .dina(dina), //input [31:0] dina
        .adb(adb), //input [11:0] adb
        .dinb(dinb) //input [31:0] dinb
    );

//--------Copy end-------------------
