# Benchmark methodology

## Full DIV2K validation run

[`div2k-100.csv`](../benchmarks/div2k-100.csv) contains the complete run on
validation images 0801–0900, at their original dimensions (1.66–4.16 million
pixels). Each of the 100 images was encoded and decoded at qualities
10, 30, 50, 75, 90 and 100, giving 600 distinct image/quality pairs.
The [matching metadata](../benchmarks/div2k-100.json) records input hashes,
the executable hash and the environment: Windows 11 x64, OCaml 4.14.0
bytecode with compiler default optimization. The pipeline is single-threaded.
There was one measured pass per pair and no warmup.

### Aggregation and interpretation

The README table and both panels use **per-image medians**, with every image
receiving equal weight. The size–quality panel plots the median file bpp and
median RGB PSNR at each quality; the point need not describe a particular
image. Horizontal and vertical bars independently show the 25th–75th percentiles
of those metrics. Runtime bands show the same percentiles of wall seconds per
MB. Percentiles use linear interpolation at sorted position `(n − 1) × p`.
These ranges describe content variation across images, not confidence intervals
or repeatability of timing on one image. PSNR is summarized directly in dB;
it is not calculated from a pooled pixel MSE.

The **OJPG / PNG size** column compares each complete OJPG file to its original
DIV2K PNG: `100 × OJPG bytes / PNG bytes`, summarized with a per-image median.
It uses the original PNG files, without re-encoding or changing dimensions.
At quality 75 the median is 9.9%, and at quality 100 it is 49.1%.
This is a storage comparison between lossy OJPG and lossless PNG, not a
comparison at equal reconstruction quality. It is distinct from the
RGB/OJPG compression ratio and from a ratio of total dataset bytes.
[`div2k-100-png.csv`](../benchmarks/div2k-100-png.csv) records original PNG
byte sizes, dimensions and hashes, linked to the benchmark input PPM hashes.
The PNG hashes were checked against the original conversion manifest.

The [derived summary](../benchmarks/div2k-100-summary.json) also retains means,
minima, maxima and ratios calculated from dataset totals. Those dataset ratios
are separate from the medians: for example, quality 75 has a median compression
ratio of 19.57×, while total RGB bytes divided by total compressed bytes gives
18.99×. Taking an average of image ratios would give another value.

At quality 75, the median file uses 1.23 bpp versus 24 bpp for RGB input.
Quality 90 raises median PSNR to 37.30 dB at 2.10 bpp. Quality 100 reaches
42.77 dB at 6.09 bpp and remains lossy. The median file bpp at quality 100 is
2.91 times the quality-90 median, for 5.47 dB more median PSNR. These are
comparisons of distribution summaries, not medians of paired image gains.

Wall time varies much less than file size in this run: medians span
1.79–1.94 s/MB for encoding and 3.67–3.79 s/MB for decoding.
The measurements describe this bytecode build and machine. No native-code
timing or comparison against a production JPEG encoder was performed.

### Reproduce the presentation

The raw CSV and JSON are preserved unchanged. The summary tool checks for
duplicate or missing image/quality pairs, agreement with run metadata, finite
metrics, consistent dimensions and agreement between recorded byte sizes,
ratios, bits/pixel and normalized times. It then generates the summary JSON,
PNG and vector SVG, without running the codec again:

```sh
python -m pip install -r scripts/requirements.txt
python scripts/summarize_benchmarks.py benchmarks/div2k-100.csv
```

The summary automatically reads `benchmarks/div2k-100-png.csv` when present,
so the PNG comparison can be reproduced without distributing the photographs.
To regenerate that size manifest from a local dataset and its conversion manifest:

```sh
python scripts/measure_png_sizes.py benchmarks/div2k-100.csv --png-directory path/to/DIV2K_valid_HR --conversion-manifest data/div2k-ppm/conversion-manifest.json
```

The measurement script verifies PNG signatures, dimensions and source/converted
hashes before writing the manifest. Existing output files are not overwritten.

## Run new measurements

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

Earlier files such as `div2k-0801.csv` are single-image execution checks with
their own recorded warmup settings. They are retained separately from the
complete `div2k-100.csv` run and are not combined in its presentation.

## Transform comparisons

The original naive algorithms are also useful baselines:

```sh
dune exec bin/main.exe -- transforms --repeat 50 --max-power 6 --csv transforms.csv
```

This compares FFT versus direct DFT, and FFT-based DCT versus the direct cosine
sum, reporting both time and maximum absolute error. Approximate floating-point
agreement is checked; exact floating-point equality is not assumed. Each
algorithm is batched for at least 0.2 elapsed seconds to reduce clock-resolution
effects. Transform speedup uses wall time per batch; CPU times are also retained.

