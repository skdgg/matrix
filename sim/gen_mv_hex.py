# -*- coding: utf-8 -*-
import numpy as np
import random
from pathlib import Path

np.seterr(over="raise", invalid="raise", divide="raise")

# -----------------------------
# FP32 helpers
# -----------------------------
def f32_to_u32(x: np.float32) -> int:
    return int(np.frombuffer(np.float32(x).tobytes(), dtype=np.uint32)[0])

def u32_to_f32(u: int) -> np.float32:
    return np.frombuffer(np.uint32(u), dtype=np.float32)[0]

# -----------------------------
# HW-like helpers (MATCH your current RTL)
# - NO NaN/Inf handling
# - denorm: exp_raw==0 => exp_eff=1, hidden=0
# - NO rounding: TRUNCATE mant_norm[29:7]
# - ADD align: plain >> (NO sticky)
# -----------------------------
def _unpack(u: int):
    s = (u >> 31) & 1
    e = (u >> 23) & 0xFF
    f = u & 0x7FFFFF
    return s, e, f

def _pack(s: int, e: int, f: int) -> int:
    return ((s & 1) << 31) | ((e & 0xFF) << 23) | (f & 0x7FFFFF)

def fp32_mul_trunc_hw(a_u: int, b_u: int) -> int:
    # === matches your fp32_mul (truncate) ===
    sa, ea_raw, fa = _unpack(a_u)
    sb, eb_raw, fb = _unpack(b_u)

    is_zero_a = (ea_raw == 0) and (fa == 0)
    is_zero_b = (eb_raw == 0) and (fb == 0)
    any_zero = is_zero_a or is_zero_b

    # exp_eff: denorm treated as exp=1
    ea = 1 if ea_raw == 0 else ea_raw
    eb = 1 if eb_raw == 0 else eb_raw

    # mantissa: normal => 1.frac, denorm => 0.frac (24-bit)
    ma = (fa if ea_raw == 0 else ((1 << 23) | fa)) & 0xFFFFFF
    mb = (fb if eb_raw == 0 else ((1 << 23) | fb)) & 0xFFFFFF

    sign_res = sa ^ sb

    # In your RTL: if any_zero OR mul_mant_res==0 => mant_norm=0 exp_norm=0
    if any_zero:
        return _pack(sign_res, 0, 0)

    exp_res = (ea + eb - 127)  # 9-bit in RTL, keep int here
    prod = ma * mb             # 48-bit

    if prod == 0:
        return _pack(sign_res, 0, 0)

    # Normalize exactly like RTL:
    # if prod[47] => mant_norm = {0, prod[47:17]}, exp_norm=exp_res+1
    # else        => mant_norm = {0, prod[46:16]}, exp_norm=exp_res
    if (prod >> 47) & 1:
        mant_norm = (prod >> 17) & 0x7FFFFFFF  # 31 bits, MSB already in position
        exp_norm  = exp_res + 1
    else:
        mant_norm = (prod >> 16) & 0x7FFFFFFF
        exp_norm  = exp_res

    # TRUNCATE (NO rounding): mant_out = mant_norm[29:7]
    mant_out = (mant_norm >> 7) & 0x7FFFFF
    exp_out  = exp_norm & 0xFF

    return _pack(sign_res, exp_out, mant_out)

def fp32_addsub_trunc_hw(sub: int, a_u: int, b_u: int) -> int:
    # === matches your fp32_addsub (truncate) ===
    sa, ea_raw, fa = _unpack(a_u)
    sb, eb_raw, fb = _unpack(b_u)
    sb_eff = sb ^ (1 if sub else 0)

    # exp_eff: denorm treated as exp=1
    ea = 1 if ea_raw == 0 else ea_raw
    eb = 1 if eb_raw == 0 else eb_raw

    # mantissa build like your RTL (32-bit with 7 zeros LSB):
    # normal -> {2'b01, frac, 7'd0}, denorm/zero -> {2'b00, frac, 7'd0}
    mant_a = (((0 if ea_raw == 0 else 1) << 23) | fa) << 7
    mant_b = (((0 if eb_raw == 0 else 1) << 23) | fb) << 7
    mant_a &= 0xFFFFFFFF
    mant_b &= 0xFFFFFFFF

    # Align exponent (NO sticky in your RTL)
    if ea > eb:
        exp_res = ea
        diff = ea - eb
        mant_a_al = mant_a
        mant_b_al = (mant_b >> diff) & 0xFFFFFFFF
    else:
        exp_res = eb
        diff = eb - ea
        mant_a_al = (mant_a >> diff) & 0xFFFFFFFF
        mant_b_al = mant_b

    # Add/Sub mantissa (match RTL sign selection)
    if sa == sb_eff:
        mant = (mant_a_al + mant_b_al) & 0xFFFFFFFF
        sign = sa
    else:
        mant_sub = (mant_a_al - mant_b_al) & 0xFFFFFFFF
        if (mant_sub >> 31) & 1:
            mant = (-mant_sub) & 0xFFFFFFFF
            sign = sb_eff
        else:
            mant = mant_sub
            sign = sa

    # exact zero -> +0 (like your RTL)
    if mant == 0:
        return _pack(0, 0, 0)

    # Normalize (match RTL)
    if (mant >> 31) & 1:
        # carry case: alu_mant_norm = {0, mant[31:1]}, exp+1
        mant_norm = (mant >> 1) & 0x7FFFFFFF
        exp_norm  = exp_res + 1
    else:
        # leading zeros on mant[30:0], shift left until bit30 becomes 1
        lz = 31
        for k in range(30, -1, -1):
            if (mant >> k) & 1:
                lz = 30 - k
                break
        # (mant != 0 already ensured)
        mant_norm = (mant << lz) & 0xFFFFFFFF
        exp_norm  = exp_res - lz

    # TRUNCATE (NO rounding): mant_out = mant_norm[29:7]
    mant_out = (mant_norm >> 7) & 0x7FFFFF
    exp_out  = exp_norm & 0xFF

    return _pack(sign, exp_out, mant_out)

# -----------------------------
# Golden model (HW TRUNC):
# - every mul/add is done by HW-like bit model
# - NO rounding (truncate)
# -----------------------------
def mv4x4_fp32_trunc_hw(M, v):
    Mf = np.array(M, dtype=np.float32)
    vf = np.array(v, dtype=np.float32)

    out_u32 = []
    for r in range(4):
        # 4 products
        p = []
        for c in range(4):
            a_u = f32_to_u32(np.float32(Mf[r, c]))
            b_u = f32_to_u32(np.float32(vf[c]))
            p.append(fp32_mul_trunc_hw(a_u, b_u))

        # RTL tree: (p0+p1) + (p2+p3)
        a0 = fp32_addsub_trunc_hw(0, p[0], p[1])
        a1 = fp32_addsub_trunc_hw(0, p[2], p[3])
        s  = fp32_addsub_trunc_hw(0, a0, a1)

        out_u32.append(s)

    return out_u32

# -----------------------------
# Random FP32 generator (finite)
# -----------------------------
def rand_f32(low=-2.0, high=2.0) -> np.float32:
    return np.float32(random.uniform(low, high))

def make_tests(n=100, seed=0x1234, val_range=(-2.0, 2.0)):
    random.seed(seed)
    tests = []
    lo, hi = val_range

    edge_pool = [
        np.float32(0.0), np.float32(-0.0), np.float32(1.0), np.float32(-1.0),
        np.float32(2.0), np.float32(0.5), np.float32(3.1415926),
        np.float32(1e-3), np.float32(1e3),
    ]

    for vid in range(n):
        def pick():
            return random.choice(edge_pool) if random.random() < 0.1 else rand_f32(lo, hi)

        M = [[pick() for _ in range(4)] for _ in range(4)]
        v = [pick() for _ in range(4)]

        out_u32 = mv4x4_fp32_trunc_hw(M, v)  # <<< HW-trunc golden (updated)

        tests.append((vid, M, v, out_u32))
    return tests

# -----------------------------
# Write .hex (one 32-bit word per line)
# -----------------------------
def write_hex_words(path: Path, words):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        for w in words:
            f.write(f"{w & 0xFFFFFFFF:08x}\n")  # keep your original lowercase hex

def main():
    N = 50
    SEED = 20251219
    OUTDIR = Path("out_hex")
    OUTDIR.mkdir(exist_ok=True)

    tests = make_tests(n=N, seed=SEED, val_range=(-2.0, 2.0))

    in_words = []
    out_words = []

    for (vid, M, v, out_u32) in tests:
        # input layout (21 words): id, m00..m33 (row-major), vx,vy,vz,vw
        in_words.append(vid)
        for r in range(4):
            for c in range(4):
                in_words.append(f32_to_u32(np.float32(M[r][c])))
        for i in range(4):
            in_words.append(f32_to_u32(np.float32(v[i])))

        # output layout (5 words): id, ox,oy,oz,ow
        out_words.append(vid)
        for r in range(4):
            out_words.append(out_u32[r])

    write_hex_words(OUTDIR / "mv_in.hex", in_words)
    write_hex_words(OUTDIR / "mv_out.hex", out_words)

    print("Generated (HW-trunc golden, MATCH current RTL):")
    print(f"  {OUTDIR/'mv_in.hex'}  ({len(in_words)} words = {N} cases * 21)")
    print(f"  {OUTDIR/'mv_out.hex'} ({len(out_words)} words = {N} cases * 5)")
    print("Format:")
    print("  mv_in.hex : id, m00..m33, vx,vy,vz,vw (21 lines per case)")
    print("  mv_out.hex: id, ox,oy,oz,ow           (5 lines per case)")

if __name__ == "__main__":
    main()
