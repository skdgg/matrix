// FP32 Add/Sub (NO rounding; TRUNCATE after normalization)
// - sub=0: y = a + b
// - sub=1: y = a - b
// - denorm: treated as exp=1, hidden=0
// - pipeline: 1 stage (same as your original)
// - exact zero => +0
module fp32_addsub (
    input  logic        clk,
    input  logic        rst,
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

    // pipeline register
    logic        alu_sign_res_2nd_stage;
    logic [31:0] alu_mant_res_2nd_stage;
    logic [ 7:0] alu_exp_res_2nd_stage;

    logic        exact_zero_add;
    logic        exact_zero_add_2nd_stage;

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

    // Step 4. Pipeline registers
    always_ff @(posedge clk) begin
        if (rst) begin
            alu_sign_res_2nd_stage   <= 1'b0;
            alu_mant_res_2nd_stage   <= 32'd0;
            alu_exp_res_2nd_stage    <= 8'd0;
            exact_zero_add_2nd_stage <= 1'b0;
        end else begin
            alu_sign_res_2nd_stage   <= alu_sign_res;
            alu_mant_res_2nd_stage   <= alu_mant_res;
            alu_exp_res_2nd_stage    <= exp_res;
            exact_zero_add_2nd_stage <= exact_zero_add;
        end
    end

    // Step 5. Normalize
    always_comb begin
        if (alu_mant_res_2nd_stage == 32'd0) begin
            alu_mant_norm = 32'd0;
            alu_exp_norm  = 9'd0;
        end else begin
            priority if (alu_mant_res_2nd_stage[30]) leading_zeros = 5'd0;
            else if (alu_mant_res_2nd_stage[29]) leading_zeros = 5'd1;
            else if (alu_mant_res_2nd_stage[28]) leading_zeros = 5'd2;
            else if (alu_mant_res_2nd_stage[27]) leading_zeros = 5'd3;
            else if (alu_mant_res_2nd_stage[26]) leading_zeros = 5'd4;
            else if (alu_mant_res_2nd_stage[25]) leading_zeros = 5'd5;
            else if (alu_mant_res_2nd_stage[24]) leading_zeros = 5'd6;
            else if (alu_mant_res_2nd_stage[23]) leading_zeros = 5'd7;
            else if (alu_mant_res_2nd_stage[22]) leading_zeros = 5'd8;
            else if (alu_mant_res_2nd_stage[21]) leading_zeros = 5'd9;
            else if (alu_mant_res_2nd_stage[20]) leading_zeros = 5'd10;
            else if (alu_mant_res_2nd_stage[19]) leading_zeros = 5'd11;
            else if (alu_mant_res_2nd_stage[18]) leading_zeros = 5'd12;
            else if (alu_mant_res_2nd_stage[17]) leading_zeros = 5'd13;
            else if (alu_mant_res_2nd_stage[16]) leading_zeros = 5'd14;
            else if (alu_mant_res_2nd_stage[15]) leading_zeros = 5'd15;
            else if (alu_mant_res_2nd_stage[14]) leading_zeros = 5'd16;
            else if (alu_mant_res_2nd_stage[13]) leading_zeros = 5'd17;
            else if (alu_mant_res_2nd_stage[12]) leading_zeros = 5'd18;
            else if (alu_mant_res_2nd_stage[11]) leading_zeros = 5'd19;
            else if (alu_mant_res_2nd_stage[10]) leading_zeros = 5'd20;
            else if (alu_mant_res_2nd_stage[9])  leading_zeros = 5'd21;
            else if (alu_mant_res_2nd_stage[8])  leading_zeros = 5'd22;
            else if (alu_mant_res_2nd_stage[7])  leading_zeros = 5'd23;
            else if (alu_mant_res_2nd_stage[6])  leading_zeros = 5'd24;
            else if (alu_mant_res_2nd_stage[5])  leading_zeros = 5'd25;
            else if (alu_mant_res_2nd_stage[4])  leading_zeros = 5'd26;
            else if (alu_mant_res_2nd_stage[3])  leading_zeros = 5'd27;
            else if (alu_mant_res_2nd_stage[2])  leading_zeros = 5'd28;
            else if (alu_mant_res_2nd_stage[1])  leading_zeros = 5'd29;
            else if (alu_mant_res_2nd_stage[0])  leading_zeros = 5'd30;
            else leading_zeros = 5'd31;

            if (alu_mant_res_2nd_stage[31]) begin
                alu_mant_norm = {1'd0, alu_mant_res_2nd_stage[31:1]};
                alu_exp_norm  = {1'b0, alu_exp_res_2nd_stage} + 9'd1;
            end else begin
                alu_mant_norm = alu_mant_res_2nd_stage << leading_zeros;
                alu_exp_norm  = {1'b0, alu_exp_res_2nd_stage} - {4'b0, leading_zeros};
            end
        end
    end

    // Step 6. TRUNCATE + Pack (NO rounding)
    always_comb begin
        // 直接截斷：拿掉 guard/round/sticky 與 round_up
        alu_mant_out = alu_mant_norm[29:7];
        alu_exp_out  = alu_exp_norm;

        if (exact_zero_add_2nd_stage)
            alu_sign_out = 1'b0;  // exact 0 → +0
        else
            alu_sign_out = alu_sign_res_2nd_stage;

        y = {alu_sign_out, alu_exp_out[7:0], alu_mant_out};

        overflow = alu_exp_norm[8] | alu_exp_out[8];
    end

endmodule
