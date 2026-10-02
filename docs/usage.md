# Additional usage instructions

See the [README](../README.md) for the standard Dune build and codec commands.

## Build without Dune

If Dune is unavailable, a Python build helper can compile the same sources:

```sh
python scripts/build.py --compiler ocamlc --test
python scripts/build.py --compiler ocamlopt --test
```

These produce `_build/bytecode/jpeg-like.exe` or
`_build/native/jpeg-like.exe`. The `.exe` name is used consistently on all
platforms. Bytecode requires a working `ocamlrun`; native builds require the
platform's OCaml C toolchain. The helper also accepts an absolute compiler path.

## PNG inputs and datasets


The historical OCaml source does not implement PNG decoding. This repository
provides a separate conversion step using Pillow:

```sh
python -m pip install -r scripts/requirements.txt
python scripts/prepare_dataset.py path/to/DIV2K_valid_HR data/div2k-ppm
```

The script preserves dimensions, converts to 8-bit RGB and writes a manifest
with source/output hashes. It does not resize, crop or apply color-profile
conversion. Transparent images require an explicit background choice and are
rejected. For a quick experiment, add `--limit 3`.

Obtain DIV2K validation images from the
[official dataset page](https://data.vision.ee.ethz.ch/cvl/DIV2K/).
The images are not included in this repository. Dataset authors restrict
availability to academic research and retain the original image owners'
copyright; see their terms and requested citations.

## Reproduce the photographic example

After obtaining the DIV2K validation dataset and installing the Python dependencies:

```sh
python scripts/make_photo_demo.py data/DIV2K_valid_HR/0809.png --crop 760 300 1080 620
```
