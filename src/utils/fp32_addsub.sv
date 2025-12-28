// FP32 Add/Sub (PURE COMB, NO rounding; TRUNCATE after normalization)
// - sub=0: y = a + b
// - sub=1: y = a - b
// - denorm: treated as exp=1, hidden=0
// - exact zero => +0
`ifndef FP32_ADDSUB_SV
`define FP32_ADDSUB_SV

module fp32_addsub (
    input  logic        sub,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        overflow,
    output logic [31:0] y
);

    logic        sign_a, sign_b;
    logic [ 7:0] exp_a_raw , exp_b_raw;
    logic [ 7:0] exp_a_eff , exp_b_eff;
    logic [22:0] frac_a_raw, frac_b_raw;
    logic        a_is_zero, b_is_zero;
    logic        a_is_denorm, b_is_denorm;

    logic [ 7:0] exp_a , exp_b;
    logic [31:0] mant_a, mant_b;

    logic [ 7:0] exp_diff, exp_res;
    logic [31:0] mant_a_align, mant_b_align;

    logic [31:0] alu_mant_res, mant_sub, mant_add;
    logic        alu_sign_res;

    logic        exact_zero_add;

    logic [ 4:0] leading_zeros;
    logic [31:0] alu_mant_norm;
    logic [ 8:0] alu_exp_norm;

    logic        alu_sign_out;
    logic [22:0] alu_mant_out;
    logic [ 8:0] alu_exp_out;

    // Step 1. Breakdown（hidden bit + denorm）
    always_comb begin
        sign_a      = a[31];
        sign_b      = sub ? ~b[31] : b[31];

        exp_a_raw   = a[30:23];
        exp_b_raw   = b[30:23];
        frac_a_raw  = a[22:0];
        frac_b_raw  = b[22:0];

        a_is_zero   = (exp_a_raw == 8'd0) && (frac_a_raw == 23'd0);
        b_is_zero   = (exp_b_raw == 8'd0) && (frac_b_raw == 23'd0);
        a_is_denorm = (exp_a_raw == 8'd0) && (frac_a_raw != 23'd0);
        b_is_denorm = (exp_b_raw == 8'd0) && (frac_b_raw != 23'd0);

        exp_a_eff   = (exp_a_raw == 8'd0) ? 8'd1 : exp_a_raw;
        exp_b_eff   = (exp_b_raw == 8'd0) ? 8'd1 : exp_b_raw;

        exp_a       = exp_a_eff;
        exp_b       = exp_b_eff;

        mant_a      = (exp_a_raw == 8'd0)
                        ? {2'b00, frac_a_raw, 7'd0}
                        : {2'b01, frac_a_raw, 7'd0};

        mant_b      = (exp_b_raw == 8'd0)
                        ? {2'b00, frac_b_raw, 7'd0}
                        : {2'b01, frac_b_raw, 7'd0};
    end

    // Step 2. Align exponent
    always_comb begin
        if (exp_a > exp_b) begin
            exp_res      = exp_a;
            exp_diff     = exp_a - exp_b;
            mant_a_align = mant_a;
            mant_b_align = mant_b >> exp_diff;
        end else begin
            exp_res      = exp_b;
            exp_diff     = exp_b - exp_a;
            mant_a_align = mant_a >> exp_diff;
            mant_b_align = mant_b;
        end
    end

    // Step 3. Add/Sub mantissa
    always_comb begin
        mant_add = mant_a_align + mant_b_align;
        mant_sub = mant_a_align - mant_b_align;

        if (sign_a == sign_b) begin
            alu_sign_res = sign_a;
            alu_mant_res = mant_add;
        end else begin
            alu_sign_res = mant_sub[31] ? sign_b : sign_a;
            alu_mant_res = mant_sub[31] ? -mant_sub : mant_sub;
        end

        exact_zero_add = (alu_mant_res == 32'd0);
    end

    // Step 5. Normalize (PURE COMB) + LZD with priority case
    always_comb begin
        if (alu_mant_res == 32'd0) begin
            leading_zeros = 5'd31;
            alu_mant_norm = 32'd0;
            alu_exp_norm  = 9'd0;
        end else begin
            // LZD: priority case (same mapping as your original if-else chain)
            priority case (1'b1)
                alu_mant_res[30]: leading_zeros = 5'd0;
                alu_mant_res[29]: leading_zeros = 5'd1;
                alu_mant_res[28]: leading_zeros = 5'd2;
                alu_mant_res[27]: leading_zeros = 5'd3;
                alu_mant_res[26]: leading_zeros = 5'd4;
                alu_mant_res[25]: leading_zeros = 5'd5;
                alu_mant_res[24]: leading_zeros = 5'd6;
                alu_mant_res[23]: leading_zeros = 5'd7;
                alu_mant_res[22]: leading_zeros = 5'd8;
                alu_mant_res[21]: leading_zeros = 5'd9;
                alu_mant_res[20]: leading_zeros = 5'd10;
                alu_mant_res[19]: leading_zeros = 5'd11;
                alu_mant_res[18]: leading_zeros = 5'd12;
                alu_mant_res[17]: leading_zeros = 5'd13;
                alu_mant_res[16]: leading_zeros = 5'd14;
                alu_mant_res[15]: leading_zeros = 5'd15;
                alu_mant_res[14]: leading_zeros = 5'd16;
                alu_mant_res[13]: leading_zeros = 5'd17;
                alu_mant_res[12]: leading_zeros = 5'd18;
                alu_mant_res[11]: leading_zeros = 5'd19;
                alu_mant_res[10]: leading_zeros = 5'd20;
                alu_mant_res[9] : leading_zeros = 5'd21;
                alu_mant_res[8] : leading_zeros = 5'd22;
                alu_mant_res[7] : leading_zeros = 5'd23;
                alu_mant_res[6] : leading_zeros = 5'd24;
                alu_mant_res[5] : leading_zeros = 5'd25;
                alu_mant_res[4] : leading_zeros = 5'd26;
                alu_mant_res[3] : leading_zeros = 5'd27;
                alu_mant_res[2] : leading_zeros = 5'd28;
                alu_mant_res[1] : leading_zeros = 5'd29;
                alu_mant_res[0] : leading_zeros = 5'd30;
                default         : leading_zeros = 5'd31;
            endcase

            if (alu_mant_res[31]) begin
                alu_mant_norm = {1'd0, alu_mant_res[31:1]};
                alu_exp_norm  = {1'b0, exp_res} + 9'd1;
            end else begin
                alu_mant_norm = alu_mant_res << leading_zeros;
                alu_exp_norm  = {1'b0, exp_res} - {4'b0, leading_zeros};
            end
        end
    end

    // Step 6. TRUNCATE + Pack (NO rounding)
    always_comb begin
        alu_mant_out = alu_mant_norm[29:7];
        alu_exp_out  = alu_exp_norm;

        alu_sign_out = exact_zero_add ? 1'b0 : alu_sign_res;

        y = {alu_sign_out, alu_exp_out[7:0], alu_mant_out};

        overflow = alu_exp_norm[8] | alu_exp_out[8];
    end

endmodule
`endif // FP32_ADDSUB_SV