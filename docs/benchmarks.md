# Benchmark methodology


The OCaml benchmark reports per-image measurements directly:

```sh
dune exec bin/main.exe -- benchmark data/div2k-ppm/0801.ppm --qualities 10,50,90 --csv results.csv
```

For directories and machine/build metadata, use the Python runner:

```sh
python scripts/run_benchmarks.py data/div2k-ppm --qualities 10,30,50,75,90,100 --build-label "OCaml VERSION native, compiler default optimization"
python scripts/plot_benchmarks.py results/benchmark.csv
```

Replace `VERSION` with the actual compiler version. The runner defaults to
Dune's `_build/default/bin/main.exe`; supply `--exe` for another build and
`--runtime path/to/ocamlrun` if a relocated bytecode launcher needs it.
All output directories must be writable; the runner creates the parent of its
CSV and refuses to overwrite existing results.

| Metric | Definition |
| --- | --- |
| Payload bpp | Valid Y, Cb and Cr entropy bits / original pixel count |
| File bpp | Complete `.ojpg` file bytes × 8 / original pixel count |
| Compression ratio | Original RGB raster bytes / complete `.ojpg` bytes |
| Space saving | 100 × (1 − compressed file bytes / original RGB raster bytes) |
| PSNR | 10 log10(255² / MSE), over all original RGB samples |
| CPU/wall seconds | Time spent inside encode/decode, reported separately |
| Seconds/MB | Codec time / original RGB raster size in decimal MB |
| MB/s | Original RGB raster size in decimal MB / codec wall time |

The reference size is **3 × width × height bytes**, not the PNG file size or
the PPM header. MB means 1,000,000 bytes, not MiB. File size includes the 28-byte
container header and each stream's last padded byte. PSNR compares the original
dimensions, including border pixels; identical images produce infinity.

By default each image/quality has **one measured pass and no warmup**. That pass
supplies both image metrics and timings. For a more stable timing study, add
`--warmup 1 --repeat 3`: one unmeasured warmup followed by three measured passes.
The CSV records repeats and warmup runs. Times are the single measured value
when repeats=1, otherwise medians. Input parsing, PNG conversion, disk I/O, PSNR and
explicit garbage collection before each measured run are excluded. Allocations
and garbage collection occurring **inside** encode/decode are included. Encode
includes entropy packing; decode includes entropy reading. The runner records
input hashes, platform information, build label and executable hash.

Checked-in CSVs and metadata in [`benchmarks/`](../benchmarks/) are actual local
measurements, not performance targets. The DIV2K result is a **single-image
execution check**, with one measured run per quality after warmup. It does not
represent the full 100-image validation set, and Windows bytecode timing should
not be compared to native-code JPEG libraries. A larger experiment should use
native compilation, multiple measured runs and all images.

The original naive algorithms are also useful baselines:

```sh
dune exec bin/main.exe -- transforms --repeat 50 --max-power 6 --csv transforms.csv
```

This compares FFT versus direct DFT, and FFT-based DCT versus the direct cosine
sum, reporting both time and maximum absolute error. Approximate floating-point
agreement is checked; exact floating-point equality is not assumed. Each
algorithm is batched for at least 0.2 elapsed seconds to reduce clock-resolution
effects. Transform speedup uses wall time per batch; CPU times are also retained.

