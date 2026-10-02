# MyImageCompressor

A JPEG-inspired image compressor written in OCaml as a personal scientific
project. I built it to study how frequency transforms, quantization and entropy
coding turn an image into a smaller representation, and how compression affects
visual quality.

The numerical core includes a recursive Cooley–Tukey FFT used to compute the
2D discrete cosine transform (DCT) and its inverse. The complete encoder and
decoder combine color conversion, 4:2:0 chroma subsampling, 8×8 block transforms,
quantization, zigzag traversal, differential DC coding and Huffman coding.
Direct transform formulas and automated regression tests validate the implementation.

## Visual example

Original photograph and reconstructions at qualities 10, 50 and 90 (scale 1-100, higher quality = less compression) :

![Original lion photograph and three reconstructions](docs/photo-0809.png)

The same region around the lion's eye, enlarged equally to reveal compression artifacts:

![Comparison of the lion's eye at three compression qualities](docs/photo-0809-detail.png)

The image is `0809.png` from [DIV2K](https://data.vision.ee.ethz.ch/cvl/DIV2K/).
Compression uses the full original resolution; resizing and enlargement are only
for display. The bpp and PSNR labels refer to the whole image.
See [image attribution](docs/image-attribution.md).

## Build and use

Requires OCaml 4.14 or later and Dune 3 or later.

```sh
opam install dune
opam exec -- dune build
opam exec -- dune runtest
opam exec -- dune exec bin/main.exe -- compress input.ppm output.ojpg --quality 75
opam exec -- dune exec bin/main.exe -- decompress output.ojpg reconstructed.ppm
```

Input images are binary PPM (P6, 8-bit RGB). Quality ranges from 1 to 100;
even quality 100 remains lossy because of chroma subsampling and rounding.
PNG conversion and alternative build instructions are in the
[usage guide](docs/usage.md).

The custom `.ojpg` format is inspired by JPEG but is not JPEG/JFIF compatible.
Decode it to PPM to view the result.

## Evaluation and implementation

Benchmark tools measure bits per pixel, compression ratio, RGB PSNR and
encoding/decoding time per MB. The [benchmark guide](docs/benchmarks.md)
describes the commands and measurement definitions.

The main modules are [`dct.ml`](src/dct.ml) for the transforms,
[`codec.ml`](src/codec.ml) for the image pipeline,
[`entropy.ml`](src/entropy.ml) for coefficient coding, and
[`container.ml`](src/container.ml) for file storage.
See the [transform explanation](docs/transforms.md) and
[file format specification](docs/format.md) for details.

## Scope and possible extensions

This project is complete. The implementation uses fixed coding tables,
nearest-neighbor chroma reconstruction and a single-threaded pipeline.
Possible extensions include comparing 4:4:4 and 4:2:0 subsampling, profiling
native execution, measuring memory use, or comparing rate–distortion with a
standard JPEG encoder. These are exploration ideas, with no further work
currently planned.

## License

The source code is released under the [MIT License](LICENSE).
The DIV2K photographs retain their separate usage conditions, described in
[image attribution](docs/image-attribution.md).
