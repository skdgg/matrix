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
    // Stage 1: latch mul results (FF)  + valid
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
    // Stage 2: s0 = p0 + p1   (fp32_addsub has clk/rst)
    // -------------------------------------------------
    logic [31:0] s0;
    logic dummy_ov3;

    fp32_addsub u3(
        .clk(clk), .rst(rst), .sub(1'b0),
        .a(p0), .b(p1),
        .overflow(dummy_ov3),
        .y(s0)
    );

    // -------------------------------------------------
    // Stage 2.5: explicit FF cut (like your 4x4 design)
    // - also aligns p2 with s0 timing
    // -------------------------------------------------
    logic [31:0] s0_r, p2_r;
    logic        v2;

    always_ff @(posedge clk) begin
        if (rst) begin
            v2   <= 1'b0;
            s0_r <= 32'd0;
            p2_r <= 32'd0;
        end else begin
            v2   <= v1;    // align valid with s0_r/p2_r
            s0_r <= s0;    // cut timing path u3->u4
            p2_r <= p2;    // align p2 with s0
        end
    end

    // -------------------------------------------------
    // Stage 3: y = s0_r + p2_r  (fp32_addsub has 1-cycle)
    // -------------------------------------------------
    logic dummy_ov4;

    fp32_addsub u4(
        .clk(clk), .rst(rst), .sub(1'b0),
        .a(s0_r), .b(p2_r),
        .overflow(dummy_ov4),
        .y(y)
    );
    logic        v3;
    always_ff @(posedge clk) begin
        if (rst) v3 <= 1'b0;
        else     v3 <= v2;
    end
    // -------------------------------------------------
    // Stage 4: output valid (align with u4 output)
    // -------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) out_valid <= 1'b0;
        else     out_valid <= v3;
    end

endmodule
