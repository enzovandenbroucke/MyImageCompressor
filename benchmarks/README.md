# Executed measurements

- `div2k-0801.csv`: one DIV2K validation photograph at its original 2040×1356
  dimensions, qualities 10, 50 and 90, one measured run per quality after warmup.
- `synthetic.csv`: deterministic 640×384 image included in `examples/`, the same
  three qualities, one measured run per quality after warmup.
- `transforms.csv`: seeded direct/FFT comparisons; 50 source signals or blocks
  per batch, each algorithm batched for at least 0.2 elapsed seconds.
- Companion JSON files identify the platform, compiler/build and input hashes.
- `conversion-manifest.json` identifies the source PNG and resulting PPM for
  the single photographic benchmark.
- `photo-0809.csv` and `photo-0809.json`: full-resolution image metrics for the
  photographic README example, computed from the actual saved/reloaded codec
  files. This visual example has no runtime columns and is separate from the
  timing benchmark.

These are OCaml 4.14.0 bytecode measurements on Windows, produced during
repository preparation on 2 October 2026. They are examples of the measurement
workflow, not an evaluation of the complete DIV2K validation set.

| Quality | Complete file bpp | RGB PSNR (dB) | RGB / compressed size |
| --- | --- | --- | --- |
| 10 | 0.341 | 27.83 | 70.29× |
| 50 | 0.920 | 33.37 | 26.08× |
| 90 | 2.273 | 37.77 | 10.56× |

This table refers only to `0801`. PNG size is not the reference size. Runtime
figures in the CSV include both CPU and wall time, and seconds/decimal MB of
the original RGB raster. Full definitions appear in the root README.
