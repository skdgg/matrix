`timescale 1ns/10ps
`define CYCLE 1.0
`define MAX 1000000

`ifdef SYN
`include "../syn/top_syn.v"
`timescale 1ns/10ps
`include "/opt/CIC/Cell_Libraries/ADFP/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/VERILOG/N16ADFP_StdCell.v"
`else
`include "../src/mv_mul_4x4_fp32.sv"
`endif

module mv_tb;

initial begin
`ifdef SYN
  $display("[TB] SYN mode");
`else
  $display("[TB] RTL mode");
`endif
end

  // -------------------------
  // Config
  // -------------------------
  localparam int IDW        = 8;   // 保留但不再使用
  localparam int N_CASES    = 50;
  localparam int IN_WORDS   = 20;  // 16M + 4v
  localparam int OUT_WORDS  = 4;   // 4out
  localparam int LATENCY    = 4;

  localparam string IN_HEX  = "../sim/out_hex/mv_in.hex";
  localparam string OUT_HEX = "../sim/out_hex/mv_out.hex";

  // -------------------------
  // Clock / Reset
  // -------------------------
  logic clk, rst;
  initial clk = 0;
  always #(`CYCLE/2) clk = ~clk;

  // -------------------------
  // DUT I/O
  // -------------------------
  logic        in_valid;
  logic [31:0] vx, vy, vz, vw;

  logic        out_valid;
  logic [31:0] ox, oy, oz, ow;

  logic        m_valid;
  logic [31:0] m00,m01,m02,m03,
               m10,m11,m12,m13,
               m20,m21,m22,m23,
               m30,m31,m32,m33;

  mv_mul_4x4_fp32 dut (
    .clk(clk),
    .rst(rst),

    .m_valid(m_valid),
    .m00_i(m00), .m01_i(m01), .m02_i(m02), .m03_i(m03),
    .m10_i(m10), .m11_i(m11), .m12_i(m12), .m13_i(m13),
    .m20_i(m20), .m21_i(m21), .m22_i(m22), .m23_i(m23),
    .m30_i(m30), .m31_i(m31), .m32_i(m32), .m33_i(m33),

    .in_valid(in_valid),
    .vx(vx), .vy(vy), .vz(vz), .vw(vw),

    .out_valid(out_valid),
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
    logic [31:0] ox, oy, oz, ow;
  } gold_t;

  gold_t gold_q [$];

  // -------------------------
  // Helper tasks
  // -------------------------
  task automatic load_case_input(int case_idx);
    int base;
    begin
      base = case_idx * IN_WORDS;

      m00 = in_mem[base+0];  m01 = in_mem[base+1];
      m02 = in_mem[base+2];  m03 = in_mem[base+3];
      m10 = in_mem[base+4];  m11 = in_mem[base+5];
      m12 = in_mem[base+6];  m13 = in_mem[base+7];
      m20 = in_mem[base+8];  m21 = in_mem[base+9];
      m22 = in_mem[base+10]; m23 = in_mem[base+11];
      m30 = in_mem[base+12]; m31 = in_mem[base+13];
      m32 = in_mem[base+14]; m33 = in_mem[base+15];

      vx  = in_mem[base+16];
      vy  = in_mem[base+17];
      vz  = in_mem[base+18];
      vw  = in_mem[base+19];
    end
  endtask

  task automatic push_case_golden(int case_idx);
    int base;
    gold_t g;
    begin
      base = case_idx * OUT_WORDS;
      g.ox = out_mem[base+0];
      g.oy = out_mem[base+1];
      g.oz = out_mem[base+2];
      g.ow = out_mem[base+3];
      gold_q.push_back(g);
    end
  endtask

  int err_count;
  int i;

  // -------------------------
  // Stimulus
  // -------------------------
  initial begin
    rst = 1'b1;
    in_valid = 1'b0;
    m_valid  = 1'b0;
    vx='0; vy='0; vz='0; vw='0;

    $display("[TB] readmemh %s", IN_HEX);
    $readmemh(IN_HEX, in_mem);
    $display("[TB] readmemh %s", OUT_HEX);
    $readmemh(OUT_HEX, out_mem);

    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);

    for (i = 0; i < N_CASES; i++) begin
      #0.1;
      in_valid = 1'b1;
      m_valid  = 1'b1;
      load_case_input(i);
      push_case_golden(i);
      @(posedge clk);
    end

    #0.1 in_valid = 1'b0;

    repeat (LATENCY + 10) @(posedge clk);

    if (gold_q.size() != 0)
      $display("[TB][WARN] gold_q not empty: %0d", gold_q.size());
    else if (err_count == 0)
      $display("[TB] PASS");
    else
      $display("[TB] FAIL err_count=%0d", err_count);

    $finish;
  end

  // -------------------------
  // Checker
  // -------------------------
  gold_t g;

  always_ff @(negedge clk) begin
    if (rst) begin
      err_count <= 0;
    end else if (out_valid) begin
      if (gold_q.size() == 0) begin
        $display("[TB][ERR] out_valid but no golden");
        err_count <= err_count + 1;
      end else begin
        g = gold_q.pop_front();
        if (ox !== g.ox || oy !== g.oy || oz !== g.oz || ow !== g.ow) begin
          $display("[TB][ERR] Mismatch");
          $display("  got: %08x %08x %08x %08x", ox, oy, oz, ow);
          $display("  exp: %08x %08x %08x %08x", g.ox, g.oy, g.oz, g.ow);
          err_count <= err_count + 1;
        end
      end
    end
  end

endmodule
