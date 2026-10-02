# OJPG version 1

This is a custom container for the project's three entropy streams. It is not
JPEG, JFIF, or PPM, and does not serialize OCaml runtime objects.

All multi-byte integers are 32-bit big-endian; valid values are nonnegative
and within signed 32-bit range. The reader validates dimensions and stream
lengths before reading stream data.

| Byte offset | Bytes | Field |
| --- | --- | --- |
| 0 | 4 | ASCII `OJPG` |
| 4 | 1 | Version = 1 |
| 5 | 1 | Quality = 1..100 |
| 6 | 2 | Reserved flags = zero |
| 8 | 4 | Original width |
| 12 | 4 | Original height |
| 16 | 4 | Valid bits in Y stream |
| 20 | 4 | Valid bits in Cb stream |
| 24 | 4 | Valid bits in Cr stream |
| 28 | ceil(Y bits / 8) | Packed Y bytes |
| following | ceil(Cb bits / 8) | Packed Cb bytes |
| following | ceil(Cr bits / 8) | Packed Cr bytes |

Bits are packed most significant bit first. Each stream's final partial byte
is zero-padded on the right. Padding is verified and is not passed to entropy
decoding. Trailing bytes, truncated files and nonzero reserved flags are rejected.

Dimensions used by block processing are implicit: round each source dimension
up to the next multiple of 16. Padding replicates the last row/column. Luminance
uses 8×8 blocks; the 4:2:0 chroma planes are half as wide and half as high.
The decoder returns only the original rectangle.

Blocks are stored in row-major order, separately for Y, Cb, then Cr. Each plane
starts with a zero DC predictor. A block contains a Huffman-coded DC category,
signed amplitude bits, zero-run/size AC symbols and a final EOB. This encoder
always writes EOB, including when coefficient 63 is nonzero. A ZRL symbol skips
exactly 16 zeros. The zigzag orientation and static tables are those of the
historical project and are fixed by this format version.

Quality tables are derived from the stored constants and quality parameter,
with minimum quantizer 1. The original coefficients for RGB/YCbCr conversion
are retained. Tables and sampling mode are not customizable in version 1.

The minimum entropy length and a conservative 2048-bit/block ceiling are checked
against the expected block count. At most 16,777,216 source pixels are accepted.
Files have no checksum or authenticity protection.
