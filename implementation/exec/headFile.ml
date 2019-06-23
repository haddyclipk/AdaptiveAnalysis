open List
open Distribution
open Printf

let infile = ref (None : string option)
let outfile = ref (None : string option)
let rounds = ref 0.0
let cols = ref 0.0
let rows = ref 0.0 
let cdb = ref false

let argDefs = [
    "--createdb" , Arg.Unit (fun l -> cdb := true ), "create a new db";
    "-rw", Arg.Float (fun i -> rows := i) , "specify the rows of the database, -rw float"; 
    "-cl", Arg.Float (fun i -> cols := i) , "specify the cols of the database, -cl float"; 
    "-r", Arg.Float (fun i -> rounds := i) , "specify the rounds of the experiments, -r float"; 
    "-i", Arg.String (fun s -> infile := Some s ), "specify the input file name, -i string" ; 
      "-o", Arg.String (fun s -> outfile := Some s ), "specify the output file name, -o string" 
]
let delta = 0.0000001
let epsilon = 1.0

type row = float list
type database = row list
type query = row -> float
type mech = query -> database -> float
type result = float * float

let parseArgs () =  
        let oname = ref (None : string option) in 
        Arg.parse argDefs 
        (fun s -> 
                match !oname  with 
                      | Some (_) -> printf "%s" "specify just one output file name"  
                      | None  -> oname := Some (s); printf "%s" s ) "for output file" ;
             match !infile, !outfile  with
                   | Some i, Some o -> (i,o)
                   | _,_ -> printf "%s" "specify  your input file -i or output file -o , or colums -col float, rounds -r float"; ("","")

let dataset = [ [1.0;1.0;1.0;1.0] ; [1.0;1.0;1.0;1.0] ; [1.0;1.0;1.0;1.0] ; [1.0;1.0;1.0;1.0] ]  
  

let rec creat_db (col : float) (row : float)  =
  if row > 0.0
    then 
      let rec creat_row (col : float) = 
        if col > 0.0
        then 
          (float_of_int (Random.int 2)) :: creat_row (col -. 1.0)
        else
          []
      in (creat_row col) :: creat_db col (row -. 1.0)
    else
      []

let record_db db oc =
    List.map (fun row -> List.map (fun e ->fprintf oc "%d," e ) row; fprintf oc "\n" )  db ; close_out oc

let sub_row row =
  List.rev (List.tl (List.rev row) )

let rec read_db ic rows cols =
    if rows > 0.0
     then 
          let line = input_line ic in 
          let tmp_row =
           (String.split_on_char ',' line) in 
           (List.map (fun s -> float_of_string s) (sub_row tmp_row)) :: (read_db ic (rows-.1.0) cols)
    else
       [] 


let thresholdout_mech (q:query) db =
  let holdout_db = creat_db (float_of_int (List.length (hd db))) (float_of_int(List.length db)) in
    let threshold = 1.0 in
      let noise_rate = 1.0 in
        let budget = (List.length db) in
              let rec threshold_mech db holdout_db gamma =
                match (db, holdout_db) with
                  |([],[]) -> []
                  |(rw::t, holdout_rw::holdout_t) -> let eta = (sample_exp (4.0 *. noise_rate)) in
                    if ((q rw) -. (q holdout_rw)) > (threshold +. gamma +. eta)
                    then
                      ((q holdout_rw) +. (sample_exp noise_rate))::(threshold_mech t holdout_t (sample_exp 2.0 *. noise_rate))
                    else
                      (q rw)::(threshold_mech t holdout_t gamma)
                  | _ -> printf "This shouldn't happen\n";[]
                  in
                    let sm = List.fold_left 
                      (fun sum rw ->  
                          sum +. rw
                      ) 0.0 (threshold_mech db holdout_db (sample_exp (2.0 *. noise_rate)))
                    in 
                      (sm /.  float_of_int (List.length (hd db)))


(*let rec read_rows ic i j acc =
        if i < j then
         read_line ic (i+1) j (float_of_string (input_line ic)) :: acc
        else
         List.rev acc *)
       

let sum_q (db: float list list) = 
    List.fold_left ( fun a r -> a +.  (hd r)  ) 0.0 db  

let gauss_mech (q:query) db =  
  let result =
    let mean = 
      let sm =  List.fold_left 
          ( fun sum rw ->  
              sum +. (q rw)
          ) 0.0 db  
        in  
        sm /.  float_of_int (List.length db)
      in
        let mu = 2.0 *. log(1.25 /. delta) *. 2.0 *. 2.0 /. epsilon
        in 
          mean +. (sample_normal_boxmuller3 0.0 mu) 
  in 
  if result > 1.0 then 1.0 
  else  if result < -1.0 then -1.0 else result 

let nonoise_mech (q:query) db =  
    let mean = 
      let sm =  List.fold_left 
          ( fun sum rw ->  
              sum +.  (q rw)
          ) 0.0 db  
        in  
        sm /.  float_of_int (List.length db)
      in
    mean 

let dot (l1:float ) (l2: float) : float = l1 *. l2
  

let sign (y: float) : float = 
  if y > 0.0 then 1.0 else -1.0

let get (row:float list) (i:float) : float  =
  nth row (int_of_float i)


let mech (q:query) =  nonoise_mech q dataset
