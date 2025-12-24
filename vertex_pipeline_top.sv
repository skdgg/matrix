module vertex_pipeline_top #(
    parameter int IDW = 8
)(
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------
    // Input
    // -------------------------
    input  logic           in_valid,
    input  logic [IDW-1:0] in_vid,

    // vertex
    input  logic [31:0] Vx, Vy, Vz,

    // normal
    input  logic [31:0] Nx, Ny, Nz,

    // point light
    input  logic [31:0] Lpx, Lpy, Lpz,
    input  logic [31:0] Lp_int,

    // directional light
    input  logic [31:0] Ldx, Ldy, Ldz,
    input  logic [31:0] Ld_int,

    // ambient
    input  logic [31:0] La_int,

    // matrices / projection
    input  logic           mv_valid,
    input  logic [31:0]    m00,m01,m02,m03,
                           m10,m11,m12,m13,
                           m20,m21,m22,m23,
                           m30,m31,m32,m33,
    input  logic [31:0]    Pscale_x,
    input  logic [31:0]    Pscale_y,

    // -------------------------
    // Output
    // -------------------------
    output logic           out_valid,
    output logic [IDW-1:0] out_vid,
    output logic [31:0]    Px,
    output logic [31:0]    Py,
    output logic [31:0]    invPz,
    output logic [31:0]    Brightness
);

    // ============================================================
    // STAGE A : 全部能並行的先做
    // ============================================================

    // ---- A1: V' = M * V  ---------------------------------------
    logic mv_v;
    logic [IDW-1:0] mv_id;
    logic [31:0] Vpx, Vpy, Vpz, Vpw;

    mv_mul_4x4_fp32 u_mv (
        .clk(clk), .rst(~rst_n),
        .m_valid(mv_valid),
        .m00_i(m00), .m01_i(m01), .m02_i(m02), .m03_i(m03),
        .m10_i(m10), .m11_i(m11), .m12_i(m12), .m13_i(m13),
        .m20_i(m20), .m21_i(m21), .m22_i(m22), .m23_i(m23),
        .m30_i(m30), .m31_i(m31), .m32_i(m32), .m33_i(m33),
        .in_valid(in_valid),
        .in_vertex_id(in_vid),
        .vx(Vx), .vy(Vy), .vz(Vz), .vw(32'h3f800000),
        .out_ready(1'b1),
        .out_valid(mv_v),
        .out_vertex_id(mv_id),
        .ox(Vpx), .oy(Vpy), .oz(Vpz), .ow(Vpw)
    );

    // ---- A2: normalize(N) -------------------------------------
    logic n_v;
    logic [IDW-1:0] n_id;
    logic [31:0] Nhx, Nhy, Nhz;

    fp32_normalize3 u_norm_n (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid),
        .in_id(in_vid),
        .vx(Nx), .vy(Ny), .vz(Nz),
        .out_valid(n_v),
        .out_id(n_id),
        .ox(Nhx), .oy(Nhy), .oz(Nhz)
    );

    // ---- A3: normalize(Ld) ------------------------------------
    logic ld_v;
    logic [IDW-1:0] ld_id;
    logic [31:0] Ldhx, Ldhy, Ldhz;

    fp32_normalize3 u_norm_ld (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid),
        .in_id(in_vid),
        .vx(Ldx), .vy(Ldy), .vz(Ldz),
        .out_valid(ld_v),
        .out_id(ld_id),
        .ox(Ldhx), .oy(Ldhy), .oz(Ldhz)
    );

    // ============================================================
    // STAGE B : 依賴 V' 的並行計算
    // ============================================================

    // ---- B1: L'p = Lp - V' ------------------------------------
    logic lp_v;
    logic [31:0] Lpx_p, Lpy_p, Lpz_p;

    fp32_addsub u_lp_x(.clk(clk),.rst(~rst_n),.sub(1'b1),.a(Lpx),.b(Vpx),.y(Lpx_p));
    fp32_addsub u_lp_y(.clk(clk),.rst(~rst_n),.sub(1'b1),.a(Lpy),.b(Vpy),.y(Lpy_p));
    fp32_addsub u_lp_z(.clk(clk),.rst(~rst_n),.sub(1'b1),.a(Lpz),.b(Vpz),.y(Lpz_p));

    // ---- B2: invPz = invsqrt(Vpz*Vpz) -------------------------
    logic vz2_v;
    logic [31:0] vz2;

    fp32_mul u_vz2(.a(Vpz), .b(Vpz), .y(vz2));

    fast_inv_sqrt u_invpz (
        .clk(clk), .rst_n(rst_n),
        .in_valid(mv_v),
        .x_fp32(vz2),
        .out_valid(vz2_v),
        .y_fp32(invPz)
    );

    // ============================================================
    // STAGE C : normalize(L'p)
    // ============================================================

    logic lp_n_v;
    logic [IDW-1:0] lp_n_id;
    logic [31:0] Lphx, Lphy, Lphz;

    fp32_normalize3 u_norm_lp (
        .clk(clk), .rst_n(rst_n),
        .in_valid(mv_v),
        .in_id(mv_id),
        .vx(Lpx_p), .vy(Lpy_p), .vz(Lpz_p),
        .out_valid(lp_n_v),
        .out_id(lp_n_id),
        .ox(Lphx), .oy(Lphy), .oz(Lphz)
    );

    // ============================================================
    // STAGE D : Diffuse + Brightness
    // ============================================================

    logic [31:0] dot_p, dot_d;

    fp32_dot3 u_dot_p(.clk(clk),.rst(~rst_n),
        .ax(Nhx),.ay(Nhy),.az(Nhz),
        .bx(Lphx),.by(Lphy),.bz(Lphz),
        .y(dot_p));

    fp32_dot3 u_dot_d(.clk(clk),.rst(~rst_n),
        .ax(Nhx),.ay(Nhy),.az(Nhz),
        .bx(Ldhx),.by(Ldhy),.bz(Ldhz),
        .y(dot_d));

    // clamp (sign bit)
    logic [31:0] Idp = dot_p[31] ? 32'd0 : dot_p;
    logic [31:0] Idd = dot_d[31] ? 32'd0 : dot_d;

    logic [31:0] t_p, t_d, t_sum;

    fp32_mul u_bp(.a(Idp), .b(Lp_int), .y(t_p));
    fp32_mul u_bd(.a(Idd), .b(Ld_int), .y(t_d));
    fp32_addsub u_bsum1(.clk(clk),.rst(~rst_n),.sub(1'b0),.a(t_p),.b(t_d),.y(t_sum));
    fp32_addsub u_bsum2(.clk(clk),.rst(~rst_n),.sub(1'b0),.a(t_sum),.b(La_int),.y(Brightness));

    // ============================================================
    // STAGE E : Projection
    // ============================================================

    logic [31:0] Px_t, Py_t;

    fp32_mul u_px1(.a(Vpx), .b(Pscale_x), .y(Px_t));
    fp32_mul u_px2(.a(Px_t), .b(invPz),   .y(Px));

    fp32_mul u_py1(.a(Vpy), .b(Pscale_y), .y(Py_t));
    fp32_mul u_py2(.a(Py_t), .b(invPz),   .y(Py));

    // ============================================================
    // OUTPUT ALIGN (以 lp_n_v 為最慢 valid)
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_vid   <= '0;
        end else begin
            out_valid <= lp_n_v;
            out_vid   <= lp_n_id;
        end
    end

endmodule
