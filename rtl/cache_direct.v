`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 30.08.2026 21:47:27
// Design Name: 
// Module Name: cache_direct
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module cache_direct #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter LINE_WORDS = 4,
    parameter NUM_SETS = 64,
    parameter CTR_WIDTH = 32,
    parameter NUM_WAYS = 4
)(
    input wire clk,
    input wire reset,
    
    input wire cpu_req_valid,
    input wire cpu_req_we,
    input wire  [ADDR_WIDTH-1: 0] cpu_req_addr,
    input wire  [DATA_WIDTH-1: 0] cpu_req_wdata,
    output wire cpu_req_ready,
    output wire cpu_resp_valid,
    output wire [DATA_WIDTH-1: 0] cpu_resp_rdata,
    
    
    output wire mem_req_valid,
    output wire mem_req_we,
    output wire [ADDR_WIDTH-1: 0] mem_req_addr,
    output wire [LINE_WORDS*DATA_WIDTH-1: 0] mem_req_wdata,
    output wire [LINE_WORDS-1: 0] mem_req_wstrb,
    input wire mem_req_ready,
    input wire mem_resp_valid,
    input wire [LINE_WORDS*DATA_WIDTH-1: 0] mem_resp_rdata,
    
    output reg [CTR_WIDTH-1: 0] load_hit_count,
    output reg [CTR_WIDTH-1: 0] load_miss_count,
    output reg [CTR_WIDTH-1: 0] store_hit_count,
    output reg [CTR_WIDTH-1: 0] store_miss_count

    );
    
    localparam BYTE_W = $clog2(DATA_WIDTH/8);
    localparam WOFF_W = $clog2(LINE_WORDS);
    localparam INDEX_W =  $clog2(NUM_SETS);
    localparam TAG_W =  ADDR_WIDTH - INDEX_W - WOFF_W - BYTE_W;
    localparam LINE_W = LINE_WORDS * DATA_WIDTH;
    localparam WAY_WIDTH = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1;
    
    localparam IDLE = 2'd0;
    localparam COMPARE = 2'd1;
    localparam ALLOCATE = 2'd2;
    localparam WRITE_MEM = 2'd3;
    
    reg [1:0] state, next_state;
    
    reg req_we;
    reg [ADDR_WIDTH-1:0] req_addr;
    reg [DATA_WIDTH-1:0] req_wdata;
    
    wire [TAG_W-1:0] req_tag  = req_addr[ADDR_WIDTH-1 -: TAG_W];
    wire [INDEX_W-1:0] req_idx  = req_addr[BYTE_W+WOFF_W +: INDEX_W];
    wire [WOFF_W-1:0] req_woff = req_addr[BYTE_W +: WOFF_W];
    
    reg [TAG_W-1: 0] tag_array [0: NUM_WAYS-1][0: NUM_SETS-1]; 
    reg valid_array [0: NUM_WAYS-1][0: NUM_SETS-1];    
    reg [LINE_W-1: 0] data_array [0: NUM_WAYS-1][0: NUM_SETS-1];
    reg [WAY_WIDTH-1: 0] age_array [0: NUM_WAYS-1][0: NUM_SETS-1];
    
    
    reg retry;    
    
    reg hit;
    reg [WAY_WIDTH-1:0] hit_way;
    integer j;
    
    always @(*) begin
        hit = 1'b0;
        hit_way = {WAY_WIDTH{1'b0}};
        for (j = 0; j < NUM_WAYS; j = j + 1)
            if (valid_array[j][req_idx] && (tag_array[j][req_idx] == req_tag)) begin
                hit = 1'b1;
                hit_way = j;
            end
    end
    
    reg[WAY_WIDTH-1:0] victim;
    integer k;
    always@(*) begin
        victim = {WAY_WIDTH{1'b0}};
        for (k = 0; k < NUM_WAYS; k = k+ 1)
            if (age_array[k][req_idx] == NUM_WAYS - 1)
                victim = k;
         for (k = NUM_WAYS - 1; k >= 0; k = k -1)
            if (!valid_array[k][req_idx])
                victim = k;   
    end
    
    reg lru_tracker;
    reg [WAY_WIDTH-1:0] touched_way;
    always @(*) begin
        lru_tracker = 1'b0;
        touched_way = {WAY_WIDTH{1'b0}};
        if (state == COMPARE && hit) begin
            lru_tracker = 1'b1;
            touched_way = hit_way;
        end 
        else if (state == ALLOCATE && mem_resp_valid) begin
            lru_tracker = 1'b1;
            touched_way = victim;
        end
    end
    
    
    always @(*) begin
        next_state = state;
        case(state)
            IDLE: if (cpu_req_valid) next_state = COMPARE;
            COMPARE: begin
                if (req_we) next_state = WRITE_MEM;
                else if (hit) begin
                    next_state = IDLE;
                end
                else begin
                    next_state = ALLOCATE;
                end
                
            end
            ALLOCATE: if(mem_resp_valid) next_state = COMPARE;
            WRITE_MEM: begin
                if (mem_req_ready) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end  
    
    
    integer i, j;
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            for (i=0; i < NUM_SETS; i = i+1)
                for (j=0; j < NUM_SETS; j = j + 1) begin
                    valid_array[i][j] <= 1'b0;
                    age_array[i][j] = i;
                end
                
            load_hit_count <= 0;
            load_miss_count <= 0;
            store_hit_count <= 0;
            store_miss_count <= 0;
            retry <= 0;
        end else begin
            state <= next_state;
            
            if (state == IDLE && cpu_req_valid) begin
                req_we <= cpu_req_we;
                req_addr <= cpu_req_addr;
                req_wdata <= cpu_req_wdata;
            end
            
            if (state == COMPARE && req_we && hit) begin
                 store_hit_count <= store_hit_count + 1;
                 data_array[hit_way][req_idx][req_woff*DATA_WIDTH +: DATA_WIDTH] <= req_wdata;
             end
             if (state == ALLOCATE && mem_resp_valid) begin
                data_array[victim][req_idx] <= mem_resp_rdata;
                tag_array[victim][req_idx] <= req_tag;
                valid_array[victim][req_idx] <= 1'b1;
             end
             
             if (lru_tracker) begin
                for (i = 0; i < NUM_WAYS; i = i + 1)
                    if (i == touched_way)
                        age_array[i][req_idx] <= {WAY_WIDTH{1'b0}};
                    else if (age_array[i][req_idx] < age_array[touched_way][req_idx])
                        age_array[i][req_idx] = age_array[i][req_idx] + 1;
             end
             
             if (state == COMPARE && !req_we && !retry && hit) begin
                load_hit_count <= load_hit_count + 1;
            end 
            if (state == COMPARE && !req_we && !hit) begin
                load_miss_count <= load_miss_count + 1;
                retry <= 1;
            end
            if (state == COMPARE && req_we && !hit) store_miss_count <= store_miss_count + 1;
            if (state == COMPARE && !req_we && hit && retry) retry <= 0;
            
        end
    end
    
    assign cpu_req_ready = (state == IDLE);
    assign cpu_resp_valid = (state == COMPARE && !req_we && hit) || (state == WRITE_MEM && mem_req_ready);
    assign cpu_resp_rdata = data_array[hit_way][req_idx][req_woff*DATA_WIDTH +: DATA_WIDTH];
    
    assign mem_req_valid = (state == ALLOCATE && !mem_resp_valid) || (state == WRITE_MEM && !mem_req_ready);
    assign mem_req_we    = (state == WRITE_MEM);
    assign mem_req_addr = { req_addr[ADDR_WIDTH-1:BYTE_W+WOFF_W], {(BYTE_W+WOFF_W){1'b0}} };
    
    assign mem_req_wdata = {LINE_WORDS{req_wdata}};
    assign mem_req_wstrb = {{LINE_WORDS-1{1'b0}}, 1'b1} << req_woff;
    

endmodule
