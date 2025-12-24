`include "fp32_mul.sv"
`include "fp32_dot3.sv"
`include "fast_inv_sqrt.sv"

module fp32_normalize3 #(
    parameter int DOT_LAT = 4,
    parameter int INV_LAT = 4
)(
    input  logic        clk,
    input  logic        rst,

    input  logic        in_valid,
    input  logic [31:0] vx,
    input  logic [31:0] vy,
    input  logic [31:0] vz,

    output logic        out_valid,
    output logic [31:0] ox,
    output logic [31:0] oy,
    output logic [31:0] oz
);

    logic        dot_valid;
    logic [31:0] len2_fp32;

    fp32_dot3 u_dot (
        .clk      (clk),
        .rst      (rst),
        .in_valid (in_valid),
        .ax       (vx), .ay(vy), .az(vz),
        .bx       (vx), .by(vy), .bz(vz),
        .out_valid(dot_valid),
        .y        (len2_fp32)
    );

    logic [DOT_LAT:0] dv_valid;
    logic [31:0]      dv_x [0:DOT_LAT];
    logic [31:0]      dv_y [0:DOT_LAT];
    logic [31:0]      dv_z [0:DOT_LAT];

    integer i;
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i <= DOT_LAT; i++) begin
                dv_valid[i] <= 1'b0;
                dv_x[i]     <= 32'd0;
                dv_y[i]     <= 32'd0;
                dv_z[i]     <= 32'd0;
            end
        end else begin
            dv_valid[0] <= in_valid;
            dv_x[0]     <= vx;
            dv_y[0]     <= vy;
            dv_z[0]     <= vz;

            for (i = 1; i <= DOT_LAT; i++) begin
                dv_valid[i] <= dv_valid[i-1];
                dv_x[i]     <= dv_x[i-1];
                dv_y[i]     <= dv_y[i-1];
                dv_z[i]     <= dv_z[i-1];
            end
        end
    end

    // =================================================
    // FIX1: latch len2 + delay dot_valid by 1 cycle
    // =================================================
    logic [31:0] len2_latched;
    logic        dot_valid_d1;

    always_ff @(posedge clk) begin
        if (rst) begin
            len2_latched <= 32'd0;
            dot_valid_d1 <= 1'b0;
        end else begin
            dot_valid_d1 <= dot_valid;
            if (dot_valid) begin
                len2_latched <= len2_fp32;
            end
        end
    end

    logic [31:0] v_dot_x, v_dot_y, v_dot_z;

    always_ff @(posedge clk) begin
        if (rst) begin
            v_dot_x <= 32'd0;
            v_dot_y <= 32'd0;
            v_dot_z <= 32'd0;
        end else if (dot_valid) begin
            v_dot_x <= dv_x[DOT_LAT];
            v_dot_y <= dv_y[DOT_LAT];
            v_dot_z <= dv_z[DOT_LAT];
        end
    end

    // =================================================
    // Stage C: invlen = fast_inv_sqrt(len2)
    // =================================================
    logic        inv_valid;
    logic [31:0] invlen_fp32;

    fast_inv_sqrt u_inv (
        .clk      (clk),
        .rst_n    (~rst),
        .in_valid (dot_valid_d1),
        .x_fp32   (len2_latched),
        .out_valid(inv_valid),
        .y_fp32   (invlen_fp32)
    );

    // =================================================
    // Delay vector by INV_LAT cycles to align with inv_valid
    // =================================================
    logic [INV_LAT:0] ew_valid;
    logic [31:0]      ew_x [0:INV_LAT];
    logic [31:0]      ew_y [0:INV_LAT];
    logic [31:0]      ew_z [0:INV_LAT];

    integer j;
    always_ff @(posedge clk) begin
        if (rst) begin
            for (j = 0; j <= INV_LAT; j++) begin
                ew_valid[j] <= 1'b0;
                ew_x[j]     <= 32'd0;
                ew_y[j]     <= 32'd0;
                ew_z[j]     <= 32'd0;
            end
        end else begin
            ew_valid[0] <= dot_valid_d1;
            if (dot_valid_d1) begin
                ew_x[0] <= v_dot_x;
                ew_y[0] <= v_dot_y;
                ew_z[0] <= v_dot_z;
            end

            for (j = 1; j <= INV_LAT; j++) begin
                ew_valid[j] <= ew_valid[j-1];
                ew_x[j]     <= ew_x[j-1];
                ew_y[j]     <= ew_y[j-1];
                ew_z[j]     <= ew_z[j-1];
            end
        end
    end

    // =================================================
    // Stage D: v_hat = v * invlen (mul is comb)
    // =================================================
    logic [31:0] ox_c, oy_c, oz_c;
    logic ovx, ovy, ovz;

    fp32_mul u_mx(.a(ew_x[INV_LAT]), .b(invlen_fp32), .overflow(ovx), .y(ox_c));
    fp32_mul u_my(.a(ew_y[INV_LAT]), .b(invlen_fp32), .overflow(ovy), .y(oy_c));
    fp32_mul u_mz(.a(ew_z[INV_LAT]), .b(invlen_fp32), .overflow(ovz), .y(oz_c));


    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            ox        <= 32'd0;
            oy        <= 32'd0;
            oz        <= 32'd0;
        end else begin
            out_valid <= inv_valid;
            ox <= ox_c;
            oy <= oy_c;
            oz <= oz_c;
        end
    end

endmodule
