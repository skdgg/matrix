`timescale 1ns/10ps
`define CYCLE 1.0  // Cycle time
`define MAX 1000000 // Max cycle number
`ifdef SYN
`include "../syn/top_syn.v"
`timescale 1ns/10ps
`include "/opt/CIC/Cell_Libraries/ADFP/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/VERILOG/N16ADFP_StdCell.v"
`else
`include "../mv_mul_4x4_fp32.sv"
`endif

module mv_tb;
initial begin
`ifdef SYN
  $display("[TB] SYN mode");
`else
  $display("[TB] RTL mode");
`endif
`ifdef FSDB
  `ifdef SYN
    $fsdbDumpfile("matrix_syn.fsdb");
  `else
    $fsdbDumpfile("matrix_rtl.fsdb");
  `endif
  $fsdbDumpvars(0, dut);
`elsif FSDB_ALL
  `ifdef SYN
    $fsdbDumpfile("matrix_syn.fsdb");
  `else
    $fsdbDumpfile("matrix_rtl.fsdb");
  `endif
  $fsdbDumpvars("+struct", "+mda", dut);
`endif
end
  // -------------------------
  // Config
  // -------------------------
  localparam int IDW        = 8;
  localparam int N_CASES    = 50;     // <-- 要跟 python 產生的一樣
  localparam int IN_WORDS   = 21;     // id + 16M + 4v
  localparam int OUT_WORDS  = 5;      // id + 4out
  localparam int LATENCY    = 4;      // <-- 可留著做 drain wait（不影響比對）

  localparam string IN_HEX  = "../sim/out_hex/mv_in.hex";
  localparam string OUT_HEX = "../sim/out_hex/mv_out.hex";

  // -------------------------
  // Clock / Reset
  // -------------------------
  logic clk, rst;

  initial clk = 0;
  always #(`CYCLE/2) clk = ~clk; // 100MHz

  // -------------------------
  // DUT I/O
  // -------------------------
  logic           in_valid;
  logic [IDW-1:0] in_vertex_id;
  logic [31:0]    vx, vy, vz, vw;

  logic           out_valid, out_ready;
  logic [IDW-1:0] out_vertex_id;
  logic [31:0]    ox, oy, oz, ow;

  // matrix regs driven by TB
  logic        m_valid;
  logic [31:0] m00,m01,m02,m03,
               m10,m11,m12,m13,
               m20,m21,m22,m23,
               m30,m31,m32,m33;

  mv_mul_4x4_fp32 #(.IDW(IDW)) dut (
    .clk(clk),
    .rst(rst),

    .m_valid(m_valid),
    .m00_i(m00), .m01_i(m01), .m02_i(m02), .m03_i(m03),
    .m10_i(m10), .m11_i(m11), .m12_i(m12), .m13_i(m13),
    .m20_i(m20), .m21_i(m21), .m22_i(m22), .m23_i(m23),
    .m30_i(m30), .m31_i(m31), .m32_i(m32), .m33_i(m33),

    .in_valid(in_valid),
    .in_vertex_id(in_vertex_id),
    .vx(vx), .vy(vy), .vz(vz), .vw(vw),

    .out_ready(out_ready),
    .out_valid(out_valid),
    .out_vertex_id(out_vertex_id),
    .ox(ox), .oy(oy), .oz(oz), .ow(ow)
  );

  // -------------------------
  // Hex memories
  // -------------------------
  logic [31:0] in_mem  [0:N_CASES*IN_WORDS-1];
  logic [31:0] out_mem [0:N_CASES*OUT_WORDS-1];

  // -------------------------
  // Scoreboard queue (golden)
  // -------------------------
  typedef struct packed {
    logic [IDW-1:0] id;
    logic [31:0] ox, oy, oz, ow;
  } gold_t;

  gold_t gold_q [$]; // queue

  // -------------------------
  // Helper: load one case from in_mem/out_mem
  // -------------------------
  task automatic load_case_input(int case_idx);
    int base;
    begin
      base = case_idx*IN_WORDS;

      in_vertex_id = in_mem[base+0][IDW-1:0];

      // matrix row-major m00..m33
      m00 = in_mem[base+1];  m01 = in_mem[base+2];  m02 = in_mem[base+3];  m03 = in_mem[base+4];
      m10 = in_mem[base+5];  m11 = in_mem[base+6];  m12 = in_mem[base+7];  m13 = in_mem[base+8];
      m20 = in_mem[base+9];  m21 = in_mem[base+10]; m22 = in_mem[base+11]; m23 = in_mem[base+12];
      m30 = in_mem[base+13]; m31 = in_mem[base+14]; m32 = in_mem[base+15]; m33 = in_mem[base+16];

      // vector
      vx  = in_mem[base+17];
      vy  = in_mem[base+18];
      vz  = in_mem[base+19];
      vw  = in_mem[base+20];
    end
  endtask

  task automatic push_case_golden(int case_idx);
    int base;
    gold_t g;
    begin
      base = case_idx*OUT_WORDS;

      g.id = out_mem[base+0][IDW-1:0];
      g.ox = out_mem[base+1];
      g.oy = out_mem[base+2];
      g.oz = out_mem[base+3];
      g.ow = out_mem[base+4];

      gold_q.push_back(g);
    end
  endtask
  `ifdef SYN
  initial $sdf_annotate("../syn/top_syn.sdf", dut);
  `endif
  int err_count;                 
  // -------------------------
  // Stimulus
  // -------------------------
  int i;
  initial begin
    // init
    rst = 1'b1;
    in_valid = 1'b0;
    in_vertex_id = '0;
    vx='0; vy='0; vz='0; vw='0;
    m_valid = '0;
    m00='0; m01='0; m02='0; m03='0;
    m10='0; m11='0; m12='0; m13='0;
    m20='0; m21='0; m22='0; m23='0;
    m30='0; m31='0; m32='0; m33='0;
    out_ready = 1'b1;

    // load hex
    $display("[TB] readmemh %s", IN_HEX);
    $readmemh(IN_HEX, in_mem);

    $display("[TB] readmemh %s", OUT_HEX);
    $readmemh(OUT_HEX, out_mem);

    // reset
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);

    // feed cases: one per cycle
    for (i = 0; i < N_CASES; i++) begin
      # 0.1;
      in_valid = 1'b1;
      m_valid = 1'b1;
      load_case_input(i);
      push_case_golden(i);

      @(posedge clk);
    end
    #0.1 in_valid  = 1'b0;

    // wait drain: allow pipeline to flush
    repeat (LATENCY + 10) @(posedge clk);

    if (gold_q.size() != 0) begin
      $display("[TB][WARN] gold_q not empty at end: size=%0d (maybe out_valid missing / dropped outputs)", gold_q.size());
    end else if (err_count == 0) begin
      $display("[TB] PASS: all vectors matched.");
    end else begin
      $display("[TB] FAIL: err_count=%0d", err_count);
    end

    $finish;
  end

  // -------------------------
  // Checker: pop golden on out_valid
  // -------------------------
  gold_t g;                      

  always_ff @(negedge clk) begin
    if (rst) begin
      err_count <= 0;            
    end else begin
      if (out_valid) begin
        if (gold_q.size() == 0) begin
          $display("[TB][ERR] out_valid but gold_q empty!");
          err_count <= err_count + 1;
        end else begin
          g = gold_q.pop_front();  

          // check id
          if (out_vertex_id !== g.id) begin
            $display("[TB][ERR] ID mismatch: got=%0d exp=%0d", out_vertex_id, g.id);
            err_count <= err_count + 1;
          end

          // bit-exact compare
          if (ox !== g.ox || oy !== g.oy || oz !== g.oz || ow !== g.ow) begin
            $display("[TB][ERR] Mismatch id=%0d", g.id);
            $display("  got: ox=%08x oy=%08x oz=%08x ow=%08x", ox, oy, oz, ow);
            $display("  exp: ox=%08x oy=%08x oz=%08x ow=%08x", g.ox, g.oy, g.oz, g.ow);
            err_count <= err_count + 1;
          end
        end
      end
    end
  end

endmodule
