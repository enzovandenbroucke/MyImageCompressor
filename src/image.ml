(* Binary PPM I/O and image dimensions. Pixel rows are indexed [y][x]. *)
type rgb = { r : int; g : int; b : int }
type t = rgb array array

let max_pixels = 16_777_216
let validate_dimensions width height =
  if width <= 0 || height <= 0 || width > max_pixels / height then
    invalid_arg "Image dimensions must be positive and contain at most 16777216 pixels"

let dimensions pixels =
  let height = Array.length pixels in
  let width = if height = 0 then 0 else Array.length pixels.(0) in
  validate_dimensions width height;
  if Array.exists (fun row -> Array.length row <> width) pixels then
    invalid_arg "Image rows have different widths";
  (width, height)

let clamp x = max 0 (min 255 x)
let round x = int_of_float (Float.round x)

let with_input filename f =
  let ic = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> f ic)

let with_output filename f =
  let oc = open_out_bin filename in
  Fun.protect ~finally:(fun () -> close_out_noerr oc)
    (fun () -> let result = f oc in flush oc; result)

let whitespace = function ' ' | '\t' | '\r' | '\n' -> true | _ -> false

(* Read one header token, consuming exactly its delimiter. In particular we
   never skip whitespace in the binary raster: 10, 13 and 32 are valid samples. *)
let token ic =
  let rec skip_comment () =
    match input_char ic with '\n' -> () | _ -> skip_comment ()
  in
  let rec first () =
    let c = input_char ic in
    if whitespace c then first ()
    else if c = '#' then (skip_comment (); first ()) else c
  in
  let buf = Buffer.create 16 in
  Buffer.add_char buf (first ());
  let rec more () =
    let c = input_char ic in
    if whitespace c then begin
      if c = '\r' then begin
        let offset = pos_in ic in
        if input_char ic <> '\n' then seek_in ic offset
      end
    end else (Buffer.add_char buf c; more ())
  in
  more (); Buffer.contents buf

let read_ppm filename =
  with_input filename (fun ic ->
    try
      if token ic <> "P6" then invalid_arg "Only binary PPM P6 is supported";
      let width = int_of_string (token ic) in
      let height = int_of_string (token ic) in
      validate_dimensions width height;
      if int_of_string (token ic) <> 255 then
        invalid_arg "PPM maximum sample value must be 255";
      let needed = 3 * width * height in
      if in_channel_length ic - pos_in ic < needed then
        invalid_arg "Truncated PPM pixel data";
      Array.init height (fun _ -> Array.init width (fun _ ->
        let r = input_byte ic in
        let g = input_byte ic in
        let b = input_byte ic in
        { r; g; b }))
    with End_of_file -> invalid_arg "Truncated PPM header")

let write_ppm filename pixels =
  let width, height = dimensions pixels in
  with_output filename (fun oc ->
    Printf.fprintf oc "P6\n%d %d\n255\n" width height;
    Array.iter (Array.iter (fun p ->
      if List.exists (fun x -> x < 0 || x > 255) [p.r; p.g; p.b] then
        invalid_arg "RGB samples must be between 0 and 255";
      output_byte oc p.r; output_byte oc p.g; output_byte oc p.b)) pixels)

let psnr a b =
  let width, height = dimensions a in
  if dimensions b <> (width, height) then invalid_arg "PSNR dimensions differ";
  let squared_error = ref 0. in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let p = a.(y).(x) and q = b.(y).(x) in
      List.iter (fun d -> let f = float_of_int d in
        squared_error := !squared_error +. f *. f)
        [p.r - q.r; p.g - q.g; p.b - q.b]
    done
  done;
  if !squared_error = 0. then infinity
  else 10. *. log10 (255. *. 255. *. float_of_int (3 * width * height) /. !squared_error)
