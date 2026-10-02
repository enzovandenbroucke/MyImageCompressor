let checks = ref 0
let check name condition =
  incr checks;
  if not condition then failwith name
let close a b = abs_float (a -. b) < 1e-7
let matrix_close a b =
  Array.length a = Array.length b &&
  Array.for_all Fun.id (Array.mapi (fun i row ->
    Array.length row = Array.length b.(i) &&
    Array.for_all Fun.id (Array.mapi (fun j v -> close v b.(i).(j)) row)) a)
let reject name f =
  let failed = try f (); false with Invalid_argument _ | Failure _ -> true in
  check name failed
let with_temp suffix f =
  let path = Filename.temp_file "jpeg-like-test-" suffix in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () -> f path)
let random = Random.State.make [|751;42|]

let test_transforms () =
  List.iter (fun n ->
    for _ = 1 to 10 do
      let block = Array.init n (fun _ -> Array.init n (fun _ ->
        Random.State.float random 256. -. 128.)) in
      let expected = Reference.dct block in
      let actual = Array.map Array.copy block in
      Dct.dct_opti actual;
      check "DCT agrees with direct cosine sum" (matrix_close expected actual);
      Dct.idct_opti actual;
      check "DCT/IDCT roundtrip" (matrix_close block actual)
    done
  ) [1;2;4;8;16];
  List.iter (fun n ->
    let signal = List.init n (fun _ -> Dct.f_to_c (Random.State.float random 256.)) in
    let a = Dct.fft signal and b = Dct.dft_naif signal in
    check "FFT agrees with DFT" (Array.for_all Fun.id (Array.mapi (fun i z ->
      Complex.norm (Complex.sub z b.(i)) < 1e-7) a))
  ) [1;2;4;8;16;64];
  let signal = List.init 7 (fun i -> Dct.f_to_c (float_of_int i)) in
  let a = Dct.fft signal and b = Dct.dft_naif (signal @ [Complex.zero]) in
  check "FFT zero padding" (Array.for_all Fun.id (Array.mapi (fun i z ->
    Complex.norm (Complex.sub z b.(i)) < 1e-7) a));
  reject "Empty FFT rejected" (fun () -> ignore (Dct.fft []));
  reject "Non-power-of-two DCT rejected" (fun () -> Dct.dct_opti (Array.make_matrix 3 3 0.));
  reject "Nonsquare DCT rejected" (fun () -> Dct.dct_opti [|[|1.;2.|];[|3.|]|])

let test_bits () =
  for length = 0 to 65 do
    let writer = Bits.writer () in
    let expected = Array.init length (fun i -> i mod 3 = 0) in
    Array.iter (Bits.put writer) expected;
    let stream = Bits.finish writer in
    check "Packed bit/byte length" (stream.length = length && String.length stream.data = (length+7)/8);
    let reader = Bits.reader stream in
    Array.iter (fun bit -> check "Bit roundtrip including partial bytes" (Bits.get reader = bit)) expected;
    reject "Reading beyond valid bits" (fun () -> ignore (Bits.get reader))
  done;
  for value = -2047 to 2047 do
    let writer = Bits.writer () and size = Entropy.category value in
    Bits.put_value writer size value;
    check "Signed amplitude roundtrip" (Bits.get_value (Bits.reader (Bits.finish writer)) size = value)
  done

let test_entropy () =
  let seen = Hashtbl.create 64 in
  Array.iter (fun position -> Hashtbl.replace seen position ()) Entropy.zigzag;
  check "Zigzag visits all 64 coefficients" (Hashtbl.length seen = 64);
  List.iter (fun luminance ->
    let writer = Bits.writer () and blocks = ref [] and previous = ref 0 in
    for trial = 0 to 199 do
      let block = Array.init 8 (fun _ -> Array.init 8 (fun _ ->
        if Random.State.int random 4 = 0 then 0 else Random.State.int random 201 - 100)) in
      if trial < 64 then begin
        Array.iter (fun row -> Array.fill row 0 8 0) block;
        let y,x = Entropy.zigzag.(trial) in block.(y).(x) <- -17
      end;
      previous := Entropy.encode ~luminance writer !previous block;
      blocks := block :: !blocks
    done;
    let reader = Bits.reader (Bits.finish writer) in
    previous := 0;
    List.iter (fun expected ->
      let actual, dc = Entropy.decode ~luminance reader !previous in
      previous := dc;
      check "Entropy chain exact roundtrip" (expected = actual)) (List.rev !blocks);
    check "All entropy bits consumed" (Bits.remaining reader = 0)
  ) [true;false]

let pattern width height = Array.init height (fun y -> Array.init width (fun x ->
  Image.{r=(x*7+y*3) mod 256;g=(x*2+y*11) mod 256;b=(x*5+y*5) mod 256}))

let test_images () =
  List.iter (fun (width,height) ->
    let pixels = pattern width height in
    List.iter (fun quality ->
      let encoded = Codec.encode pixels quality in
      let decoded = Codec.decode encoded in
      check "Original dimensions preserved" (Image.dimensions decoded = (width,height));
      Array.iter (Array.iter (fun (p : Image.rgb) -> check "RGB in range"
        (p.r>=0 && p.r<=255 && p.g>=0 && p.g<=255 && p.b>=0 && p.b<=255))) decoded;
      with_temp ".ojpg" (fun path ->
        Container.write path encoded;
        let disk_size = Image.with_input path in_channel_length in
        check "Container size matches disk size" (disk_size = Container.file_bytes encoded);
        let reread = Container.read path in
        check "Container preserves exact streams" (reread = encoded);
        check "File and memory reconstruction agree" (Codec.decode reread = decoded))
    ) [1;50;75;100];
    with_temp ".ppm" (fun path -> Image.write_ppm path pixels;
      check "PPM roundtrip" (Image.read_ppm path = pixels));
    check "Identical image PSNR is infinite" (Image.psnr pixels pixels = infinity)
  ) [1,1;7,9;8,8;16,16;17,31;31,17;64,33;480,240];
  List.iter (fun value ->
    let pixels = Array.make_matrix 17 19 Image.{r=value;g=value;b=value} in
    check "Flat grayscale quality 100 is exact" (Codec.decode (Codec.encode pixels 100) = pixels)
  ) [0;128;255];
  List.iter (fun q -> reject "Invalid quality" (fun () -> ignore (Codec.encode (pattern 1 1) q))) [-1;0;101];
  reject "PSNR dimensions" (fun () -> ignore (Image.psnr (pattern 1 1) (pattern 2 1)))

let test_ppm_headers () =
  with_temp ".ppm" (fun path ->
    Image.with_output path (fun oc -> output_string oc "P6\r\n# comment\r\n1\t1\r\n255\r\n";
      List.iter (output_byte oc) [10;13;32]);
    check "Comments, tabs, CRLF, and raster whitespace bytes"
      (Image.read_ppm path = [|[|Image.{r=10;g=13;b=32}|]|]);
    Image.with_output path (fun oc -> output_string oc "P6\n1 1\n65535\n");
    reject "Reject non-8-bit PPM" (fun () -> ignore (Image.read_ppm path));
    Image.with_output path (fun oc -> output_string oc "P6\n1 1\n255\n\000");
    reject "Reject truncated PPM" (fun () -> ignore (Image.read_ppm path)))

let test_corruption () =
  with_temp ".ojpg" (fun path ->
    let encoded = Codec.encode (pattern 17 19) 75 in
    Container.write path encoded;
    let bytes = Image.with_input path (fun ic -> really_input_string ic (in_channel_length ic)) in
    for n = 0 to String.length bytes - 1 do
      Image.with_output path (fun oc -> output_string oc (String.sub bytes 0 n));
      reject "Every file truncation rejected" (fun () -> ignore (Container.read path))
    done;
    Image.with_output path (fun oc -> output_string oc (bytes ^ "x"));
    reject "Trailing file data rejected" (fun () -> ignore (Container.read path));
    let modified = Bytes.of_string bytes in Bytes.set modified 4 (Char.chr 2);
    Image.with_output path (fun oc -> output_bytes oc modified);
    reject "Unknown container version rejected" (fun () -> ignore (Container.read path)));
  reject "Invalid Huffman branch" (fun () ->
    let writer = Bits.writer () in Bits.put_code writer "1111111111111111";
    ignore (Entropy.read_symbol (Bits.reader (Bits.finish writer)) Entropy.ac_lum))

let () =
  test_transforms (); test_bits (); test_entropy (); test_images ();
  test_ppm_headers (); test_corruption ();
  Printf.printf "Passed %d checks\n" !checks
