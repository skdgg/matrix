`include "../src/fp32_addsub.sv"
`include "../src/fp32_mul.sv"

module mv_mul_4x4_fp32 (
    input  logic        clk,
    input  logic        rst,

    // -------------------------
    // Configuration matrix
    // -------------------------
    input  logic        m_valid,
    input  logic [31:0] m00_i, m01_i, m02_i, m03_i,
    input  logic [31:0] m10_i, m11_i, m12_i, m13_i,
    input  logic [31:0] m20_i, m21_i, m22_i, m23_i,
    input  logic [31:0] m30_i, m31_i, m32_i, m33_i,

    // -------------------------
    // Per-vertex input stream
    // -------------------------
    input  logic        in_valid,
    input  logic [31:0] vx, vy, vz, vw,

    // -------------------------
    // Per-vertex output stream
    // -------------------------
    output logic        out_valid,
    output logic [31:0] ox, oy, oz, ow
);

    // -------------------------
    // Save 4x4 matrix
    // -------------------------
    logic [127:0] m0_reg, m1_reg, m2_reg, m3_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            m0_reg <= '0;
            m1_reg <= '0;
            m2_reg <= '0;
            m3_reg <= '0;
        end else if (m_valid) begin
            m0_reg <= {m00_i, m01_i, m02_i, m03_i};
            m1_reg <= {m10_i, m11_i, m12_i, m13_i};
            m2_reg <= {m20_i, m21_i, m22_i, m23_i};
            m3_reg <= {m30_i, m31_i, m32_i, m33_i};
        end
    end

    // -------------------------
    // Select matrix source
    // -------------------------
    logic [31:0] m00, m01, m02, m03;
    logic [31:0] m10, m11, m12, m13;
    logic [31:0] m20, m21, m22, m23;
    logic [31:0] m30, m31, m32, m33;

    always_comb begin
        if (m_valid) begin
            {m00, m01, m02, m03} = {m00_i, m01_i, m02_i, m03_i};
            {m10, m11, m12, m13} = {m10_i, m11_i, m12_i, m13_i};
            {m20, m21, m22, m23} = {m20_i, m21_i, m22_i, m23_i};
            {m30, m31, m32, m33} = {m30_i, m31_i, m32_i, m33_i};
        end else begin
            {m00, m01, m02, m03} = m0_reg;
            {m10, m11, m12, m13} = m1_reg;
            {m20, m21, m22, m23} = m2_reg;
            {m30, m31, m32, m33} = m3_reg;
        end
    end

    // -------------------------
    // Stage 1: FP MUL (comb)
    // -------------------------
    logic [31:0] p00,p01,p02,p03;
    logic [31:0] p10,p11,p12,p13;
    logic [31:0] p20,p21,p22,p23;
    logic [31:0] p30,p31,p32,p33;

    fp32_mul u_mul00 (.a(m00), .b(vx), .overflow(), .y(p00));
    fp32_mul u_mul01 (.a(m01), .b(vy), .overflow(), .y(p01));
    fp32_mul u_mul02 (.a(m02), .b(vz), .overflow(), .y(p02));
    fp32_mul u_mul03 (.a(m03), .b(vw), .overflow(), .y(p03));

    fp32_mul u_mul10 (.a(m10), .b(vx), .overflow(), .y(p10));
    fp32_mul u_mul11 (.a(m11), .b(vy), .overflow(), .y(p11));
    fp32_mul u_mul12 (.a(m12), .b(vz), .overflow(), .y(p12));
    fp32_mul u_mul13 (.a(m13), .b(vw), .overflow(), .y(p13));

    fp32_mul u_mul20 (.a(m20), .b(vx), .overflow(), .y(p20));
    fp32_mul u_mul21 (.a(m21), .b(vy), .overflow(), .y(p21));
    fp32_mul u_mul22 (.a(m22), .b(vz), .overflow(), .y(p22));
    fp32_mul u_mul23 (.a(m23), .b(vw), .overflow(), .y(p23));

    fp32_mul u_mul30 (.a(m30), .b(vx), .overflow(), .y(p30));
    fp32_mul u_mul31 (.a(m31), .b(vy), .overflow(), .y(p31));
    fp32_mul u_mul32 (.a(m32), .b(vz), .overflow(), .y(p32));
    fp32_mul u_mul33 (.a(m33), .b(vw), .overflow(), .y(p33));

    // -------------------------
    // Stage 1 register
    // -------------------------
    logic s1_valid;
    logic [31:0] s1_p00,s1_p01,s1_p02,s1_p03;
    logic [31:0] s1_p10,s1_p11,s1_p12,s1_p13;
    logic [31:0] s1_p20,s1_p21,s1_p22,s1_p23;
    logic [31:0] s1_p30,s1_p31,s1_p32,s1_p33;

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_valid <= 1'b0;
        end else begin
            s1_valid <= in_valid;
            s1_p00 <= p00; s1_p01 <= p01; s1_p02 <= p02; s1_p03 <= p03;
            s1_p10 <= p10; s1_p11 <= p11; s1_p12 <= p12; s1_p13 <= p13;
            s1_p20 <= p20; s1_p21 <= p21; s1_p22 <= p22; s1_p23 <= p23;
            s1_p30 <= p30; s1_p31 <= p31; s1_p32 <= p32; s1_p33 <= p33;
        end
    end

    // -------------------------
    // Stage 2: pairwise add (COMB)
    // -------------------------
    logic [31:0] a00,a01,a10,a11,a20,a21,a30,a31;

    fp32_addsub u_add00 (.sub(1'b0), .a(s1_p00), .b(s1_p01), .overflow(), .y(a00));
    fp32_addsub u_add01 (.sub(1'b0), .a(s1_p02), .b(s1_p03), .overflow(), .y(a01));

    fp32_addsub u_add10 (.sub(1'b0), .a(s1_p10), .b(s1_p11), .overflow(), .y(a10));
    fp32_addsub u_add11 (.sub(1'b0), .a(s1_p12), .b(s1_p13), .overflow(), .y(a11));

    fp32_addsub u_add20 (.sub(1'b0), .a(s1_p20), .b(s1_p21), .overflow(), .y(a20));
    fp32_addsub u_add21 (.sub(1'b0), .a(s1_p22), .b(s1_p23), .overflow(), .y(a21));

    fp32_addsub u_add30 (.sub(1'b0), .a(s1_p30), .b(s1_p31), .overflow(), .y(a30));
    fp32_addsub u_add31 (.sub(1'b0), .a(s1_p32), .b(s1_p33), .overflow(), .y(a31));

    // -------------------------
    // Stage 2 register
    // -------------------------
    logic [31:0] s2_a00, s2_a01, s2_a10, s2_a11;
    logic [31:0] s2_a20, s2_a21, s2_a30, s2_a31;
    logic         s2_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            s2_a00 <= '0; s2_a01 <= '0;
            s2_a10 <= '0; s2_a11 <= '0;
            s2_a20 <= '0; s2_a21 <= '0;
            s2_a30 <= '0; s2_a31 <= '0;
        end else begin
            out_valid <= s1_valid;
            s2_a00 <= a00; s2_a01 <= a01;
            s2_a10 <= a10; s2_a11 <= a11;
            s2_a20 <= a20; s2_a21 <= a21;
            s2_a30 <= a30; s2_a31 <= a31;
        end
    end

    // -------------------------
    // Stage 3: final add (COMB)
    // -------------------------
    fp32_addsub u_addf0 (.sub(1'b0), .a(s2_a00), .b(s2_a01), .overflow(), .y(ox));
    fp32_addsub u_addf1 (.sub(1'b0), .a(s2_a10), .b(s2_a11), .overflow(), .y(oy));
    fp32_addsub u_addf2 (.sub(1'b0), .a(s2_a20), .b(s2_a21), .overflow(), .y(oz));
    fp32_addsub u_addf3 (.sub(1'b0), .a(s2_a30), .b(s2_a31), .overflow(), .y(ow));

endmodule
