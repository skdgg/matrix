`include "utils/fp32_addsub.sv"
`include "utils/fp32_mul.sv"
`include "utils/fp32_dot3.sv"
`include "utils/fp32_normalize3.sv"
`include "utils/mv_mul_4x4_fp32.sv"
`include "utils/fast_inv_sqrt.sv"
`include "utils/delay_reg.sv"

module vertex_processing (
    input clk,
    input rst,

    // Vertex coordinate, normal vector
    input         v_valid_i,
    input  [31:0] Vx_i, Vy_i, Vz_i,
    input  [31:0] Nx_i, Ny_i, Nz_i,

    // Position light coordinate, intensity
    input         Lp_valid_i,
    input  [31:0] Lpx_i, Lpy_i, Lpz_i,
    input  [31:0] Lp_intensity_i,

    // Direction light vector, intensity
    input         Ld_valid_i,
    input  [31:0] Ldx_i, Ldy_i, Ldz_i,
    input  [31:0] Ld_intensity_i,

    // Ambient light intensity
    input         La_valid_i,
    input  [31:0] La_intensity_i,

    // Model-View matrix
    input         m_valid_i,
    input  [31:0] m00_i, m01_i, m02_i, m03_i,
    input  [31:0] m10_i, m11_i, m12_i, m13_i,
    input  [31:0] m20_i, m21_i, m22_i, m23_i,
    input  [31:0] m30_i, m31_i, m32_i, m33_i,

    // Projection scale
    input         P_scale_valid_i,
    input  [31:0] Px_scale_i, Py_scale_i,

    // Coordinate and brightness output to rasterizer
    output logic        out_valid_o,
    output logic [31:0] Px_o, Py_o, Pz_inv_o,
    output logic [31:0] brightness_o
);

    // Define delays of modules
    localparam FP32_ADDSUB_D  = 1;
    localparam FP32_MUL_D     = 1;
    localparam MAT_VEC_MUL_D  = 3;
    localparam INV_SQRT_D     = 4;
    localparam FP32_DOT3_D    = FP32_MUL_D + 2 * FP32_ADDSUB_D;
    localparam VEC_NORM_D     = FP32_DOT3_D + INV_SQRT_D + FP32_MUL_D;
    
    // Delays of signals, for alignment
    localparam P_SCALE_D      = MAT_VEC_MUL_D;
    localparam LP_INTENSITY_D = MAT_VEC_MUL_D + FP32_ADDSUB_D + FP32_DOT3_D + INV_SQRT_D + FP32_MUL_D;
    localparam LD_INTENSITY_D = VEC_NORM_D + FP32_DOT3_D;
    localparam LA_INTENSITY_D = VEC_NORM_D + FP32_DOT3_D + FP32_MUL_D;

    localparam LONGEST_PATH   = MAT_VEC_MUL_D + FP32_ADDSUB_D + VEC_NORM_D + FP32_MUL_D + FP32_ADDSUB_D;
    localparam PZ_INV_D       = LONGEST_PATH - MAT_VEC_MUL_D - FP32_MUL_D - INV_SQRT_D;
    localparam PXY_D          = PZ_INV_D;

    // ===============================
    //      Vertex transformation
    // ===============================

    /*
     * Transform vertex from model space (V) to view space (V_prime)
     * V_prime[4][1] = Model-View matrix m[4][4] X Vertex vector V[4][1]
     */
    localparam FP32_ONE   = 32'h3f800000;

    logic V_prime_valid_, V_prime_valid;
    logic [31:0] Vx_prime_, Vy_prime_, Vz_prime_, Vw_prime_;
    logic [31:0] Vx_prime, Vy_prime, Vz_prime, Vw_prime;

    mv_mul_4x4_fp32 i_mv_mul_4x4_fp32_V_m (
        .clk(clk),
        .rst(rst),

        .m_valid(m_valid_i),
        .m00_i  (m00_i), .m01_i(m01_i), .m02_i(m02_i), .m03_i(m03_i),
        .m10_i  (m10_i), .m11_i(m11_i), .m12_i(m12_i), .m13_i(m13_i),
        .m20_i  (m20_i), .m21_i(m21_i), .m22_i(m22_i), .m23_i(m23_i),
        .m30_i  (m30_i), .m31_i(m31_i), .m32_i(m32_i), .m33_i(m33_i),

        .in_valid(v_valid_i),
        .vx      (Vx_i), 
        .vy      (Vy_i), 
        .vz      (Vz_i), 
        .vw      (FP32_ONE),

        .out_valid(V_prime_valid_),
        .ox       (Vx_prime_), 
        .oy       (Vy_prime_), 
        .oz       (Vz_prime_), 
        .ow       (Vw_prime_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            V_prime_valid <= 1'b0;
            {Vx_prime, Vy_prime, Vz_prime, Vw_prime} <= 128'd0; 
        end else begin
            V_prime_valid <= V_prime_valid_;
            {Vx_prime, Vy_prime, Vz_prime, Vw_prime} <= {Vx_prime_, Vy_prime_, Vz_prime_, Vw_prime_};
        end
    end

    /*
     * Calculate depth of Vertex: 1 / Pz
     * 1 / Pz = 1 / sqrt(Vz' * Vz')
     * Using fast inverse square root algorithm to calculate
     * the inverse root of Vz'^2
     */
    localparam SQRT_MAGIC = 32'h5f3759df;

    logic Vz_prime_square_valid;
    logic [31:0] Vz_prime_square_, Vz_prime_square;

    // Calculate Vz'^2 = Vz' * Vz'
    fp32_mul i_fp32_mul_Vz_prime (
        .a       (Vz_prime),
        .b       (Vz_prime),
        .overflow(),
        .y       (Vz_prime_square_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            Vz_prime_square_valid <= 1'b0;
            Vz_prime_square       <= 32'd0; 
        end else begin
            Vz_prime_square_valid <= V_prime_valid;
            Vz_prime_square       <= Vz_prime_square_;
        end
    end

    // Calculate inverse-square-root of Vz'^2
    logic Vz_prime_inv_sqrt_valid_, Vz_prime_inv_sqrt_valid;
    logic [31:0] Vz_prime_inv_sqrt_, Vz_prime_inv_sqrt;

    fast_inv_sqrt #(
        .MAGIC(SQRT_MAGIC)
    ) i_fast_inv_sqrt_Vz_prime_square (
        .clk      (clk),
        .rst      (rst),
        .in_valid (Vz_prime_square_valid),
        .x_fp32   (Vz_prime_square),
        .out_valid(Vz_prime_inv_sqrt_valid_),
        .y_fp32   (Vz_prime_inv_sqrt_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            Vz_prime_inv_sqrt_valid <= 1'b0;
            Vz_prime_inv_sqrt       <= 32'd0; 
        end else begin
            Vz_prime_inv_sqrt_valid <= Vz_prime_inv_sqrt_valid_;
            Vz_prime_inv_sqrt       <= Vz_prime_inv_sqrt_;
        end
    end

    // delay 1 / Pz output for PZ_INV_D cycles to align to Brightness result 
    logic Pz_inv_valid;
    logic [31:0] Pz_inv;

    delay_reg #(
        .SIZE (32),
        .NUM  (1),
        .DELAY(PZ_INV_D)
    ) i_delay_reg_Pz_inv (
        .clk      (clk),
        .rst      (rst),
        .in_valid (Vz_prime_inv_sqrt_valid),
        .data_in  (Vz_prime_inv_sqrt),
        .out_valid(Pz_inv_valid),
        .data_out (Pz_inv)
    );

    /*
     * Vertex projection, calculate the coordinate to rasterizer
     * Px = Vx' * Px_scale * (1 / Pz)
     * Py = Vy' * Py_scale * (1 / Pz)
     */

    // Delay P_scale for MAT_VEC_MUL_D cycles, align with V'
    logic P_scale_valid;
    logic [31:0] Px_scale, Py_scale;

    delay_reg # (
        .SIZE (32),
        .NUM  (2),
        .DELAY(MAT_VEC_MUL_D)
    ) i_delay_reg_Pxy_scale (
        .clk      (clk),
        .rst      (rst),
        .in_valid (P_scale_valid_i),
        .data_in  ({Px_scale_i, Py_scale_i}),
        .out_valid(P_scale_valid),
        .data_out ({Px_scale, Py_scale})
    );

    // Calculate Vx' * Px_scale
    //           Vy' * Py_scale
    logic        V_prime_times_P_scale_valid;
    logic [31:0] Vx_prime_times_Px_scale_, Vx_prime_times_Px_scale;
    logic [31:0] Vy_prime_times_Py_scale_, Vy_prime_times_Py_scale;

    fp32_mul i_fp32_mul_Vx_prime_Px_scale (
        .a       (Vx_prime),
        .b       (Px_scale),
        .overflow(),
        .y       (Vx_prime_times_Px_scale_)
    );

    fp32_mul i_fp32_mul_Vy_prime_Py_scale (
        .a       (Vy_prime),
        .b       (Py_scale),
        .overflow(),
        .y       (Vy_prime_times_Py_scale_)
    );

    // wait calculating (1 / Pz) for INV_SQRT_D cycles
    delay_reg #(
        .SIZE (32),
        .NUM  (2),
        .DELAY(FP32_MUL_D + INV_SQRT_D)
    ) i_delay_reg_V_prime_times_P_scale (
        .clk      (clk),
        .rst      (rst),
        .in_valid (V_prime_valid && P_scale_valid),
        .data_in  ({Vx_prime_times_Px_scale_, Vy_prime_times_Py_scale_}),
        .out_valid(V_prime_times_P_scale_valid),
        .data_out ({Vx_prime_times_Px_scale, Vy_prime_times_Py_scale})
    );

    // Calculate Px = (Vx' * Px_scale) * (1 / Pz)
    //           Py = (Vy' * Py_scale) * (1 / Pz)
    logic [31:0] Px_, Py_;
    
    fp32_mul i_fp32_mul_V_Px_scale_Pz_inv_sqrt (
        .a       (Vz_prime_inv_sqrt),
        .b       (Vx_prime_times_Px_scale),
        .overflow(),
        .y       (Px_)
    );

    fp32_mul i_fp32_mul_V_Py_scale_Pz_inv_sqrt (
        .a       (Vz_prime_inv_sqrt),
        .b       (Vy_prime_times_Py_scale),
        .overflow(),
        .y       (Py_)
    );

    // delay Px, Py outputs for PXY_D cycles to align with Brightness result 
    logic        P_valid;
    logic [31:0] Px, Py;

    delay_reg #(
        .SIZE (32),
        .NUM  (2),
        .DELAY(PXY_D)
    ) i_delay_reg_P_xy (
        .clk      (clk),
        .rst      (rst),
        .in_valid (V_prime_times_P_scale_valid && Vz_prime_inv_sqrt_valid),
        .data_in  ({Px_, Py_}),
        .out_valid(P_valid),
        .data_out ({Px, Py})
    );

    // ===============================
    //   Normal Vector Normalization
    // ===============================
    logic N_hat_valid_, N_hat_valid;
    logic [31:0] Nx_hat_, Ny_hat_, Nz_hat_;
    logic [31:0] Nx_hat, Ny_hat, Nz_hat;
 
    // calculate normalized unit normal vector
    fp32_normalize3 #(
        .DOT_LAT(FP32_DOT3_D-1),
        .INV_LAT(INV_SQRT_D-1)
    ) i_fp32_normalize3_N (
        .clk      (clk),
        .rst      (rst),
        .in_valid (v_valid_i),
        .vx       (Nx_i),
        .vy       (Ny_i),
        .vz       (Nz_i),
        .out_valid(N_hat_valid_),
        .ox       (Nx_hat_),
        .oy       (Ny_hat_),
        .oz       (Nz_hat_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            N_hat_valid <= 1'b0;
            Nx_hat      <= 32'd0;
            Ny_hat      <= 32'd0;
            Nz_hat      <= 32'd0;
        end else begin
            N_hat_valid <= N_hat_valid_;
            Nx_hat      <= Nx_hat_;
            Ny_hat      <= Ny_hat_;
            Nz_hat      <= Nz_hat_;
        end
    end

    // ===============================
    //     Brightness Calculation
    // ===============================
    // Calculate the brightness of each vertex influenced by
    // 1. Point light
    // 2. Direction light
    // 3. Ambient light

    /*
     * Calculate the brightness component caused by a Point light source
     */

    // delay Point light coordinate inputs for MAT_VEC_MUL_D cycle
    // align with V_prime_valid
    logic Lp_valid, Lp_vec_valid;
    logic [31:0] Lpx, Lpy, Lpz;

    delay_reg #(
        .SIZE (32),
        .NUM  (3),
        .DELAY(MAT_VEC_MUL_D)
    ) i_delay_reg_Lp (
        .clk      (clk),
        .rst      (rst),
        .in_valid (Lp_valid_i),
        .data_in  ({Lpx_i, Lpy_i, Lpz_i}),
        .out_valid(Lp_valid),
        .data_out ({Lpx, Lpy, Lpz})
    );

    // Point light coordinate minus V' coordinate,
    // making a vector from vertex to the light
    logic [31:0] Lpx_sub_Vx_prime_, Lpy_sub_Vy_prime_, Lpz_sub_Vz_prime_;
    logic [31:0] Lpx_vec, Lpy_vec, Lpz_vec;
    
    // Substract V' from Point light to get a vector
    fp32_addsub i_fp32_addsub_Lpx_sub_Vx_prime(
        .sub     (1'b1),
        .a       (Lpx),
        .b       (Vx_prime),
        .overflow(),
        .y       (Lpx_sub_Vx_prime_)
    );
    
    fp32_addsub i_fp32_addsub_Lpy_sub_Vy_prime(
        .sub     (1'b1),
        .a       (Lpy),
        .b       (Vy_prime),
        .overflow(),
        .y       (Lpy_sub_Vy_prime_)
    );
    
    fp32_addsub i_fp32_addsub_Lpz_sub_Vz_prime(
        .sub     (1'b1),
        .a       (Lpz),
        .b       (Vz_prime),
        .overflow(),
        .y       (Lpz_sub_Vz_prime_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            Lp_vec_valid <= 1'b0;
            Lpx_vec      <= 32'd0;
            Lpy_vec      <= 32'd0;
            Lpz_vec      <= 32'd0;
        end else begin
            Lp_vec_valid <= Lp_valid;
            Lpx_vec      <= Lpx_sub_Vx_prime_;
            Lpy_vec      <= Lpy_sub_Vy_prime_;
            Lpz_vec      <= Lpz_sub_Vz_prime_;
        end
    end

    // Delay Lp_vec for later dot product with N_hat
    logic Lp_vec_delay_valid;
    logic [31:0] Lpx_vec_delay, Lpy_vec_delay, Lpz_vec_delay;

    delay_reg # (
        .SIZE (32),
        .NUM  (3),
        .DELAY(VEC_NORM_D - MAT_VEC_MUL_D - FP32_ADDSUB_D)
    ) i_delay_reg_Lp_vec (
        .clk      (clk),
        .rst      (rst),
        .in_valid(Lp_vec_valid),
        .data_in  ({Lpx_vec, Lpy_vec, Lpz_vec}),
        .out_valid(Lp_vec_delay_valid),
        .data_out ({Lpx_vec_delay, Lpy_vec_delay, Lpz_vec_delay})
    );

    // Normalize the Point light vector, becoming Lp_prime_hat
    // then calculate dot product with N_hat
    // fuse these 2 operations into:
    // 1. Lp_vec dot product with Lp_vec
    // 2. inv_sqrt(Lp_vec_dot_Lp_vec)
    // 2. Lp_vec dot product with N_hat
    // 3. times two results of step 2 together
    
    // 1. Lp_vec dot Lp_vec
    logic Lp_vec_dot_Lp_vec_valid_, Lp_vec_dot_Lp_vec_valid;
    logic [31:0] Lp_vec_dot_Lp_vec_, Lp_vec_dot_Lp_vec;

    fp32_dot3 i_fp32_dot3_Lp_Lp (
        .clk      (clk),
        .rst      (rst),
        .in_valid (Lp_vec_valid),
        .ax       (Lpx_vec),
        .ay       (Lpy_vec),
        .az       (Lpz_vec),
        .bx       (Lpx_vec),
        .by       (Lpy_vec),
        .bz       (Lpz_vec),
        .out_valid(Lp_vec_dot_Lp_vec_valid_),
        .y        (Lp_vec_dot_Lp_vec_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            Lp_vec_dot_Lp_vec_valid <= 1'b0;
            Lp_vec_dot_Lp_vec       <= 32'd0;
        end else begin
            Lp_vec_dot_Lp_vec_valid <= Lp_vec_dot_Lp_vec_valid_;
            Lp_vec_dot_Lp_vec       <= Lp_vec_dot_Lp_vec_;
        end
    end

    // 2. inv_sqrt(Lp_vec_dot_Lp_vec)
    logic Lp_inv_valid_, Lp_inv_valid;
    logic [31:0] Lp_inv_, Lp_inv;

    fast_inv_sqrt i_fast_inv_sqrt_Lp_dot_Lp (
        .clk      (clk),
        .rst      (rst),
        .in_valid (Lp_vec_dot_Lp_vec_valid),
        .x_fp32   (Lp_vec_dot_Lp_vec),
        .out_valid(Lp_inv_valid_),
        .y_fp32   (Lp_inv_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            Lp_inv_valid <= 1'b0;
            Lp_inv       <= 32'd0;
        end else begin
            Lp_inv_valid <= Lp_inv_valid_;
            Lp_inv       <= Lp_inv_;
        end
    end

    // 2. Lp_vec dot product with N_hat
    logic Lp_vec_dot_N_hat_valid_, Lp_vec_dot_N_hat_valid;
    logic [31:0] Lp_vec_dot_N_hat_, Lp_vec_dot_N_hat;

    fp32_dot3 i_Lp_vec_dot_N_hat (
        .clk      (clk),
        .rst      (rst),
        .in_valid (N_hat_valid && Lp_vec_delay_valid),
        .ax       (Lpx_vec_delay),
        .ay       (Lpy_vec_delay),
        .az       (Lpz_vec_delay),
        .bx       (Nx_hat),
        .by       (Ny_hat),
        .bz       (Nz_hat),
        .out_valid(Lp_vec_dot_N_hat_valid_),
        .y        (Lp_vec_dot_N_hat_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            Lp_vec_dot_N_hat_valid <= 1'b0;
            Lp_vec_dot_N_hat       <= 32'd0;
        end else begin
            Lp_vec_dot_N_hat_valid <= Lp_vec_dot_N_hat_valid_;
            Lp_vec_dot_N_hat       <= Lp_vec_dot_N_hat_;
        end
    end

    // 3. times two results of step 2 together
    logic Lp_hat_dot_N_hat_valid;
    logic [31:0] Lp_hat_dot_N_hat_, Lp_hat_dot_N_hat;

    fp32_mul i_fp32_mul_Lp_hat_dot_N_hat (
        .a       (Lp_inv),
        .b       (Lp_vec_dot_N_hat),
        .overflow(),
        .y       (Lp_hat_dot_N_hat_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            Lp_hat_dot_N_hat_valid <= 1'b0;
            Lp_hat_dot_N_hat       <= 32'd0;
        end else begin
            Lp_hat_dot_N_hat_valid <= (Lp_vec_dot_N_hat_valid && Lp_inv_valid);
            Lp_hat_dot_N_hat       <= Lp_hat_dot_N_hat_;
        end
    end

    // Delay Lp_intensity_i for LP_INTENSITY_D cycles
    logic Lp_intensity_valid;
    logic [31:0] Lp_intensity;

    delay_reg # (
        .SIZE(32),
        .NUM(1),
        .DELAY(LP_INTENSITY_D)
    ) i_delay_reg_Lp_intensity (
        .clk      (clk),
        .rst      (rst),
        .in_valid (Lp_valid_i),
        .data_in  (Lp_intensity_i),
        .out_valid(Lp_intensity_valid),
        .data_out (Lp_intensity)
    );

    // Compare Lp_hat_dot_N_hat with 0
    // if <= 0, clamp the Point light component of brightness to 0
    // if > 0, multiply the intensity to get Point light component
    logic Lp_comp_valid;
    logic [31:0] Lp_dot_times_intensity_;
    logic [31:0] Lp_comp_, Lp_comp;
    
    fp32_mul i_Lp_dot_times_intensity (
        .a       (Lp_hat_dot_N_hat),
        .b       (Lp_intensity),
        .overflow(),
        .y       (Lp_dot_times_intensity_)
    );

    always_comb begin
        if(Lp_hat_dot_N_hat[31]) begin // <= 0
            Lp_comp_ = 32'd0;
        end else begin // > 0
            Lp_comp_ = Lp_dot_times_intensity_;
        end
    end

    always_ff @(posedge clk) begin
        if(rst) begin
            Lp_comp_valid <= 1'b0;
            Lp_comp       <= 32'd0;
        end else begin
            Lp_comp_valid <= (Lp_hat_dot_N_hat_valid && Lp_intensity_valid);
            Lp_comp       <= Lp_comp_;
        end
    end

    /*
     * Calculate the brightness component caused by a Direction light source
     */

    // Normalize Direction light vector
    logic Ld_hat_valid_, Ld_hat_valid;
    logic [31:0] Ldx_hat_, Ldy_hat_, Ldz_hat_;
    logic [31:0] Ldx_hat, Ldy_hat, Ldz_hat;

    fp32_normalize3 # (
        .DOT_LAT(FP32_DOT3_D-1),
        .INV_LAT(INV_SQRT_D-1)
    ) i_fp32_normalize3_Ld (
        .clk      (clk),
        .rst      (rst),
        .in_valid (Ld_valid_i),
        .vx       (Ldx_i),
        .vy       (Ldy_i),
        .vz       (Ldz_i),
        .out_valid(Ld_hat_valid_),
        .ox       (Ldx_hat_),
        .oy       (Ldy_hat_),
        .oz       (Ldz_hat_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            Ld_hat_valid <= 1'b0;
            Ldx_hat      <= 32'd0;
            Ldy_hat      <= 32'd0;
            Ldz_hat      <= 32'd0;
        end else begin
            Ld_hat_valid <= Ld_hat_valid_;
            Ldx_hat      <= Ldx_hat_;
            Ldy_hat      <= Ldy_hat_;
            Ldz_hat      <= Ldz_hat_;
        end
    end

    // Calculate dot product of normalized Direction light vector with
    // unit normal vector of vertex
    logic Ld_hat_dot_N_hat_valid_, Ld_hat_dot_N_hat_valid;
    logic [31:0] Ld_hat_dot_N_hat_, Ld_hat_dot_N_hat;

    fp32_dot3 i_fp32_dot3_Ld_hat_N_hat (
        .clk      (clk),
        .rst      (rst),
        .in_valid (Ld_hat_valid),
        .ax       (Ldx_hat),
        .ay       (Ldy_hat),
        .az       (Ldz_hat),
        .bx       (Nx_hat),
        .by       (Ny_hat),
        .bz       (Nz_hat),
        .out_valid(Ld_hat_dot_N_hat_valid_),
        .y        (Ld_hat_dot_N_hat_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            Ld_hat_dot_N_hat_valid <= 1'b0;
            Ld_hat_dot_N_hat       <= 32'd0;
        end else begin
            Ld_hat_dot_N_hat_valid <= Ld_hat_dot_N_hat_valid_;
            Ld_hat_dot_N_hat       <= Ld_hat_dot_N_hat_;
        end
    end

    // Delay Ld_intensity_i for LD_INTENSITY_D cycles
    logic Ld_intensity_valid;
    logic [31:0] Ld_intensity;

    delay_reg # (
        .SIZE (32),
        .NUM  (1),
        .DELAY(LD_INTENSITY_D)
    ) i_delay_reg_Ld_intensity (
        .clk      (clk),
        .rst      (rst),
        .in_valid (Ld_valid_i),
        .data_in  (Ld_intensity_i),
        .out_valid(Ld_intensity_valid),
        .data_out (Ld_intensity)
    );

    // Compare Ld_hat_dot_N_hat with 0
    // if <= 0, clamp the Direction light component of brightness to 0
    // if > 0, multiply the intensity to get Direction light component
    logic Ld_comp_valid;
    logic [31:0] Ld_dot_times_intensity_;
    logic [31:0] Ld_comp_, Ld_comp;
    
    fp32_mul i_Ld_dot_times_intensity (
        .a       (Ld_hat_dot_N_hat),
        .b       (Ld_intensity),
        .overflow(),
        .y       (Ld_dot_times_intensity_)
    );

    always_comb begin
        if(Ld_hat_dot_N_hat[31]) begin // <= 0
            Ld_comp_ = 32'd0;
        end else begin // > 0
            Ld_comp_ = Ld_dot_times_intensity_;
        end
    end

    always_ff @(posedge clk) begin
        if(rst) begin
            Ld_comp_valid <= 1'b0;
            Ld_comp       <= 32'd0;
        end else begin
            Ld_comp_valid <= (Ld_hat_dot_N_hat_valid && Ld_intensity_valid);
            Ld_comp       <= Ld_comp_;
        end
    end

    /*
     * Add components of Point light, Direction light, Ambient light
     * together to get the brightness of a vertex
     */
    
    // Delay La_intensity_i for LA_INTENSITY_D cycles
    logic La_comp_valid;
    logic [31:0] La_comp;

    delay_reg # (
        .SIZE (32),
        .NUM  (1),
        .DELAY(LA_INTENSITY_D)
    ) i_delay_reg_La_intensity (
        .clk      (clk),
        .rst      (rst),
        .in_valid (La_valid_i),
        .data_in  (La_intensity_i),
        .out_valid(La_comp_valid),
        .data_out (La_comp)
    );

    // Add Direction light component and Ambient light component first
    logic Ld_comp_add_La_comp_valid;
    logic [31:0] Ld_comp_add_La_comp_, Ld_comp_add_La_comp;
    
    fp32_addsub i_fp32_addsub_Ld_comp_La_comp (
        .sub     (1'b0),
        .a       (Ld_comp),
        .b       (La_comp),
        .overflow(),
        .y       (Ld_comp_add_La_comp_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            Ld_comp_add_La_comp_valid <= 1'b0;
            Ld_comp_add_La_comp       <= 32'd0;
        end else begin
            Ld_comp_add_La_comp_valid <= (Ld_comp_valid && La_comp_valid);
            Ld_comp_add_La_comp       <= Ld_comp_add_La_comp_;
        end
    end

    // Add sum of Direction light component and Ambient light component
    // to Point light component
    logic brightness_valid;
    logic [31:0] brightness_, brightness;

    fp32_addsub i_fp32_addsub_Ld_comp_La_comp_Lp_comp (
        .sub     (1'b0),
        .a       (Ld_comp_add_La_comp),
        .b       (Lp_comp),
        .overflow(),
        .y       (brightness_)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            brightness_valid    <= 1'b0;
            brightness <= 32'd0;
        end else begin
            brightness_valid <= (Ld_comp_add_La_comp_valid && Lp_comp_valid);
            brightness       <= brightness_;
        end
    end

    // ===============================
    //             Outputs
    // ===============================
    always_comb begin
        out_valid_o  = (Pz_inv_valid && P_valid && brightness_valid);
        Pz_inv_o     = Pz_inv;
        Px_o         = Px;
        Py_o         = Py;
        brightness_o = brightness;
    end

endmodule