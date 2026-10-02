(* The original FFT/DCT and JPEG-style pipeline, with edge replication and
   packed entropy streams. No whole-image lists of individual bits are built. *)
type compressed = {
  width : int; height : int; quality : int;
  y : Bits.stream; cb : Bits.stream; cr : Bits.stream;
}

let validate_quality quality =
  if quality < 1 || quality > 100 then invalid_arg "Quality must be between 1 and 100"

let padded n = ((n + 15) / 16) * 16
let quantization_tables quality =
  validate_quality quality;
  let scale = if quality < 50 then 5000 / quality else 200 - 2 * quality in
  let scale_table table = Array.map (Array.map (fun value ->
    max 1 ((scale * value + 50) / 100))) table in
  (scale_table Tables.tb_lum, scale_table Tables.tb_chr)

let planes pixels width height =
  let ph = padded height and pw = padded width in
  let lum = Array.make_matrix ph pw 0.
  and cb = Array.make_matrix (ph / 2) (pw / 2) 0.
  and cr = Array.make_matrix (ph / 2) (pw / 2) 0. in
  for row = 0 to ph - 1 do
    for col = 0 to pw - 1 do
      let p : Image.rgb = pixels.(min row (height-1)).(min col (width-1)) in
      let l = 0.299 *. float_of_int p.r +. 0.587 *. float_of_int p.g
        +. 0.114 *. float_of_int p.b in
      lum.(row).(col) <- l;
      cb.(row/2).(col/2) <- cb.(row/2).(col/2) +.
        (0.564 *. (float_of_int p.b -. l) +. 128.) /. 4.;
      cr.(row/2).(col/2) <- cr.(row/2).(col/2) +.
        (0.713 *. (float_of_int p.r -. l) +. 128.) /. 4.
    done
  done;
  lum, cb, cr

let encode_plane ~luminance plane table =
  let writer = Bits.writer () and previous = ref 0 in
  for row = 0 to Array.length plane / 8 - 1 do
    for col = 0 to Array.length plane.(0) / 8 - 1 do
      let block = Array.init 8 (fun y -> Array.init 8 (fun x ->
        plane.(8*row+y).(8*col+x) -. 128.)) in
      Dct.dct_opti block;
      let quantized = Array.mapi (fun y -> Array.mapi (fun x value ->
        Image.round (value /. float_of_int table.(y).(x)))) block in
      previous := Entropy.encode ~luminance writer !previous quantized
    done
  done;
  Bits.finish writer

let encode pixels quality =
  let width, height = Image.dimensions pixels in
  let lum_table, chr_table = quantization_tables quality in
  let lum, cb, cr = planes pixels width height in
  let y = encode_plane ~luminance:true lum lum_table in
  let cb = encode_plane ~luminance:false cb chr_table in
  let cr = encode_plane ~luminance:false cr chr_table in
  { width; height; quality; y; cb; cr }

let decode_plane ~luminance stream width height table =
  let reader = Bits.reader stream and previous = ref 0 in
  let plane = Array.make_matrix height width 0. in
  for row = 0 to height / 8 - 1 do
    for col = 0 to width / 8 - 1 do
      let quantized, dc = Entropy.decode ~luminance reader !previous in
      previous := dc;
      (* 8-bit source DC coefficients are bounded by +/-1024 before quantization. *)
      if abs dc > 2048 then invalid_arg "DC coefficient outside supported range";
      let block = Array.init 8 (fun y -> Array.init 8 (fun x ->
        float_of_int (quantized.(y).(x) * table.(y).(x)))) in
      Dct.idct_opti block;
      for y = 0 to 7 do
        for x = 0 to 7 do plane.(8*row+y).(8*col+x) <- block.(y).(x) done
      done
    done
  done;
  if Bits.remaining reader <> 0 then invalid_arg "Unused bits after last image block";
  plane

let decode image =
  Image.validate_dimensions image.width image.height;
  let lum_table, chr_table = quantization_tables image.quality in
  let pw = padded image.width and ph = padded image.height in
  let lum = decode_plane ~luminance:true image.y pw ph lum_table in
  let cb = decode_plane ~luminance:false image.cb (pw/2) (ph/2) chr_table in
  let cr = decode_plane ~luminance:false image.cr (pw/2) (ph/2) chr_table in
  Array.init image.height (fun y -> Array.init image.width (fun x ->
    let l = lum.(y).(x) +. 128. in
    let c_b = cb.(y/2).(x/2) and c_r = cr.(y/2).(x/2) in
    let sample value = Image.clamp (Image.round value) in
    Image.{ r = sample (l +. 1.402 *. c_r);
            g = sample (l -. 0.344 *. c_b -. 0.714 *. c_r);
            b = sample (l +. 1.772 *. c_b) }))

let payload_bits image = image.y.length + image.cb.length + image.cr.length
