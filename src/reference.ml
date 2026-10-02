(* Independent direct cosine sum, adapted from the original dct_naif.
   Its original fixed /4 normalization applied only to 8x8 blocks. *)
let dct block =
  let n = Array.length block in
  if n = 0 || Array.exists (fun row -> Array.length row <> n) block then
    invalid_arg "DCT reference expects a nonempty square block";
  let norm k = if k = 0 then sqrt (1. /. float_of_int n)
    else sqrt (2. /. float_of_int n) in
  Array.init n (fun u -> Array.init n (fun v ->
    let sum = ref 0. in
    for y = 0 to n - 1 do
      for x = 0 to n - 1 do
        sum := !sum +. block.(y).(x)
          *. cos (float_of_int ((2*y+1)*u) *. Float.pi /. float_of_int (2*n))
          *. cos (float_of_int ((2*x+1)*v) *. Float.pi /. float_of_int (2*n))
      done
    done;
    !sum *. norm u *. norm v))
