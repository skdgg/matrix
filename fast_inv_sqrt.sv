`include "../src/fp32_mul.sv"
`include "../src/fp32_addsub.sv"

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
    // Stage 0: bit hack
    // =====================================================
    logic        v0;
    logic [31:0] x0, y0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v0 <= 1'b0;
            x0 <= 32'd0;
            y0 <= 32'd0;
        end else begin
            v0 <= in_valid;
            x0 <= x_fp32;
            y0 <= MAGIC - (x_fp32 >> 1);
        end
    end

    // =====================================================
    // Stage 1: parallel mul (x2, yy)
    // =====================================================
    logic        v1;
    logic [31:0] y0_1;
    logic [31:0] x2_s1, yy_s1;
    logic [31:0] x2_1, yy_1;   

    fp32_mul u_mul_x2 (.a(x0), .b(FP32_HALF), .y(x2_s1));
    fp32_mul u_mul_yy (.a(y0), .b(y0),       .y(yy_s1));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1   <= 1'b0;
            y0_1 <= 32'd0;
            x2_1 <= 32'd0;
            yy_1 <= 32'd0;
        end else begin
            v1   <= v0;
            y0_1 <= y0;
            x2_1 <= x2_s1; 
            yy_1 <= yy_s1; 
        end
    end

    // =====================================================
    // Stage 2: t2 = x2 * yy 
    // =====================================================
    logic        v2;
    logic [31:0] y0_2;
    logic [31:0] t2_s2;
    logic [31:0] t2_2;  

    fp32_mul u_mul_t2 (.a(x2_1), .b(yy_1), .y(t2_s2));

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
    // Stage 3: t3 = 1.5 - t2 (1-cycle latency)
    // =====================================================
    logic        v3;
    logic [31:0] y0_3, t3_s3;

    fp32_addsub u_sub (
        .clk(clk),
        .rst(~rst_n),
        .sub(1'b1),
        .a(FP32_THREEHALFS),
        .b(t2_2),            
        .y(t3_s3)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v3   <= 1'b0;
            y0_3 <= '0;
        end else begin
            v3   <= v2;   
            y0_3 <= y0_2; 
        end
    end

    // =====================================================
    // Stage 4: y = y0 * t3
    // =====================================================

    logic [31:0] y_s4;

    fp32_mul u_mul_out (
        .a(y0_3),
        .b(t3_s3),
        .y(y_s4)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_fp32   <= 32'h0;
            out_valid <= 1'b0;
        end else begin
            y_fp32   <= y_s4;
            out_valid <= v3;
        end
    end


endmodule
