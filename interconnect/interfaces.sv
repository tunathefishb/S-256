`timescale 1ns/1ps

interface ring_bus_if (input logic clk);
    logic [255:0] data;
    logic valid;
    logic ready;
    modport master(output data, valid, input ready);
    modport slave(input data, valid, output ready);
endinterface

interface comms_bus_if (input logic clk);
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic        wen;
    logic        ren;
    logic        valid;
    logic        ready;
    logic [1:0]  resp;
    logic [31:0] cmd; // Legacy compatibility

    modport master (
        input  clk,
        output addr,
        output wdata,
        output wen,
        output ren,
        output valid,
        output cmd,
        input  ready,
        input  rdata,
        input  resp
    );

    modport slave (
        input  clk,
        input  addr,
        input  wdata,
        input  wen,
        input  ren,
        input  valid,
        input  cmd,
        output ready,
        output rdata,
        output resp
    );
endinterface
