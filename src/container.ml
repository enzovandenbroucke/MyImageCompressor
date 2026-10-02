(* OJPG v1 is a custom research container, not a JPEG/JFIF file. *)
let header_bytes = 28
let file_bytes (image : Codec.compressed) = header_bytes +
  String.length image.y.data + String.length image.cb.data + String.length image.cr.data

let write filename (image : Codec.compressed) =
  Image.validate_dimensions image.width image.height;
  Codec.validate_quality image.quality;
  List.iter Bits.validate [image.y; image.cb; image.cr];
  Image.with_output filename (fun oc ->
    output_string oc "OJPG"; output_byte oc 1; output_byte oc image.quality;
    output_byte oc 0; output_byte oc 0;
    output_binary_int oc image.width; output_binary_int oc image.height;
    List.iter (fun (s : Bits.stream) -> output_binary_int oc s.length)
      [image.y; image.cb; image.cr];
    List.iter (fun (s : Bits.stream) -> output_string oc s.data)
      [image.y; image.cb; image.cr])

let read filename =
  Image.with_input filename (fun ic ->
    try
      if really_input_string ic 4 <> "OJPG" then invalid_arg "Invalid OJPG signature";
      if input_byte ic <> 1 then invalid_arg "Unsupported OJPG version";
      let quality = input_byte ic in Codec.validate_quality quality;
      let flag1 = input_byte ic in let flag2 = input_byte ic in
      if flag1 <> 0 || flag2 <> 0 then invalid_arg "Unsupported OJPG flags";
      let width = input_binary_int ic in let height = input_binary_int ic in
      Image.validate_dimensions width height;
      let y_length = input_binary_int ic in
      let cb_length = input_binary_int ic in
      let cr_length = input_binary_int ic in
      let blocks = Codec.padded width / 8 * (Codec.padded height / 8) in
      let validate_length length count =
        if length < count * 4 || length > count * 2048 then
          invalid_arg "Invalid entropy stream length" in
      validate_length y_length blocks;
      validate_length cb_length (blocks/4); validate_length cr_length (blocks/4);
      let byte_length n = (n+7)/8 in
      let expected = byte_length y_length + byte_length cb_length + byte_length cr_length in
      if in_channel_length ic - pos_in ic <> expected then
        invalid_arg "OJPG file length does not match its header";
      let stream length =
        let s = Bits.{ data = really_input_string ic (byte_length length); length } in
        Bits.validate s; s in
      let y = stream y_length in let cb = stream cb_length in let cr = stream cr_length in
      Codec.{ width; height; quality; y; cb; cr }
    with End_of_file -> invalid_arg "Truncated OJPG file")
