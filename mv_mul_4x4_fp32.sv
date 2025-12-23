`include "../fp32_addsub.sv"
`include "../fp32_mul.sv"

module mv_mul_4x4_fp32 #(
    parameter int IDW = 8
)(
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
    input  logic           in_valid,
    input  logic [IDW-1:0] in_vertex_id,
    input  logic [31:0]    vx, vy, vz, vw,     // FP32 vec4

    // -------------------------
    // Per-vertex output stream
    // -------------------------
    input  logic           out_ready,
    output logic           out_valid,
    output logic [IDW-1:0] out_vertex_id,
    output logic [31:0]    ox, oy, oz, ow
);

    // control state
    typedef enum logic [1:0] { IDLE, MUL, ADD1, ADD2 } MATRIX_MUL_STATE_t;
    MATRIX_MUL_STATE_t state_q, state_n;

    always_ff @(posedge clk) begin
        if(rst) begin
            state_q <= IDLE;
        end else begin
            state_q <= state_n;
        end
    end

    always_comb begin
        case(state_q)
            IDLE: state_n = (in_valid) ? ADD1 : IDLE;
            ADD1: state_n = ADD2;
            ADD2: state_n = (in_valid) ? MUL : ADD2;
        endcase
    end

    // -------------------------
    // Save 4*4 matrix if m_valid
    // -------------------------
    integer i;
    logic [127:0] m0_reg;
    logic [127:0] m1_reg;
    logic [127:0] m2_reg;
    logic [127:0] m3_reg;

    always_ff @(posedge clk) begin
        if(rst) begin
            for(i = 0; i < 4; i = i + 1) begin
                m0_reg <= 'd0;
                m1_reg <= 'd0;
                m2_reg <= 'd0;
                m3_reg <= 'd0;
            end
        end else if(m_valid) begin
            m0_reg <= {m00_i, m01_i, m02_i, m03_i};
            m1_reg <= {m10_i, m11_i, m12_i, m13_i};
            m2_reg <= {m20_i, m21_i, m22_i, m23_i};
            m3_reg <= {m30_i, m31_i, m32_i, m33_i};
        end
    end

    // -------------------------
    // Stage 1: FP MUL (4 rows x 4 cols) - comb mul + FF latch
    // -------------------------
    logic [31:0] m00, m01, m02, m03;
    logic [31:0] m10, m11, m12, m13;
    logic [31:0] m20, m21, m22, m23;
    logic [31:0] m30, m31, m32, m33;

    logic [31:0] p00, p01, p02, p03;
    logic [31:0] p10, p11, p12, p13;
    logic [31:0] p20, p21, p22, p23;
    logic [31:0] p30, p31, p32, p33;

    // decide m source
    // if m_valid = 1'b1 then use the input m
    // if m_valid = 1'b0 then use m that stored in m_reg
    always_comb begin
        if(m_valid) begin
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

    logic [31:0] s1_p00, s1_p01, s1_p02, s1_p03;
    logic [31:0] s1_p10, s1_p11, s1_p12, s1_p13;
    logic [31:0] s1_p20, s1_p21, s1_p22, s1_p23;
    logic [31:0] s1_p30, s1_p31, s1_p32, s1_p33;

    logic           s1_valid;
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
            s1_valid <= in_valid;
            s1_id    <= in_vertex_id;

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
    logic [31:0] s2_a00, s2_a01;
    logic [31:0] s2_a10, s2_a11;
    logic [31:0] s2_a20, s2_a21;
    logic [31:0] s2_a30, s2_a31;    

    always_ff @(posedge clk) begin
        if (rst) begin
            s2_valid <= 1'b0;
            s2_id    <= '0;
            s2_a00   <= 32'd0; s2_a01 <= 32'd0;
            s2_a10   <= 32'd0; s2_a11 <= 32'd0;
            s2_a20   <= 32'd0; s2_a21 <= 32'd0;
            s2_a30   <= 32'd0; s2_a31 <= 32'd0;
        end else begin
            s2_valid <= s1_valid;
            s2_id    <= s1_id;
            s2_a00   <= a00; s2_a01 <= a01;
            s2_a10   <= a10; s2_a11 <= a11;
            s2_a20   <= a20; s2_a21 <= a21;
            s2_a30   <= a30; s2_a31 <= a31;
        end
    end

    // -------------------------
    // Stage 3: final add per row (a0 + a1)
    // -------------------------
    logic [31:0] row0_sum, row1_sum, row2_sum, row3_sum;
    logic        row0_ov,  row1_ov,  row2_ov,  row3_ov;

    fp32_addsub u_add0_2(.clk(clk),.rst(rst),.sub(1'b0),.a(s2_a00),.b(s2_a01),.overflow(row0_ov),.y(row0_sum));
    fp32_addsub u_add1_2(.clk(clk),.rst(rst),.sub(1'b0),.a(s2_a10),.b(s2_a11),.overflow(row1_ov),.y(row1_sum));
    fp32_addsub u_add2_2(.clk(clk),.rst(rst),.sub(1'b0),.a(s2_a20),.b(s2_a21),.overflow(row2_ov),.y(row2_sum));
    fp32_addsub u_add3_2(.clk(clk),.rst(rst),.sub(1'b0),.a(s2_a30),.b(s2_a31),.overflow(row3_ov),.y(row3_sum));

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
