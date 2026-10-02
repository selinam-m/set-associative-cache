`timescale 1ns / 1ps

module tb_cache_trace;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam LINE_WORDS = 4;
    localparam NUM_SETS   = 64;
    localparam NUM_WAYS   = 4;
    localparam MEM_LINES  = 4096;
    localparam MEM_WORDS  = MEM_LINES * LINE_WORDS;
    localparam WIDX_W     = $clog2(MEM_WORDS);
    localparam MAX_OPS    = 8192;

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
    wire [31:0] store_hit_count, store_miss_count, writeback_count;

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
        .store_hit_count(store_hit_count), .store_miss_count(store_miss_count),
        .writeback_count(writeback_count)
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
    reg [31:0] trace [0:3*MAX_OPS-1];
    reg [31:0] expected [0:7];

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

    task compare(input [8*20:1] name, input integer got, input integer exp);
    begin
        if (got !== exp) begin
            errors = errors + 1;
            $display("MODEL MISMATCH %0s: rtl=%0d model=%0d", name, got, exp);
        end else
            $display("  %0s matches model: %0d", name, exp);
    end
    endtask

    reg [1023:0] trace_path;
    reg [1023:0] expected_path;
    integer n_ops;
    integer i;

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_path))
            trace_path = "C:/Users/morte/set-associative-cache/model/trace.hex";
        if (!$value$plusargs("EXPECTED=%s", expected_path))
            expected_path = "C:/Users/morte/set-associative-cache/model/expected.hex";

        for (i = 0; i < MEM_WORDS; i = i + 1) ref_mem[i] = i;
        for (i = 0; i < 3*MAX_OPS; i = i + 1) trace[i] = 32'hxxxx_xxxx;

        $readmemh(trace_path, trace);
        $readmemh(expected_path, expected);
        n_ops = expected[0];

        if (n_ops === 0 || n_ops > MAX_OPS) begin
            $display("TRACE ERROR: n_ops=%0d, check that the model files exist", n_ops);
            $finish;
        end

        reset = 1'b1;
        cpu_req_valid = 0; cpu_req_we = 0; cpu_req_addr = 0; cpu_req_wdata = 0;
        repeat (5) @(negedge clk);
        reset = 1'b0;

        $display("replaying %0d accesses from the C++ model trace", n_ops);
        for (i = 0; i < n_ops; i = i + 1) begin
            if (trace[3*i] == 32'h1) do_write(trace[3*i+1], trace[3*i+2]);
            else                     do_read (trace[3*i+1]);
        end

        repeat (6) @(negedge clk);

        $display("comparing RTL counters against the C++ reference model");
        compare("load hits",   load_hit_count,   expected[1]);
        compare("load misses", load_miss_count,  expected[2]);
        compare("store hits",  store_hit_count,  expected[3]);
        compare("store misses",store_miss_count, expected[4]);
        compare("writebacks",  writeback_count,  expected[5]);
        compare("memory reads",  mem_reads,  expected[6]);
        compare("memory writes", mem_writes, expected[7]);

        if (errors == 0)
            $display("PASS: %0d accesses replayed, data and all 7 counters match the model",
                     num_reads + num_writes);
        else
            $display("FAIL: %0d mismatches over %0d accesses", errors, num_reads + num_writes);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("TIMEOUT: trace replay hung");
        $finish;
    end
endmodule
