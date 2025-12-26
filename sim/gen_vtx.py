#!/usr/bin/env python3
"""
gen_vtx_io.py (SPEC-correct, uses software IEEE FP32 sqrt as reference)
- supports two modes:
    --mode random  : generate N random vertices (default)
    --mode fixed3  : generate fixed 3 vertices with simple global params (easy to sanity-check)

Input (header + N vertex records):
  N                    : uint32
  MV matrix (4x4)      : 16 * fp32 (row-major)
  Lp (Lpx,Lpy,Lpz)     : 3 * fp32
  Ld (Ldx,Ldy,Ldz)     : 3 * fp32   (raw input; HW will normalize)
  Lp_intensity         : fp32 in (0,1)
  Ld_intensity         : fp32 in (0,1)
  La_intensity         : fp32 in (0,1)
  Pscale_x             : fp32
  Pscale_y             : fp32
  Records (repeat N):
    id                 : uint32
    Vx,Vy,Vz,Vw        : 4 * fp32   (Vw fixed=1.0)
    Nx,Ny,Nz           : 3 * fp32   (normalized input normal)

Golden output:
  N
  Records (repeat N):
    Px, Py, 1/Pz, Brightness : 4 * fp32
"""

import argparse
import struct
from pathlib import Path
import numpy as np


def f32(x) -> np.float32:
    return np.float32(x)


def f32_to_u32(x: np.float32) -> int:
    return struct.unpack("<I", struct.pack("<f", float(np.float32(x))))[0]


def hex8(u: int) -> str:
    return f"{u & 0xFFFFFFFF:08x}"


def dot3(a: np.ndarray, b: np.ndarray) -> np.float32:
    return f32(a[0] * b[0] + a[1] * b[1] + a[2] * b[2])


def inv_sqrt_soft(x: np.float32) -> np.float32:
    # "Correct software sqrt" reference
    if float(x) <= 0.0:
        return f32(0.0)
    return f32(1.0) / f32(np.sqrt(x))


def vec_norm3(v: np.ndarray) -> np.ndarray:
    vv = dot3(v, v)
    inv = inv_sqrt_soft(vv)
    return (v * inv).astype(np.float32)


def clamp0(x: np.float32) -> np.float32:
    return x if float(x) > 0.0 else f32(0.0)


def mat4_mul_vec4(M: np.ndarray, v4: np.ndarray) -> np.ndarray:
    return (M @ v4).astype(np.float32)


def build_fixed3():
    """
    Deterministic, easy-to-check test:
      M = I
      Pscale_x = Pscale_y = 1
      Lp = (0,0,10), Ld = (0,0,1)
      intensities: Lp=0.5, Ld=0.5, La=0.0
      vertices:
        id0: V=(1,0,1,1), N=(0,0,1)
        id1: V=(0,1,2,1), N=(0,0,1)
        id2: V=(1,1,4,1), N=(0,0,1)
    """
    M = np.eye(4, dtype=np.float32)
    Pscale_x = f32(1.0)
    Pscale_y = f32(1.0)

    Lp = np.array([f32(0.0), f32(0.0), f32(10.0)], dtype=np.float32)
    Ld = np.array([f32(0.0), f32(0.0), f32(1.0)], dtype=np.float32)

    Lp_intensity = f32(0.5)
    Ld_intensity = f32(0.5)
    La_intensity = f32(0.0)

    ids = np.array([0, 1, 2], dtype=np.uint32)
    Vx = np.array([f32(1.0), f32(0.0), f32(1.0)], dtype=np.float32)
    Vy = np.array([f32(0.0), f32(1.0), f32(1.0)], dtype=np.float32)
    Vz = np.array([f32(1.0), f32(2.0), f32(4.0)], dtype=np.float32)
    Vw = np.ones(3, dtype=np.float32)

    Nvec = np.tile(np.array([f32(0.0), f32(0.0), f32(1.0)], dtype=np.float32), (3, 1))

    return (M, Pscale_x, Pscale_y, Lp, Ld, Lp_intensity, Ld_intensity, La_intensity,
            ids, Vx, Vy, Vz, Vw, Nvec)


def build_random(n: int, seed: int):
    rng = np.random.default_rng(seed)

    # MV matrix: moderate values to avoid overflow
    M = np.eye(4, dtype=np.float32)
    M[0, 0] = f32(rng.uniform(0.5, 2.0))
    M[1, 1] = f32(rng.uniform(0.5, 2.0))
    M[2, 2] = f32(rng.uniform(0.5, 2.0))
    M[3, 3] = f32(1.0)

    # Pscale_x/y
    Pscale_x = f32(rng.uniform(100.0, 800.0))
    Pscale_y = f32(rng.uniform(100.0, 800.0))

    # Lp, Ld
    Lp = np.array(
        [f32(rng.uniform(-5.0, 5.0)), f32(rng.uniform(-5.0, 5.0)), f32(rng.uniform(1.0, 8.0))],
        dtype=np.float32,
    )

    Ld = np.array(
        [f32(rng.uniform(-1.0, 1.0)), f32(rng.uniform(-1.0, 1.0)), f32(rng.uniform(-1.0, 1.0))],
        dtype=np.float32,
    )
    if float(dot3(Ld, Ld)) < 1e-12:
        Ld = np.array([f32(0.0), f32(1.0), f32(0.0)], dtype=np.float32)

    # Intensities in (0,1)
    Lp_intensity = f32(rng.uniform(0.05, 0.95))
    Ld_intensity = f32(rng.uniform(0.05, 0.95))
    La_intensity = f32(rng.uniform(0.05, 0.95))

    # Vertex inputs
    ids = np.arange(n, dtype=np.uint32)
    Vx = rng.uniform(-2.0, 2.0, size=n).astype(np.float32)
    Vy = rng.uniform(-2.0, 2.0, size=n).astype(np.float32)
    Vz = rng.uniform(0.5, 10.0, size=n).astype(np.float32)
    Vw = np.ones(n, dtype=np.float32)

    # N random then normalize
    Nraw = rng.normal(size=(n, 3)).astype(np.float32)
    Nvec = np.zeros_like(Nraw, dtype=np.float32)
    for i in range(n):
        if float(dot3(Nraw[i], Nraw[i])) < 1e-12:
            Nraw[i] = np.array([f32(1.0), f32(0.0), f32(0.0)], dtype=np.float32)
        Nvec[i] = vec_norm3(Nraw[i])

    return (M, Pscale_x, Pscale_y, Lp, Ld, Lp_intensity, Ld_intensity, La_intensity,
            ids, Vx, Vy, Vz, Vw, Nvec)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["random", "fixed3"], default="random",
                    help="random: generate N random vertices; fixed3: deterministic 3-vertex test")
    ap.add_argument("--n", type=int, default=256, help="number of vertices (random mode only)")
    ap.add_argument("--seed", type=int, default=0, help="random seed (random mode only)")
    ap.add_argument("--outdir", type=str, default=".", help="output directory")
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    if args.mode == "fixed3":
        (M, Pscale_x, Pscale_y, Lp, Ld, Lp_intensity, Ld_intensity, La_intensity,
         ids, Vx, Vy, Vz, Vw, Nvec) = build_fixed3()
        Nverts = 3
    else:
        (M, Pscale_x, Pscale_y, Lp, Ld, Lp_intensity, Ld_intensity, La_intensity,
         ids, Vx, Vy, Vz, Vw, Nvec) = build_random(args.n, args.seed)
        Nverts = int(args.n)

    # Precompute normalized Ld for reference
    Ld_hat = vec_norm3(Ld)

    # -------------------------
    # Golden compute (per spec)
    # -------------------------
    golden = []  # (Px, Py, invPz, Brightness)
    for i in range(Nverts):
        V = np.array([Vx[i], Vy[i], Vz[i], Vw[i]], dtype=np.float32)
        Vp = mat4_mul_vec4(M, V)  # V'

        z = Vp[2]
        invPz = inv_sqrt_soft(f32(z * z))  # 1/sqrt(z^2)

        Px = f32(Vp[0] * Pscale_x * invPz)
        Py = f32(Vp[1] * Pscale_y * invPz)

        Lp_prime = (Lp - Vp[:3]).astype(np.float32)
        if float(dot3(Lp_prime, Lp_prime)) < 1e-12:
            Lp_prime = np.array([f32(0.0), f32(0.0), f32(1.0)], dtype=np.float32)
        Lp_hat = vec_norm3(Lp_prime)

        N_hat = vec_norm3(Nvec[i])

        Idiff_p = clamp0(dot3(N_hat, Lp_hat))
        Idiff_d = clamp0(dot3(N_hat, Ld_hat))

        Brightness = f32(Idiff_p * Lp_intensity + Idiff_d * Ld_intensity + La_intensity)

        golden.append((Px, Py, invPz, Brightness))

    # -------------------------
    # Write input.hex 
    # -------------------------
    inp = []
    inp.append(hex8(Nverts))

    for r in range(4):
        for c in range(4):
            inp.append(hex8(f32_to_u32(M[r, c])))

    for k in range(3):
        inp.append(hex8(f32_to_u32(Lp[k])))
    for k in range(3):
        inp.append(hex8(f32_to_u32(Ld[k])))

    inp.append(hex8(f32_to_u32(Lp_intensity)))
    inp.append(hex8(f32_to_u32(Ld_intensity)))
    inp.append(hex8(f32_to_u32(La_intensity)))

    inp.append(hex8(f32_to_u32(Pscale_x)))
    inp.append(hex8(f32_to_u32(Pscale_y)))

    for i in range(Nverts):
        inp.append(hex8(int(ids[i])))
        inp.append(hex8(f32_to_u32(Vx[i])))
        inp.append(hex8(f32_to_u32(Vy[i])))
        inp.append(hex8(f32_to_u32(Vz[i])))
        inp.append(hex8(f32_to_u32(Vw[i])))
        inp.append(hex8(f32_to_u32(Nvec[i, 0])))
        inp.append(hex8(f32_to_u32(Nvec[i, 1])))
        inp.append(hex8(f32_to_u32(Nvec[i, 2])))

    (outdir / "input.hex").write_text("\n".join(inp) + "\n")

    # -------------------------
    # Write golden_output.hex 
    # -------------------------
    out = []
    out.append(hex8(Nverts))
    for (Px, Py, invPz, Br) in golden:
        out.append(hex8(f32_to_u32(Px)))
        out.append(hex8(f32_to_u32(Py)))
        out.append(hex8(f32_to_u32(invPz)))
        out.append(hex8(f32_to_u32(Br)))

    (outdir / "golden_output.hex").write_text("\n".join(out) + "\n")

    print("[OK] wrote", outdir / "input.hex")
    print("[OK] wrote", outdir / "golden_output.hex")
    print(f"mode={args.mode} N={Nverts}" + (f" seed={args.seed}" if args.mode == "random" else ""))
    print("intensities:",
          f"Lp_intensity={float(Lp_intensity):.6f}",
          f"Ld_intensity={float(Ld_intensity):.6f}",
          f"La_intensity={float(La_intensity):.6f}")


if __name__ == "__main__":
    main()
