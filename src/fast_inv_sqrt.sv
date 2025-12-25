`ifndef FAST_INV_SQRT_SV
`define FAST_INV_SQRT_SV

`include "fp32_mul.sv"
`include "fp32_addsub.sv"

module fast_inv_sqrt #(
    parameter logic [31:0] MAGIC = 32'h5f3759df
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        in_valid,
    input  logic [31:0] x_fp32,

    output logic        out_valid,
    output logic [31:0] y_fp32
);

    localparam logic [31:0] FP32_HALF       = 32'h3f000000; // 0.5
    localparam logic [31:0] FP32_THREEHALFS = 32'h3fc00000; // 1.5

    // =====================================================
    // Stage 0 (COMB): bit hack
    // =====================================================
    logic [31:0] y0_c;
    assign y0_c = MAGIC - (x_fp32 >> 1);

    // =====================================================
    // Stage 1 (FF): x2=x/2, yy=y0*y0, and latch y0
    // =====================================================
    logic        v1;
    logic [31:0] y0_1;
    logic [31:0] x2_s1, yy_s1;
    logic [31:0] x2_1, yy_1;

    fp32_mul u_mul_x2 (.a(x_fp32), .b(FP32_HALF), .overflow(), .y(x2_s1));
    fp32_mul u_mul_yy (.a(y0_c),   .b(y0_c),      .overflow(), .y(yy_s1));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1   <= 1'b0;
            y0_1 <= 32'd0;
            x2_1 <= 32'd0;
            yy_1 <= 32'd0;
        end else begin
            v1   <= in_valid;
            y0_1 <= y0_c;
            x2_1 <= x2_s1;
            yy_1 <= yy_s1;
        end
    end

    // =====================================================
    // Stage 2 (FF): t2 = x2 * yy, latch y0
    // =====================================================
    logic        v2;
    logic [31:0] y0_2;
    logic [31:0] t2_s2;
    logic [31:0] t2_2;

    fp32_mul u_mul_t2 (.a(x2_1), .b(yy_1), .overflow(), .y(t2_s2));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v2   <= 1'b0;
            y0_2 <= 32'd0;
            t2_2 <= 32'd0;
        end else begin
            v2   <= v1;
            y0_2 <= y0_1;
            t2_2 <= t2_s2;
        end
    end

    // =====================================================
    // Stage 3 (COMB): t3 = 1.5 - t2
    // =====================================================
    logic [31:0] t3_c;
    fp32_addsub u_sub (
        .sub(1'b1),
        .a  (FP32_THREEHALFS),
        .b  (t2_2),
        .overflow(),
        .y  (t3_c)
    );

    // =====================================================
    // Stage 3.5 (FF): latch t3 and y0, generate out_valid
    // (因為最後乘法是 comb，TB 通常用 out_valid 在 posedge 取樣)
    // =====================================================
    logic        v3;
    logic [31:0] y0_3, t3_3;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v3       <= 1'b0;
            y0_3     <= 32'd0;
            t3_3     <= 32'd0;
            out_valid<= 1'b0;
        end else begin
            v3       <= v2;
            y0_3     <= y0_2;
            t3_3     <= t3_c;
            out_valid<= v2;  
        end
    end

    // =====================================================
    // Stage 4 (COMB): y = y0 * t3
    // =====================================================
    fp32_mul u_mul_out (
        .a(y0_3),
        .b(t3_3),
        .overflow(),
        .y(y_fp32)
    );

endmodule
`endif // FAST_INV_SQRT_SV