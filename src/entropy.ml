(* Zigzag, differential DC, zero-run AC, and fixed Huffman coding. *)
let category value =
  let rec loop n size = if n = 0 then size else loop (n / 2) (size + 1) in
  loop (abs value) 0

(* Retains the traversal orientation of the original TIPE. *)
let zigzag =
  let positions = ref [] in
  for diagonal = 0 to 14 do
    let low = max 0 (diagonal - 7) and high = min 7 diagonal in
    if diagonal mod 2 = 0 then
      for y = low to high do positions := (y, diagonal - y) :: !positions done
    else
      for y = high downto low do positions := (y, diagonal - y) :: !positions done
  done;
  Array.of_list (List.rev !positions)

type tree = Empty | Leaf of int | Node of tree * tree
let build codes =
  let rec insert tree code index value =
    if index = String.length code then
      match tree with Empty -> Leaf value | _ -> failwith "Huffman prefix collision"
    else match tree with
      | Leaf _ -> failwith "Huffman prefix collision"
      | Empty -> insert (Node (Empty, Empty)) code index value
      | Node (left, right) ->
          if code.[index] = '0' then Node (insert left code (index+1) value, right)
          else Node (left, insert right code (index+1) value)
  in
  Array.fold_left (fun (index, tree) code ->
    (index + 1, if code = "" then tree else insert tree code 0 index))
    (0, Empty) codes |> snd

let flatten a = Array.concat (Array.to_list a)
let dc_lum = build Tables.huffman_dc_luminance
let dc_chr = build Tables.huffman_dc_chrominance
let ac_lum = build (flatten Tables.huffman_ac_luminance)
let ac_chr = build (flatten Tables.huffman_ac_chrominance)

let read_symbol reader tree =
  let rec walk = function
    | Empty -> invalid_arg "Invalid Huffman code"
    | Leaf x -> x
    | Node (left, right) -> walk (if Bits.get reader then right else left)
  in walk tree

let encode ~luminance writer previous block =
  let dc_codes, ac_codes = if luminance then
      Tables.huffman_dc_luminance, Tables.huffman_ac_luminance
    else Tables.huffman_dc_chrominance, Tables.huffman_ac_chrominance in
  let dc = block.(0).(0) in
  let delta = dc - previous in
  let size = category delta in
  if size > 11 then invalid_arg "DC coefficient category exceeds 11";
  Bits.put_code writer dc_codes.(size); Bits.put_value writer size delta;
  let zeros = ref 0 in
  for index = 1 to 63 do
    let y, x = zigzag.(index) in
    let value = block.(y).(x) in
    if value = 0 then incr zeros
    else begin
      while !zeros >= 16 do
        Bits.put_code writer ac_codes.(15).(0); zeros := !zeros - 16
      done;
      let size = category value in
      if size > 10 then invalid_arg "AC coefficient category exceeds 10";
      Bits.put_code writer ac_codes.(!zeros).(size);
      Bits.put_value writer size value; zeros := 0
    end
  done;
  (* Always emit EOB, including dense blocks. Decoder consumes it explicitly. *)
  Bits.put_code writer ac_codes.(0).(0); dc

let decode ~luminance reader previous =
  let dc_tree, ac_tree = if luminance then dc_lum, ac_lum else dc_chr, ac_chr in
  let size = read_symbol reader dc_tree in
  let dc = previous + Bits.get_value reader size in
  let block = Array.make_matrix 8 8 0 in
  block.(0).(0) <- dc;
  let index = ref 1 and ended = ref false in
  while not !ended do
    let symbol = read_symbol reader ac_tree in
    let run = symbol / 11 and size = symbol mod 11 in
    if run = 0 && size = 0 then ended := true
    else if run = 15 && size = 0 then begin
      index := !index + 16;
      if !index > 64 then invalid_arg "Zero run exceeds block boundary"
    end else begin
      if size = 0 then invalid_arg "Invalid AC symbol";
      index := !index + run;
      if !index >= 64 then invalid_arg "AC coefficient exceeds block boundary";
      let y, x = zigzag.(!index) in
      block.(y).(x) <- Bits.get_value reader size;
      incr index
    end
  done;
  (block, dc)
