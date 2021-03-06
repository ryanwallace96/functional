open WorldObject
open WorldObjectI
open Movable
open Hive

(* ### Part 3 Actions ### *)
let pollen_theft_amount = 1000

(* ### Part 4 Aging ### *)
let bear_starting_life = 20

(* ### Part 2 Movement ### *)
let bear_inverse_speed = Some 10

class bear p (hive : hive_i) (home : world_object_i) : movable_t =
object (self)
  inherit movable p bear_inverse_speed as super

  (******************************)
  (***** Instance Variables *****)
  (******************************)

  (* ### Part 3 Actions ### *)
  val mutable stolen_honey = 0

  (* ### TODO: Part 6 Events ### *)
  val mutable life = bear_starting_life

  (***********************)
  (***** Initializer *****)
  (***********************)

  (* ### TODO: Part 3 Actions ### *)
  initializer 
    self#register_handler World.action_event (fun () -> self#do_action; 
      self#deposit_honey)

  (**************************)
  (***** Event Handlers *****)
  (**************************)

  (* ### TODO: Part 6 Custom Events ### *)
  method private deposit_honey : unit = 
    let rec gen_list n = if n < 1 then [] else 1::(gen_list (n - 1)) in
      if self#get_pos = home#get_pos then
        (ignore (home#receive_pollen (gen_list stolen_honey)) ;
          stolen_honey <- 0 ;
      if hive#get_pollen < pollen_theft_amount / 2 then self#die)

  (* ### TODO: Part 3 Actions ### *)
  method private do_action : unit =
    if self#get_pos = hive#get_pos then begin
      let amt = hive#forfeit_honey pollen_theft_amount 
        (self :> WorldObjectI.world_object_i) in
      stolen_honey <- stolen_honey + amt
    end ;

  (********************************)
  (***** WorldObjectI Methods *****)
  (********************************)

  (* ### TODO: Part 1 Basic ### *)

  method get_name = "bear"

  method draw = super#draw_circle (Graphics.rgb 170 130 110) 
    Graphics.black ((string_of_int) stolen_honey)

  method draw_z_axis = 3


  (* ### TODO: Part 6 Custom Events ### *)
  method receive_sting = 
    life <- life - 1;
    if life < 1 then self#die

  (***************************)
  (***** Movable Methods *****)
  (***************************)

  (* ### TODO: Part 2 Movement ### *)

  (* method next_direction = World.direction_from_to self#get_pos 
    hive#get_pos *)

  (* ### TODO: Part 6 Custom Events ### *)
  method next_direction = if stolen_honey = 0 then 
    World.direction_from_to self#get_pos hive#get_pos
    else World.direction_from_to self#get_pos home#get_pos

end
