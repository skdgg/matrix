`include "fp32_addsub.sv"
`include "fp32_mul.sv"

module mv_mul_4x4_fp32 #(
    parameter int IDW = 8
)(
    input  logic        clk,
    input  logic        rst,

    // -------------------------
    // Configuration matrix
    // -------------------------
    input  logic [31:0] m00, m01, m02, m03,
    input  logic [31:0] m10, m11, m12, m13,
    input  logic [31:0] m20, m21, m22, m23,
    input  logic [31:0] m30, m31, m32, m33,

    // -------------------------
    // Per-vertex input stream
    // -------------------------
    input  logic        in_valid,
    input  logic [IDW-1:0] in_vertex_id,
    input  logic [31:0] vx, vy, vz, vw,     // FP32 vec4

    // -------------------------
    // Per-vertex output stream
    // -------------------------
    output logic        out_valid,
    output logic [IDW-1:0] out_vertex_id,
    output logic [31:0] ox, oy, oz, ow
);

    // -------------------------
    // Stage 0: input latch
    // -------------------------
    logic        v0_valid;
    logic [IDW-1:0] v0_id;
    logic [31:0] v0_x, v0_y, v0_z, v0_w;

    always_ff @(posedge clk) begin
        if (rst) begin
            v0_valid <= 1'b0;
            v0_id    <= '0;
            v0_x     <= 32'd0;
            v0_y     <= 32'd0;
            v0_z     <= 32'd0;
            v0_w     <= 32'd0;
        end else begin
            v0_valid <= in_valid;
            v0_id    <= in_vertex_id;
            v0_x     <= vx;
            v0_y     <= vy;
            v0_z     <= vz;
            v0_w     <= vw;
        end
    end

    // -------------------------
    // Stage 1: FP MUL (4 rows x 4 cols) - comb mul + FF latch
    // -------------------------
    logic [31:0] p00, p01, p02, p03;
    logic [31:0] p10, p11, p12, p13;
    logic [31:0] p20, p21, p22, p23;
    logic [31:0] p30, p31, p32, p33;

    fp32_mul u_mul00 (.a(m00), .b(v0_x), .overflow(), .y(p00));
    fp32_mul u_mul01 (.a(m01), .b(v0_y), .overflow(), .y(p01));
    fp32_mul u_mul02 (.a(m02), .b(v0_z), .overflow(), .y(p02));
    fp32_mul u_mul03 (.a(m03), .b(v0_w), .overflow(), .y(p03));

    fp32_mul u_mul10 (.a(m10), .b(v0_x), .overflow(), .y(p10));
    fp32_mul u_mul11 (.a(m11), .b(v0_y), .overflow(), .y(p11));
    fp32_mul u_mul12 (.a(m12), .b(v0_z), .overflow(), .y(p12));
    fp32_mul u_mul13 (.a(m13), .b(v0_w), .overflow(), .y(p13));

    fp32_mul u_mul20 (.a(m20), .b(v0_x), .overflow(), .y(p20));
    fp32_mul u_mul21 (.a(m21), .b(v0_y), .overflow(), .y(p21));
    fp32_mul u_mul22 (.a(m22), .b(v0_z), .overflow(), .y(p22));
    fp32_mul u_mul23 (.a(m23), .b(v0_w), .overflow(), .y(p23));

    fp32_mul u_mul30 (.a(m30), .b(v0_x), .overflow(), .y(p30));
    fp32_mul u_mul31 (.a(m31), .b(v0_y), .overflow(), .y(p31));
    fp32_mul u_mul32 (.a(m32), .b(v0_z), .overflow(), .y(p32));
    fp32_mul u_mul33 (.a(m33), .b(v0_w), .overflow(), .y(p33));

    logic [31:0] s1_p00, s1_p01, s1_p02, s1_p03;
    logic [31:0] s1_p10, s1_p11, s1_p12, s1_p13;
    logic [31:0] s1_p20, s1_p21, s1_p22, s1_p23;
    logic [31:0] s1_p30, s1_p31, s1_p32, s1_p33;

    logic        s1_valid;
    logic [IDW-1:0] s1_id;

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_valid <= 1'b0;
            s1_id    <= '0;

            s1_p00   <= 32'd0; s1_p01 <= 32'd0; s1_p02 <= 32'd0; s1_p03 <= 32'd0;
            s1_p10   <= 32'd0; s1_p11 <= 32'd0; s1_p12 <= 32'd0; s1_p13 <= 32'd0;
            s1_p20   <= 32'd0; s1_p21 <= 32'd0; s1_p22 <= 32'd0; s1_p23 <= 32'd0;
            s1_p30   <= 32'd0; s1_p31 <= 32'd0; s1_p32 <= 32'd0; s1_p33 <= 32'd0;
        end else begin
            s1_valid <= v0_valid;
            s1_id    <= v0_id;

            s1_p00   <= p00; s1_p01 <= p01; s1_p02 <= p02; s1_p03 <= p03;
            s1_p10   <= p10; s1_p11 <= p11; s1_p12 <= p12; s1_p13 <= p13;
            s1_p20   <= p20; s1_p21 <= p21; s1_p22 <= p22; s1_p23 <= p23;
            s1_p30   <= p30; s1_p31 <= p31; s1_p32 <= p32; s1_p33 <= p33;
        end
    end

    // -------------------------
    // Stage 2: pairwise add (per row) 2 adders each row
    // (fp32_addsub has 1-cycle internal pipeline => outputs valid next cycle)
    // -------------------------
    // row0
    logic [31:0] a00, a01;  logic a00_ov, a01_ov;
    fp32_addsub u_add0_0(.clk(clk),.rst(rst),.sub(1'b0),.a(s1_p00),.b(s1_p01),.overflow(a00_ov),.y(a00));
    fp32_addsub u_add0_1(.clk(clk),.rst(rst),.sub(1'b0),.a(s1_p02),.b(s1_p03),.overflow(a01_ov),.y(a01));

    // row1
    logic [31:0] a10, a11;  logic a10_ov, a11_ov;
    fp32_addsub u_add1_0(.clk(clk),.rst(rst),.sub(1'b0),.a(s1_p10),.b(s1_p11),.overflow(a10_ov),.y(a10));
    fp32_addsub u_add1_1(.clk(clk),.rst(rst),.sub(1'b0),.a(s1_p12),.b(s1_p13),.overflow(a11_ov),.y(a11));

    // row2
    logic [31:0] a20, a21;  logic a20_ov, a21_ov;
    fp32_addsub u_add2_0(.clk(clk),.rst(rst),.sub(1'b0),.a(s1_p20),.b(s1_p21),.overflow(a20_ov),.y(a20));
    fp32_addsub u_add2_1(.clk(clk),.rst(rst),.sub(1'b0),.a(s1_p22),.b(s1_p23),.overflow(a21_ov),.y(a21));

    // row3
    logic [31:0] a30, a31;  logic a30_ov, a31_ov;
    fp32_addsub u_add3_0(.clk(clk),.rst(rst),.sub(1'b0),.a(s1_p30),.b(s1_p31),.overflow(a30_ov),.y(a30));
    fp32_addsub u_add3_1(.clk(clk),.rst(rst),.sub(1'b0),.a(s1_p32),.b(s1_p33),.overflow(a31_ov),.y(a31));

    // valid/id alignment for stage2 (match adder outputs)
    logic        s2_valid;
    logic [IDW-1:0] s2_id;

    always_ff @(posedge clk) begin
        if (rst) begin
            s2_valid <= 1'b0;
            s2_id    <= '0;
        end else begin
            s2_valid <= s1_valid;
            s2_id    <= s1_id;
        end
    end

    // -------------------------
    // Stage 3: final add per row (a0 + a1)
    // -------------------------
    logic [31:0] row0_sum, row1_sum, row2_sum, row3_sum;
    logic        row0_ov,  row1_ov,  row2_ov,  row3_ov;

    fp32_addsub u_add0_2(.clk(clk),.rst(rst),.sub(1'b0),.a(a00),.b(a01),.overflow(row0_ov),.y(row0_sum));
    fp32_addsub u_add1_2(.clk(clk),.rst(rst),.sub(1'b0),.a(a10),.b(a11),.overflow(row1_ov),.y(row1_sum));
    fp32_addsub u_add2_2(.clk(clk),.rst(rst),.sub(1'b0),.a(a20),.b(a21),.overflow(row2_ov),.y(row2_sum));
    fp32_addsub u_add3_2(.clk(clk),.rst(rst),.sub(1'b0),.a(a30),.b(a31),.overflow(row3_ov),.y(row3_sum));

    // valid/id alignment for stage3 (match final-adder outputs)
    logic        s3_valid;
    logic [IDW-1:0] s3_id;

    always_ff @(posedge clk) begin
        if (rst) begin
            s3_valid <= 1'b0;
            s3_id    <= '0;
        end else begin
            s3_valid <= s2_valid;
            s3_id    <= s2_id;
        end
    end

    // -------------------------
    // Stage 4: output latch
    // -------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid     <= 1'b0;
            out_vertex_id <= '0;
            ox            <= 32'd0;
            oy            <= 32'd0;
            oz            <= 32'd0;
            ow            <= 32'd0;
        end else begin
            out_valid     <= s3_valid;
            out_vertex_id <= s3_id;
            ox            <= row0_sum;
            oy            <= row1_sum;
            oz            <= row2_sum;
            ow            <= row3_sum;
        end
    end

endmodule
