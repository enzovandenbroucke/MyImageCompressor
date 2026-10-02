# From FFT to block DCT

The retained code starts from polynomial evaluation. A length-N DFT evaluates
the sample polynomial at N roots of unity. `separe` separates even and odd
coefficients, and `fft_opt` recursively combines the two transforms with
Cooley–Tukey butterflies. Power-of-two lengths give O(N log N) arithmetic
instead of the direct DFT's O(N²). `fft` zero-pads other lengths.

For samples f[y], the unnormalized DCT-II coefficient is

```text
C[u] = sum(y=0..N-1) f[y] cos(pi (2y+1) u / (2N))
```

`adapte_fft2` places the N real samples in the first half of a zero-filled
length-2N signal. It takes that signal's FFT, multiplies coefficient u by
exp(-i pi u / (2N)), then takes the real part. This produces the cosine sum
above. The historical alternate `adapte_fft` constructs an even, sparse
length-4N signal; it remains available as another derivation.

The 2D transform is separable: apply the 1D transform to every row and then
every column. `dct_opti` applies the orthonormal scale factors:

```text
alpha(0) = sqrt(1/N)
alpha(k) = sqrt(2/N), k > 0
F[u,v] = alpha(u) alpha(v) sum(x,y) f[x,y] cos(...) cos(...)
```

`adapte_ifft` evaluates a zero-padded coefficient signal at odd sample indices.
Despite the historical function name, its construction uses a forward FFT and
real parts to obtain the inverse cosine sums. `idct_opti` combines rows and
columns and applies the corresponding scale factors.

Before the transform, every sample plane is shifted by 128. After inverse DCT,
luminance is shifted back. Chroma values remain centered for RGB reconstruction.
Quantization divides each coefficient by its frequency-dependent integer
quantizer and rounds it; inverse quantization multiplies by the same value.

The tests compare the FFT-based DCT to an independent direct cosine sum for
1×1 through 16×16 blocks, and check inverse reconstruction before quantization.
The reference's normalization is generalized to N: the historical naive code
used a fixed division by 4, valid for 8×8 but not arbitrary block sizes.

The actual image codec uses 8×8 blocks. O(N log N) scaling alone does not prove
a practical speed advantage at this small fixed size: recursive calls, lists,
complex arithmetic and allocation have costs. The `transforms` command measures
both error and runtime, and keeps that question empirical.
