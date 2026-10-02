(* FFT and FFT-based DCT/IDCT adapted from the original TIPE final/FFT.ml. *)
type c = Complex.t

type polynome = c list

type graphe = c array

let check_block block =
  let n = Array.length block in
  if n = 0 || n land (n - 1) <> 0 ||
     Array.exists (fun row -> Array.length row <> n) block then
    invalid_arg "FFT-based DCT requires a nonempty square power-of-two block"

let int_to_c (n : int) : c = { Complex.re = Float.of_int n; Complex.im = 0. }

let rec lst_int_to_c (lst : int list) : c list =
  match lst with
  | [] -> []
  | n :: ns -> int_to_c n :: lst_int_to_c ns

let f_to_c (x : float) : c = { Complex.re = x; Complex.im = 0. }

let rec eval (p : polynome) (z : c) : c =
  match p with
  | [] -> Complex.zero
  | a :: q -> Complex.add a (Complex.mul z (eval q z))

let dft_naif (p : polynome) : graphe =
  let n = List.length p in
  let res = Array.make n Complex.zero in
  let omega = Complex.polar 1. (-2. *. Float.pi /. Float.of_int n) in
  let z = ref Complex.one in
  for i = 0 to n - 1 do
    res.(i) <- eval p !z;
    z := Complex.mul !z omega
  done;
  res

let degre (p : polynome) = List.length p - 1

let rec separe (p : polynome) =
  match p with
  | a :: b :: q ->
      let r, s = separe q in
      (a :: r, b :: s)
  | _ -> (p, [])

let standardise (p : polynome) : polynome * int =
  let pow = ref 1 in
  let d = degre p in
  let coeffs = ref [] in
  while !pow <= d do
    pow := 2 * !pow
  done;
  for _i = d + 2 to !pow do
    coeffs := Complex.zero :: !coeffs
  done;
  (p @ !coeffs, !pow )

let rec fft_opt (q : polynome) (pow : int) (omega : c) : graphe =
  if pow = 1 then
    [| eval q Complex.one |]
  else begin
    let r, s = separe q in
    let t = Array.make pow Complex.zero in
    let m = pow / 2 in
    let omega' = Complex.mul omega omega in
    let g1 = fft_opt r m omega' in
    let g2 = fft_opt s m omega' in
    let z = ref Complex.one in
    for i = 0 to m - 1 do
      let u = Complex.mul !z g2.(i) in
      t.(i) <- Complex.add g1.(i) u;
      t.(m + i) <- Complex.sub g1.(i) u;
      z := Complex.mul !z omega
    done;
    t
  end

let fft (p : polynome) : graphe =
  if p = [] then invalid_arg "FFT requires a nonempty signal";
  let coeffs, pow = standardise p in
  let omega = Complex.polar 1. (-2. *. Float.pi /. Float.of_int pow) in
  fft_opt coeffs pow omega

let adapte_fft (f : int -> float) (n : int) : float array =
  
  let res = Array.make n 0. in
  let temp = Array.make (4 * n) Complex.zero in
  for i = 0 to n - 1 do
    temp.(2 * i) <- Complex.zero;
    temp.((4 * n) - 2 - (2 * i)) <- Complex.zero;
    temp.((2 * i) + 1) <- f_to_c (f i);
    temp.((4 * n) - ((2 * i) + 1)) <- f_to_c (f i)
  done;
  let lst = Array.to_list temp in
  let omega = Complex.polar 1. (-.Float.pi /. Float.of_int (2 * n)) in
  let t = fft_opt lst (4 * n) omega in
  for u = 0 to n - 1 do
    res.(u) <- 0.5 *. t.(u).re
  done;
  res

let adapte_fft2 (f : int -> float) (n : int) : float array =
  let res = Array.make n 0. in
  let f_tilde = Array.make (2 * n) Complex.zero in
  for i = 0 to n - 1 do
    f_tilde.(i) <- f_to_c (f i)
  done;
  let lst = Array.to_list f_tilde in
  let omega = Complex.polar 1. (-.Float.pi /. Float.of_int (2 * n)) in
  let omega' = Complex.mul omega omega in
  let t = fft_opt lst (2 * n) omega' in
  let z = ref Complex.one in
  for u = 0 to n - 1 do
    res.(u) <- (Complex.mul !z t.(u)).re;
    z := Complex.mul !z omega
  done;
  res

let teste_adapte f n =
  let res = Array.make n 0. in
  for u = 0 to n - 1 do
    for y = 0 to n - 1 do
      let x = Float.of_int (((2 * y) + 1) * u) /. Float.of_int (2 * n) in
      res.(u) <- res.(u) +. (f y *. Float.cos (x *. Float.pi))
    done
  done;
  res

type int_bloc = int array array

type c_bloc = c array array

type f_bloc = float array array

let dct_ligne (bloc : f_bloc) (n : int) : f_bloc =
  let res = Array.make_matrix n n 0. in
  for i = 0 to n - 1 do
    let f y = bloc.(i).(y) in
    let c = adapte_fft2 f n in
    for j = 0 to n - 1 do
      res.(i).(j) <- c.(j)
    done
  done;
  res

let dct_colonne (bloc : f_bloc) (n : int) : f_bloc =
  let res = Array.make_matrix n n 0. in
  for j = 0 to n - 1 do
    let f x = bloc.(x).(j) in
    let c = adapte_fft2 f n in
    for i = 0 to n - 1 do
      res.(i).(j) <- c.(i)
    done
  done;
  res

let dct_opti (bloc : f_bloc) : unit =
  check_block bloc;
  
  let n = Array.length bloc in
  let temp = dct_colonne (dct_ligne bloc n) n in
  let x = 1. /. Float.of_int n in
  bloc.(0).(0) <- temp.(0).(0) *. x;
  let y = Float.sqrt 2. *. x in
  for k = 1 to n - 1 do
    bloc.(k).(0) <- temp.(k).(0) *. y;
    bloc.(0).(k) <- temp.(0).(k) *. y
  done;
  for i = 1 to n - 1 do
    for j = 1 to n - 1 do
      bloc.(i).(j) <- temp.(i).(j) *. 2. *. x
    done
  done

let adapte_ifft (g : int -> float) (n : int) =
  let g_tilde = Array.make (4 * n) Complex.zero in
  for i = 1 to n - 1 do
    g_tilde.(i) <- f_to_c (g i)
  done;
  g_tilde.(0) <- f_to_c (g 0 *. sqrt 0.5);
  let res = Array.make n 0. in
  let t = fft (Array.to_list g_tilde) in
  for x = 0 to n - 1 do
    res.(x) <- t.((2 * x) + 1).re
  done;
  res

let grand_c x = if x = 0 then sqrt 0.5 else 1.

let teste_adapte_ifft g n =
  let res = Array.make n 0. in
  for x = 0 to n - 1 do
    for i = 0 to n - 1 do
      let u = Float.of_int (((2 * x) + 1) * i) /. Float.of_int (2 * n) in
      res.(x) <- res.(x) +. (g i *. grand_c i *. Float.cos (u *. Float.pi))
    done
  done;
  res

let idct_ligne (bloc : f_bloc) (n : int) : f_bloc =
  let res = Array.make_matrix n n 0. in
  for x = 0 to n - 1 do
    let g j = bloc.(x).(j) in
    let c = adapte_ifft g n in
    for y = 0 to n - 1 do
      res.(x).(y) <- c.(y)
    done
  done;
  res

let idct_colonne (bloc : f_bloc) (n : int) : f_bloc =
  let res = Array.make_matrix n n 0. in
  for y = 0 to n - 1 do
    let g i = bloc.(i).(y) in
    let c = adapte_ifft g n in
    for x = 0 to n - 1 do
      res.(x).(y) <- c.(x)
    done
  done;
  res

let idct_opti (bloc : f_bloc) : unit =
  check_block bloc;
  let n = Array.length bloc in
  let temp = idct_colonne (idct_ligne bloc n) n in
  for i = 0 to n - 1 do
    for j = 0 to n - 1 do
      bloc.(i).(j) <- 2. /. Float.of_int n *. temp.(i).(j)
    done
  done
