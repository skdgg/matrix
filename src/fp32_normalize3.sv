`ifndef FP32_NORMALIZE3_SV
`define FP32_NORMALIZE3_SV

`include "fp32_mul.sv"
`include "fp32_dot3.sv"
`include "fast_inv_sqrt.sv"

module fp32_normalize3 #(
    // dot: 2cycle valid + 1cycle latch(comb y) => 3
    // inv: 3cycle valid + 1cycle latch(comb y) => 4
    parameter int DOT_LAT = 2,
    parameter int INV_LAT = 3
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

    // =================================================
    // Stage A: dot(v,v)
    // =================================================
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

    // =================================================
    // Delay v by DOT_LAT cycles so that dv_*[DOT_LAT]
    // aligns with dot_valid_d1 (the latched len2 cycle)
    // =================================================
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
    // Stage B: latch dot output (because len2_fp32 is comb)
    // dot_valid_d1 is the "real" valid for feeding inv
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

    // =================================================
    // Stage C: invlen = fast_inv_sqrt(len2_latched)
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
    // Stage C.5: latch inv output (because invlen_fp32 is comb)
    // inv_valid_d1 is the "real" valid for mul stage
    // =================================================
    logic [31:0] invlen_latched;
    logic        inv_valid_d1;

    always_ff @(posedge clk) begin
        if (rst) begin
            invlen_latched <= 32'd0;
            inv_valid_d1   <= 1'b0;
        end else begin
            inv_valid_d1 <= inv_valid;          

            if (inv_valid) begin
                invlen_latched <= invlen_fp32;  
            end
        end
    end

    assign out_valid = inv_valid_d1;

    // =================================================
    // Delay vector by INV_LAT cycles to align with inv_valid_d1
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
                ew_x[0] <= dv_x[DOT_LAT];
                ew_y[0] <= dv_y[DOT_LAT];
                ew_z[0] <= dv_z[DOT_LAT];
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
    // Use invlen_latched (registered) + inv_valid_d1
    // =================================================
    logic [31:0] ox_c, oy_c, oz_c;
    logic ovx, ovy, ovz;

    fp32_mul u_mx(.a(ew_x[INV_LAT]), .b(invlen_latched), .overflow(ovx), .y(ox_c));
    fp32_mul u_my(.a(ew_y[INV_LAT]), .b(invlen_latched), .overflow(ovy), .y(oy_c));
    fp32_mul u_mz(.a(ew_z[INV_LAT]), .b(invlen_latched), .overflow(ovz), .y(oz_c));

    assign ox = ox_c;
    assign oy = oy_c;
    assign oz = oz_c;


endmodule

`endif // FP32_NORMALIZE3_SV