`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.09.2026 21:15:34
// Design Name: 
// Module Name: tb_cache
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


module tb_cache;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam LINE_WORDS = 4;
    localparam NUM_SETS   = 64;
    localparam MEM_LINES  = 4096;
    localparam LINE_BYTES = LINE_WORDS * 4;              
    localparam MEM_WORDS  = MEM_LINES * LINE_WORDS;      
    localparam MEM_BYTES  = MEM_LINES * LINE_BYTES;      
    localparam WIDX_W     = $clog2(MEM_WORDS);
    localparam NUM_WAYS = 4;
    
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg reset;
    
    reg cpu_req_valid, cpu_req_we;
    reg [31:0] cpu_req_addr, cpu_req_wdata;
    wire cpu_req_ready, cpu_resp_valid;
    wire [31:0] cpu_resp_rdata;
    
    wire mem_req_valid, mem_req_we, mem_req_ready, mem_resp_valid;
    wire [31:0]  mem_req_addr;
    wire [127:0] mem_req_wdata, mem_resp_rdata;
    wire [3:0]   mem_req_wstrb;
    
    wire [31:0] load_hit_count, load_miss_count;
    wire [31:0] store_hit_count, store_miss_count;
    
    
    cache_direct #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .LINE_WORDS(LINE_WORDS), .NUM_SETS(NUM_SETS), .NUM_WAYS(NUM_WAYS)
    ) u_cache (
        .clk(clk), .reset(reset),
        .cpu_req_valid(cpu_req_valid), .cpu_req_we(cpu_req_we),
        .cpu_req_addr(cpu_req_addr),   .cpu_req_wdata(cpu_req_wdata),
        .cpu_req_ready(cpu_req_ready),
        .cpu_resp_valid(cpu_resp_valid), .cpu_resp_rdata(cpu_resp_rdata),
        .mem_req_valid(mem_req_valid), .mem_req_we(mem_req_we),
        .mem_req_addr(mem_req_addr),   .mem_req_wdata(mem_req_wdata),
        .mem_req_wstrb(mem_req_wstrb), .mem_req_ready(mem_req_ready),
        .mem_resp_valid(mem_resp_valid), .mem_resp_rdata(mem_resp_rdata),
        .load_hit_count(load_hit_count), .load_miss_count(load_miss_count),
        .store_hit_count(store_hit_count), .store_miss_count(store_miss_count)
    );

    simple_mem #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .LINE_WORDS(LINE_WORDS), .MEM_LINES(MEM_LINES), .LATENCY(10)
    ) u_mem (
        .clk(clk), .rst(reset),
        .mem_req_valid(mem_req_valid), .mem_req_we(mem_req_we),
        .mem_req_addr(mem_req_addr),   .mem_req_wdata(mem_req_wdata),
        .mem_req_wstrb(mem_req_wstrb), .mem_req_ready(mem_req_ready),
        .mem_resp_valid(mem_resp_valid), .mem_resp_rdata(mem_resp_rdata)
    );
    
    reg [31:0] ref_mem [0:MEM_WORDS-1];
    integer k;
    initial for (k = 0; k < MEM_WORDS; k = k + 1) ref_mem[k] = k;

    integer num_reads = 0, num_writes = 0, errors = 0;
    
    integer mem_reads = 0, mem_writes = 0;
    always @(negedge clk) begin
        if (mem_resp_valid) mem_reads = mem_reads + 1;
        if (mem_req_ready && mem_req_we) mem_writes = mem_writes + 1;
    end

    task cpu_op(input we, input [31:0] addr, input [31:0] wdata, output [31:0] rdata);
    begin
        @(negedge clk);
        cpu_req_valid = 1'b1;  cpu_req_we = we;
        cpu_req_addr  = addr;  cpu_req_wdata = wdata;
        while (!cpu_req_ready) @(negedge clk);
        @(negedge clk);                    
        cpu_req_valid = 1'b0;
        while (!cpu_resp_valid) @(negedge clk);
        rdata = cpu_resp_rdata;
    end
    endtask
    
    task do_read(input [31:0] addr);
        reg [31:0] rdata, exp;
    begin
        exp = ref_mem[addr[2 +: WIDX_W]];
        cpu_op(1'b0, addr, 32'h0, rdata);
        num_reads = num_reads + 1;
        if (rdata !== exp) begin
            errors = errors + 1;
            $display("FAIL: read addr=%h got=%h exp=%h (t=%0t)", addr, rdata, exp, $time);
                     
        end
    end
    endtask

    task do_write(input [31:0] addr, input [31:0] data);
        reg [31:0] dummy;
    begin
        cpu_op(1'b1, addr, data, dummy);
        ref_mem[addr[2 +: WIDX_W]] = data;
        num_writes = num_writes + 1;
    end
    endtask
    
    task random_ops(input integer n, input [31:0] ws_bytes);
        integer j;
        reg [31:0] addr, data;
    begin
        for (j = 0; j < n; j = j + 1) begin
            addr = ({$random} % ws_bytes) & 32'hFFFF_FFFC;  
            data = $random;
            if ({$random} % 2) do_write(addr, data);
            else do_read(addr);
        end
    end
    endtask
    
    task check_directed;
    begin
        repeat (4) @(negedge clk);   
        if (load_hit_count   !== 5 || load_miss_count  !== 4 || store_hit_count  !== 1 || store_miss_count !== 2) begin
            errors = errors + 1;
            $display("AUDIT FAIL (directed): LH=%0d exp 5 | LM=%0d exp 4 | SH=%0d exp 1 | SM=%0d exp 2",
                     load_hit_count, load_miss_count, store_hit_count, store_miss_count);
        end else
            $display("directed counter check OK: LH=5 LM=4 SH=1 SM=2");
    end
    endtask
    
    integer phase_start_load_hits, phase_start_num_reads;

    task phase_begin;
    begin
        repeat (4) @(negedge clk);          
        phase_start_load_hits = load_hit_count;
        phase_start_num_reads = num_reads;
    end
    endtask

    task phase_report(input [8*24:1] phase_name);
        integer loads_hit_this_phase, loads_issued_this_phase;
    begin
        repeat (4) @(negedge clk);
        loads_hit_this_phase    = load_hit_count - phase_start_load_hits;
        loads_issued_this_phase = num_reads - phase_start_num_reads;
        if (loads_issued_this_phase > 0)
            $display("phase %0s: load hit rate %0d%% (%0d hits / %0d loads)", phase_name, (100*loads_hit_this_phase)/loads_issued_this_phase,
                loads_hit_this_phase, loads_issued_this_phase);
        else
            $display("phase %0s: no loads issued", phase_name);
    end
    endtask
    
    task check_set_association;
    begin
        repeat (4) @(negedge clk);
        if (load_hit_count !== 10 || load_miss_count !== 10 || store_hit_count !== 1 || store_miss_count !== 2) begin
            errors = errors + 1;
            $display("AUDIT FAILED (set association / LRU): load hits = %0d exp 10 | load misses = %0d exp 10 | store hits = %0d exp 1 | store misses = %0d exp 2", load_hit_count, load_miss_count, store_hit_count, store_miss_count);
        end else 
            $display("Set association / LRU passed: 4 ways coexist and LRU victim correct");
          
    end
    endtask
    
    task audit;
    begin
        repeat (4) @(negedge clk);
        $display("---cache counters: load hits = %0d, load misses = %0d, store hits = %0d, store misses = %0d | bus observed reads = %0d writes = %0d | TB ops reads = %0d writes = %0d",
             load_hit_count, load_miss_count, store_hit_count, store_miss_count, mem_reads, mem_writes, num_reads, num_writes);
        if (load_hit_count + load_miss_count != num_reads) begin
            errors = errors + 1;
            $display("AUDIT FAIL: load hits + load misses = %0d, but TB issued %0d loads", load_hit_count + load_miss_count, num_reads);
        end
        if (store_hit_count + store_miss_count !== num_writes) begin
            errors = errors + 1;
            $display("AUDIT FAIL: store hits + store misses = %0d, but TB issued %0d writes", store_hit_count + store_miss_count, num_writes);
        end
        if (mem_reads !== load_miss_count) begin
            errors = errors + 1;
            $display("AUDIT FAIL: %0d memory line reads by memory, but %0d cache load misses reported", mem_reads, load_miss_count);
        end
        if (mem_writes !== store_hit_count + store_miss_count) begin
            errors = errors + 1;
            $display("AUDIT FAIL: %0d memory line writes by memory, but %0d cache stores reported", mem_writes, store_hit_count + store_miss_count);
        end
        if (errors == 0) $display("AUDIT: All 4 invariants hold");
        
    end
    endtask
  
     initial begin
        reset = 1'b1;
        cpu_req_valid = 0; cpu_req_we = 0; cpu_req_addr = 0; cpu_req_wdata = 0;
        repeat (5) @(negedge clk);
        reset = 1'b0;

        $display("--- directed: cold miss, then hits ---");
        do_read(32'h0000_0100);            
        do_read(32'h0000_0100);            
        do_read(32'h0000_0104);            

        $display("--- directed: store hit, then loads ---");
        do_write(32'h0000_0100, 32'hDEAD_BEEF);
        do_read (32'h0000_0100);
        do_read (32'h0000_010C);          

        $display("--- directed: store miss (no-allocate), then load ---");
        do_write(32'h0000_2000, 32'hCAFE_F00D); 
        do_read (32'h0000_2000);           
        do_read (32'h0000_2004);

        $display("--- directed: conflict eviction (same index, new tag) ---");
        do_write(32'h0000_0300, 32'h1111_1111);
        do_read (32'h0000_0300 + NUM_SETS*LINE_BYTES); 
        do_read (32'h0000_0300);  
        
        check_directed;   
        
        do_read(32'h0000_0180);      
        do_read(32'h0000_0580); 
        do_read(32'h0000_0980); 
        do_read(32'h0000_0D80); 
        do_read(32'h0000_0180); 
        do_read(32'h0000_0580); 
        do_read(32'h0000_0980); 
        do_read(32'h0000_0D80); 
        do_read(32'h0000_1180); 
        do_read(32'h0000_0180); 
        do_read(32'h0000_0980); 
        

        $display("--- random: 1 KB working set (mostly hits after warmup) ---");
        phase_begin;
        random_ops(2000, 32'h0000_0400);
        phase_report("small-ws");

        $display("--- random: full 64 KB range (mostly misses) ---");
        phase_begin;
        random_ops(2000, MEM_BYTES);
        phase_report("full-range");
        
        audit;

        if (errors == 0)
            $display("PASS: %0d operations, 0 mismatches, all audits pass", num_reads + num_writes);
        else
            $display("FAIL: %0d mismatches in %0d operations", errors, num_reads + num_writes);
        $finish;
    end
    
    initial begin
        #5_000_000;                        
        $display("TIMEOUT: testbench hung -- check handshakes");
        $finish;
    end
    
                
    
endmodule
