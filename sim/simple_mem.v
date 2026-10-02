`timescale 1ns / 1ps



module simple_mem #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter LINE_WORDS = 4,
    parameter MEM_LINES  = 4096,   
    parameter LATENCY    = 10
)(
    input  wire clk,
    input  wire rst,
    input  wire mem_req_valid,
    input  wire mem_req_we,
    input  wire [ADDR_WIDTH-1:0] mem_req_addr,
    input  wire [LINE_WORDS*DATA_WIDTH-1:0] mem_req_wdata,
    input  wire [LINE_WORDS-1:0] mem_req_wstrb,
    output reg mem_req_ready,
    output reg mem_resp_valid,
    output reg  [LINE_WORDS*DATA_WIDTH-1:0] mem_resp_rdata
    );
    
    localparam BYTE_W = $clog2(DATA_WIDTH/8);
    localparam WOFF_W = $clog2(LINE_WORDS);
    localparam LINE_W = LINE_WORDS * DATA_WIDTH;
    localparam LIDX_W = $clog2(MEM_LINES);
    
    reg [LINE_W-1:0] mem [0:MEM_LINES-1];
    
    integer i, w;
    initial begin
        for (i = 0; i < MEM_LINES; i = i + 1)
            for (w = 0; w < LINE_WORDS; w = w + 1)
                mem[i][w*DATA_WIDTH +: DATA_WIDTH] = i*LINE_WORDS + w;
    end
    
    reg busy;
    reg [31:0] cnt;
    reg r_we;
    reg [LIDX_W-1: 0] r_line;
    reg [LINE_W-1: 0] r_wdata;
    reg [LINE_WORDS-1:0] r_wstrb;
    
    always @(posedge clk) begin
        mem_req_ready  <= 1'b0;    
        mem_resp_valid <= 1'b0;
        if (rst) begin
            busy <= 1'b0;
        end else if (!busy) begin
            if (mem_req_valid) begin
                busy    <= 1'b1;
                cnt     <= LATENCY;
                r_we    <= mem_req_we;
                r_line  <= mem_req_addr[BYTE_W+WOFF_W +: LIDX_W];
                r_wdata <= mem_req_wdata;
                r_wstrb <= mem_req_wstrb;
            end
        end else if (cnt != 0) begin
            cnt <= cnt - 1;
        end else begin
            busy          <= 1'b0;
            mem_req_ready <= 1'b1;
            if (r_we) begin
                for (w = 0; w < LINE_WORDS; w = w + 1)
                    if (r_wstrb[w])
                        mem[r_line][w*DATA_WIDTH +: DATA_WIDTH]
                            <= r_wdata[w*DATA_WIDTH +: DATA_WIDTH];
            end else begin
                mem_resp_valid <= 1'b1;
                mem_resp_rdata <= mem[r_line];
            end
        end
    end
endmodule
