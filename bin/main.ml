let usage = "Usage:\n\
  jpeg-like compress INPUT.ppm OUTPUT.ojpg [--quality 75]\n\
  jpeg-like decompress INPUT.ojpg OUTPUT.ppm\n\
  jpeg-like benchmark INPUT.ppm ... [--qualities 10,30,50,75,90,100] [--repeat 1] [--warmup 0] [--csv results.csv]\n\
  jpeg-like transforms [--repeat 50] [--max-power 6] [--csv transforms.csv]\n"

let parse rest specs =
  let positional = ref [] in
  Arg.parse_argv ~current:(ref 0) (Array.of_list ("jpeg-like" :: rest)) specs
    (fun path -> positional := path :: !positional) usage;
  List.rev !positional

let with_csv filename f =
  match filename with
  | "-" -> f stdout
  | _ -> Image.with_output filename f

let csv_quote s = "\"" ^ String.concat "\"\"" (String.split_on_char '"' s) ^ "\""
let median values =
  let a = Array.of_list values in Array.sort compare a;
  let n = Array.length a in
  if n mod 2 = 1 then a.(n/2) else (a.(n/2-1) +. a.(n/2)) /. 2.

let timed f =
  let wall = Unix.gettimeofday () and cpu = Sys.time () in
  let result = f () in
  result, Sys.time () -. cpu, Unix.gettimeofday () -. wall

let benchmark paths qualities repeat warmup csv =
  if paths = [] then invalid_arg "Provide at least one PPM image";
  if repeat < 1 then invalid_arg "Repeat must be positive";
  if warmup < 0 then invalid_arg "Warmup must be nonnegative";
  let qualities = List.map int_of_string (String.split_on_char ',' qualities) in
  List.iter Codec.validate_quality qualities;
  with_csv csv (fun oc ->
    output_string oc "image,quality,width,height,raw_rgb_bytes,payload_bits,file_bytes,payload_bpp,file_bpp,compression_ratio,space_saving_percent,psnr_db,encode_cpu_s,decode_cpu_s,encode_wall_s,decode_wall_s,encode_cpu_s_per_mb,decode_cpu_s_per_mb,encode_wall_s_per_mb,decode_wall_s_per_mb,encode_mb_per_s,decode_mb_per_s,repeats,warmup_runs\n";
    List.iter (fun path ->
      let pixels = Image.read_ppm path in
      let width, height = Image.dimensions pixels in
      let raw_bytes = 3 * width * height in
      let mb = float_of_int raw_bytes /. 1_000_000. in
      List.iter (fun quality ->
        (* Warmup is optional; by default the first pass supplies all metrics.
           Parsing and disk I/O are outside codec timings. *)
        for _ = 1 to warmup do
          ignore (Codec.decode (Codec.encode pixels quality))
        done;
        let enc_cpu = ref [] and enc_wall = ref []
        and dec_cpu = ref [] and dec_wall = ref [] in
        let last = ref None in
        for _ = 1 to repeat do
          Gc.full_major ();
          let encoded, cpu, wall = timed (fun () -> Codec.encode pixels quality) in
          enc_cpu := cpu :: !enc_cpu; enc_wall := wall :: !enc_wall;
          Gc.full_major ();
          let decoded, cpu, wall = timed (fun () -> Codec.decode encoded) in
          dec_cpu := cpu :: !dec_cpu; dec_wall := wall :: !dec_wall;
          last := Some (encoded, decoded)
        done;
        let encoded, decoded = Option.get !last in
        let bits = Codec.payload_bits encoded and bytes = Container.file_bytes encoded in
        let ec = median !enc_cpu and dc = median !dec_cpu
        and ew = median !enc_wall and dw = median !dec_wall in
        let n = float_of_int (width * height) in
        let fields = [
          csv_quote path; string_of_int quality; string_of_int width; string_of_int height;
          string_of_int raw_bytes; string_of_int bits; string_of_int bytes;
          Printf.sprintf "%.8f" (float_of_int bits /. n);
          Printf.sprintf "%.8f" (8. *. float_of_int bytes /. n);
          Printf.sprintf "%.8f" (float_of_int raw_bytes /. float_of_int bytes);
          Printf.sprintf "%.8f" (100. *. (1. -. float_of_int bytes /. float_of_int raw_bytes));
          Printf.sprintf "%.8f" (Image.psnr pixels decoded)
        ] @ List.map (Printf.sprintf "%.9f")
          [ec;dc;ew;dw;ec/.mb;dc/.mb;ew/.mb;dw/.mb;
           (if ew <= 0. then nan else mb/.ew); (if dw <= 0. then nan else mb/.dw)]
          @ [string_of_int repeat; string_of_int warmup] in
        output_string oc (String.concat "," fields ^ "\n"); flush oc;
        Printf.eprintf "%s q=%d: %.3f bpp, %.2f dB\n%!" (Filename.basename path)
          quality (8. *. float_of_int bytes /. n) (Image.psnr pixels decoded)
      ) qualities
    ) paths)

let transforms repeat max_power csv =
  if repeat < 1 || max_power < 0 || max_power > 9 then
    invalid_arg "Repeat must be positive and max-power between 0 and 9";
  let random = Random.State.make [|2026;10;2|] in
  (* Windows CPU clocks can have a coarse tick. Batch each algorithm for at
     least 0.2 wall seconds; compare elapsed time per batch, not zero CPU ticks. *)
  let measure f =
    let started = Unix.gettimeofday () and cpu_start = Sys.time () in
    let count = ref 1 and result = ref (f ()) in
    while Unix.gettimeofday () -. started < 0.2 do
      result := f (); incr count
    done;
    let cpu = (Sys.time () -. cpu_start) /. float_of_int !count in
    let wall = (Unix.gettimeofday () -. started) /. float_of_int !count in
    !result, cpu, wall, !count
  in
  with_csv csv (fun oc ->
    output_string oc "kind,n,signals_per_batch,naive_batches,fft_batches,naive_cpu_s_per_batch,fft_cpu_s_per_batch,naive_wall_s_per_batch,fft_wall_s_per_batch,wall_speedup,max_abs_error\n";
    for power = 0 to max_power do
      let n = 1 lsl power in
      let signals = Array.init repeat (fun _ -> List.init n (fun _ ->
        Dct.f_to_c (Random.State.float random 256. -. 128.))) in
      let naive, nc, nw, nb = measure (fun () -> Array.map Dct.dft_naif signals) in
      let fast, fc, fw, fb = measure (fun () -> Array.map Dct.fft signals) in
      let error = ref 0. in
      Array.iteri (fun i row -> Array.iteri (fun j value ->
        error := max !error (Complex.norm (Complex.sub value fast.(i).(j)))) row) naive;
      Printf.fprintf oc "DFT,%d,%d,%d,%d,%.9f,%.9f,%.9f,%.9f,%.6f,%.12g\n"
        n repeat nb fb nc fc nw fw (nw/.fw) !error
    done;
    (* Block DCT comparison uses the mathematically normalized reference. *)
    for power = 1 to min max_power 4 do
      let n = 1 lsl power in
      let blocks = Array.init repeat (fun _ -> Array.init n (fun _ ->
        Array.init n (fun _ -> Random.State.float random 256. -. 128.))) in
      let naive, nc, nw, nb = measure (fun () -> Array.map Reference.dct blocks) in
      let fast, fc, fw, fb = measure (fun () -> Array.map (fun b ->
        let b = Array.map Array.copy b in Dct.dct_opti b; b) blocks) in
      let error = ref 0. in
      Array.iteri (fun i b -> Array.iteri (fun y row -> Array.iteri (fun x value ->
        error := max !error (abs_float (value -. fast.(i).(y).(x)))) row) b) naive;
      Printf.fprintf oc "DCT,%d,%d,%d,%d,%.9f,%.9f,%.9f,%.9f,%.6f,%.12g\n"
        n repeat nb fb nc fc nw fw (nw/.fw) !error
    done)

let run () =
  match Array.to_list Sys.argv with
  | _ :: "compress" :: rest ->
      let quality = ref 75 in
      let paths = parse rest ["--quality", Arg.Set_int quality, "Quality in [1,100]"] in
      (match paths with [input;output] ->
        Container.write output (Codec.encode (Image.read_ppm input) !quality)
      | _ -> invalid_arg "compress expects input and output paths")
  | _ :: "decompress" :: rest ->
      (match parse rest [] with [input;output] ->
        Image.write_ppm output (Codec.decode (Container.read input))
      | _ -> invalid_arg "decompress expects input and output paths")
  | _ :: "benchmark" :: rest ->
      let qualities = ref "10,30,50,75,90,100" and repeat = ref 1
      and warmup = ref 0 and csv = ref "-" in
      let paths = parse rest [
        "--qualities", Arg.Set_string qualities, "Comma-separated qualities";
        "--repeat", Arg.Set_int repeat, "Measured runs per quality (default: 1)";
        "--warmup", Arg.Set_int warmup, "Unmeasured warmup runs per quality (default: 0)";
        "--csv", Arg.Set_string csv, "Output CSV path, or - for stdout"] in
      benchmark paths !qualities !repeat !warmup !csv
  | _ :: "transforms" :: rest ->
      let repeat = ref 50 and max_power = ref 6 and csv = ref "-" in
      let paths = parse rest [
        "--repeat", Arg.Set_int repeat, "Number of signals/blocks";
        "--max-power", Arg.Set_int max_power, "Largest DFT size as power of two";
        "--csv", Arg.Set_string csv, "Output CSV path"] in
      if paths <> [] then invalid_arg "transforms takes no image paths";
      transforms !repeat !max_power !csv
  | _ :: ("--help" | "-h") :: _ -> print_string usage
  | _ -> invalid_arg usage

let () =
  try run () with
  | Arg.Help text -> print_string text
  | Invalid_argument text | Failure text | Sys_error text | Arg.Bad text ->
      Printf.eprintf "Error: %s\n" text; exit 2
