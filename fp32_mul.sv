// FP32 Multiply (NO rounding; TRUNCATE after normalization)
// - denorm: treated as exp=1, hidden=0
// - result: normalized then TRUNCATE fraction (no GRS, no RNE)
module fp32_mul (
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        overflow,
    output logic [31:0] y
);

    logic        sign_1, sign_2;
    logic [ 7:0] exp1_raw, exp2_raw;
    logic [22:0] frac1_raw, frac2_raw;
    logic        is_zero_1, is_zero_2;
    logic        is_denorm_1, is_denorm_2;

    logic [ 8:0] exp_1 , exp_2;
    logic [23:0] mant_1, mant_2;

    logic        mul_sign_res;
    logic [ 8:0] mul_exp_res;
    logic [47:0] mul_mant_res;

    logic [ 8:0] mul_exp_norm;
    logic [31:0] mul_mant_norm;

    logic        mul_any_zero;

    logic        mul_sign_out;
    logic [ 8:0] mul_exp_out;
    logic [22:0] mul_mant_out;

    // Step 1. Breakdown + zero/denorm
    always_comb begin
        sign_1    = a[31];
        sign_2    = b[31];

        exp1_raw  = a[30:23];
        exp2_raw  = b[30:23];
        frac1_raw = a[22:0];
        frac2_raw = b[22:0];

        is_zero_1   = (exp1_raw == 8'd0) && (frac1_raw == 23'd0);
        is_zero_2   = (exp2_raw == 8'd0) && (frac2_raw == 23'd0);
        is_denorm_1 = (exp1_raw == 8'd0) && (frac1_raw != 23'd0);
        is_denorm_2 = (exp2_raw == 8'd0) && (frac2_raw != 23'd0);

        exp_1 = {1'b0, (exp1_raw == 8'd0) ? 8'd1 : exp1_raw};
        exp_2 = {1'b0, (exp2_raw == 8'd0) ? 8'd1 : exp2_raw};

        mant_1 = (exp1_raw == 8'd0) ? {1'b0, frac1_raw} : {1'b1, frac1_raw};
        mant_2 = (exp2_raw == 8'd0) ? {1'b0, frac2_raw} : {1'b1, frac2_raw};

        mul_any_zero = is_zero_1 || is_zero_2;
    end

    // Step 2. Multiply
    always_comb begin
        mul_sign_res = sign_1 ^ sign_2;
        mul_exp_res  = exp_1 + exp_2 - 9'd127;
        mul_mant_res = mant_1 * mant_2;
    end

    // Step 3. Normalize
    always_comb begin
        if (mul_mant_res == 48'd0 || mul_any_zero) begin
            mul_mant_norm = 32'd0;
            mul_exp_norm  = 9'd0;
        end else if (mul_mant_res[47]) begin
            mul_mant_norm = {1'd0, mul_mant_res[47:17]};
            mul_exp_norm  = mul_exp_res + 9'd1;
        end else begin
            mul_mant_norm = {1'd0, mul_mant_res[46:16]};
            mul_exp_norm  = mul_exp_res;
        end
    end

    // Step 4. TRUNCATE + Pack (NO rounding)
    always_comb begin
        mul_mant_out = mul_mant_norm[29:7];
        mul_exp_out  = mul_exp_norm;
        mul_sign_out = mul_sign_res;

        y = {mul_sign_out, mul_exp_out[7:0], mul_mant_out};

        overflow = mul_exp_res[8] | mul_exp_norm[8] | mul_exp_out[8];
    end

endmodule
