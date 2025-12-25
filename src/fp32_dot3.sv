`ifndef FP32_DOT3_SV
`define FP32_DOT3_SV

`include "fp32_mul.sv"
`include "fp32_addsub.sv"
module fp32_dot3 (
    input  logic        clk,
    input  logic        rst,
    input  logic        in_valid,

    input  logic [31:0] ax, ay, az,
    input  logic [31:0] bx, by, bz,

    output logic        out_valid,
    output logic [31:0] y
);

    // -------------------------------------------------
    // Stage 0: 3 mul (combinational)
    // -------------------------------------------------
    logic [31:0] p0_c, p1_c, p2_c;
    logic dummy_ov0, dummy_ov1, dummy_ov2;

    fp32_mul u0(.a(ax), .b(bx), .overflow(dummy_ov0), .y(p0_c));
    fp32_mul u1(.a(ay), .b(by), .overflow(dummy_ov1), .y(p1_c));
    fp32_mul u2(.a(az), .b(bz), .overflow(dummy_ov2), .y(p2_c));

    // -------------------------------------------------
    // Stage 1: latch mul results (FF) + valid
    // -------------------------------------------------
    logic [31:0] p0, p1, p2;
    logic        v1;

    always_ff @(posedge clk) begin
        if (rst) begin
            v1 <= 1'b0;
            p0 <= 32'd0;
            p1 <= 32'd0;
            p2 <= 32'd0;
        end else begin
            v1 <= in_valid;
            p0 <= p0_c;
            p1 <= p1_c;
            p2 <= p2_c;
        end
    end

    // -------------------------------------------------
    // Stage 2: s0 = p0 + p1 (COMB addsub) then FF cut
    // -------------------------------------------------
    logic [31:0] s0_c;
    logic        dummy_ov3;

    fp32_addsub u3(
        .sub(1'b0),
        .a  (p0),
        .b  (p1),
        .overflow(dummy_ov3),
        .y  (s0_c)
    );

    logic [31:0] s0;
    logic [31:0] p2_d1;   // align p2 with s0 after this stage

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid    <= 1'b0;
            s0    <= 32'd0;
            p2_d1 <= 32'd0;
        end else begin
            out_valid    <= v1;
            s0    <= s0_c;
            p2_d1 <= p2;
        end
    end

    // -------------------------------------------------
    // Stage 3: y = s0 + p2_d1 (COMB addsub) then FF cut
    // -------------------------------------------------
    logic [31:0] y_c;
    logic        dummy_ov4;

    fp32_addsub u4(
        .sub(1'b0),
        .a  (s0),
        .b  (p2_d1),
        .overflow(dummy_ov4),
        .y  (y)
    );


endmodule
`endif // FP32_DOT3_SV