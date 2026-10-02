(* Packed bits, most significant bit first. Valid bit length is stored separately
   from byte length so the last partial byte is never silently discarded. *)
type stream = { data : string; length : int }
type writer = { buffer : Buffer.t; mutable byte : int; mutable used : int;
                mutable count : int }
type reader = { stream : stream; mutable position : int }

let writer () = { buffer = Buffer.create 1024; byte = 0; used = 0; count = 0 }
let put w bit =
  w.byte <- (w.byte lsl 1) lor (if bit then 1 else 0);
  w.used <- w.used + 1; w.count <- w.count + 1;
  if w.used = 8 then begin
    Buffer.add_char w.buffer (Char.chr w.byte); w.byte <- 0; w.used <- 0
  end

let put_code w code =
  String.iter (function '0' -> put w false | '1' -> put w true
    | _ -> invalid_arg "Non-binary Huffman code") code

let put_value w size value =
  let encoded = if value >= 0 then value else (1 lsl size) - 1 + value in
  for i = size - 1 downto 0 do put w (encoded land (1 lsl i) <> 0) done

let finish w =
  let data = Buffer.contents w.buffer in
  { length = w.count; data = if w.used = 0 then data
      else data ^ String.make 1 (Char.chr (w.byte lsl (8 - w.used))) }

let validate stream =
  if stream.length < 0 || String.length stream.data <> (stream.length + 7) / 8 then
    invalid_arg "Packed stream length is inconsistent";
  let partial = stream.length mod 8 in
  if partial <> 0 &&
    Char.code stream.data.[String.length stream.data - 1] land
      ((1 lsl (8 - partial)) - 1) <> 0 then
    invalid_arg "Nonzero padding bits"

let reader stream = validate stream; { stream; position = 0 }
let remaining r = r.stream.length - r.position
let get r =
  if remaining r <= 0 then invalid_arg "Truncated entropy stream";
  let bit = Char.code r.stream.data.[r.position / 8] land
    (1 lsl (7 - r.position mod 8)) <> 0 in
  r.position <- r.position + 1; bit

let get_value r size =
  let value = ref 0 in
  for _ = 1 to size do value := (!value lsl 1) lor (if get r then 1 else 0) done;
  if size = 0 then 0
  else if !value land (1 lsl (size - 1)) <> 0 then !value
  else !value - ((1 lsl size) - 1)
