(* module Mcdsemantics *)
  open Types

  type location = abstract_tree ref
  type var_environment = (var_name, location) Assoclist.t
  type macro_environment = (macro_name, macro_location) Assoclist.t
  and function_spec = DummyFunc
                    | Func of (var_name list) * abstract_tree * abstract_tree * macro_environment * var_environment
  and macro_location = function_spec ref

  let report_error errmsg =
    print_string ("! [ERROR IN SEMANTICS] " ^ errmsg ^ ".") ;
    print_newline ()

  let report_detail dtlmsg =
    print_string ("  " ^ dtlmsg) ;
    print_newline ()

  (* for test *)
  let print_process stat =
    (* enable below in order to see the process of interpretation *)
  (*
    print_string (stat ^ " ") ;
  *)
    ()

  let replace_list : ((literal_name * letter, letter) Assoclist.t) ref = ref Assoclist.empty
  let prefix_list : ((literal_name, abstract_tree) Assoclist.t) ref = ref Assoclist.empty
  let postfix_list : ((literal_name, abstract_tree) Assoclist.t) ref = ref Assoclist.empty

  (* abstract_tree -> abstract_tree *)
  let rec semantics abstr =
    print_process "[BEGIN SEMANTICS]" ;
    let loc_deeper : macro_location = ref DummyFunc in
    let loc_break : macro_location = ref DummyFunc in
    let loc_ifempty : macro_location = ref DummyFunc in
    let loc_ifsame : macro_location = ref DummyFunc in
    let loc_include : macro_location = ref DummyFunc in
    let menv_main : macro_environment ref = ref Assoclist.empty in
    let venv_main : var_environment ref = ref Assoclist.empty in
      menv_main := (Assoclist.add "\\deeper" loc_deeper !menv_main) ;
      menv_main := (Assoclist.add "\\break" loc_break !menv_main) ;
      menv_main := (Assoclist.add "\\ifempty" loc_ifempty !menv_main) ;
      menv_main := (Assoclist.add "\\ifsame" loc_ifsame !menv_main) ;
      menv_main := (Assoclist.add "\\include" loc_include !menv_main) ;
      loc_deeper := Func(["~content"],
                      AbsBlock(DeeperIndent(
                        AbsBlock(BreakAndIndent,
                            ContentOf("~content"))), BreakAndIndent),
                      EmptyAbsBlock, !menv_main, !venv_main) ;
      loc_break := Func([], BreakAndIndent, EmptyAbsBlock, !menv_main, !venv_main) ;
      loc_ifempty := Func(["~subj"; "~tru"; "~fls"],
                        PrimitiveIfEmpty(ContentOf("~subj"), ContentOf("~tru"), ContentOf("~fls")),
                        EmptyAbsBlock, !menv_main, !venv_main
                      ) ;
      loc_ifsame := Func(["~subj1"; "~subj2"; "~tru"; "~fls"],
                        PrimitiveIfSame(ContentOf("~subj1"), ContentOf("~subj2"), ContentOf("~tru"), ContentOf("~fls")),
                        EmptyAbsBlock, !menv_main, !venv_main
                      ) ;
      loc_include := Func(["~filename"],
                        PrimitiveInclude(ContentOf("~filename")),
                        EmptyAbsBlock, !menv_main, !venv_main
                      ) ;
      interpret menv_main venv_main abstr

  (* (macro_environment ref) -> int -> (var_environment ref) -> abstract_tree -> abstract_tree *)
  and interpret menv venv abstr =

    match abstr with

    | PrimitiveIfEmpty(abstr_subj, abstr_tru, abstr_fls) -> (
          let value_subj = interpret menv venv abstr_subj in
            match value_subj with
            | EmptyAbsBlock -> interpret menv venv abstr_tru
            | _ -> interpret menv venv abstr_fls
        )

    | PrimitiveIfSame(abstr_subj1, abstr_subj2, abstr_tru, abstr_fls) -> (
    	    print_process "$PrimitiveIfSame" ;
    	    let str_subj1 = (
    	      try Mcdout.mcdout (interpret menv venv abstr_subj1) with
    	      | IllegalOut -> ( report_error "illegal argument of \\ifsame" ; "" )
    	    ) in
    	    let str_subj2 = (
    	      try Mcdout.mcdout (interpret menv venv abstr_subj2) with
    	      | IllegalOut -> ( report_error "illegal argument of \\ifsame" ; "" )
    	    ) in (
    	      if (compare str_subj1 str_subj2) == 0 then (
    	        print_process ("$true [" ^ str_subj1 ^ "]") ;
    	        interpret menv venv abstr_tru
    	      ) else (
    	        print_process ("$false [" ^ str_subj1 ^ "][" ^ str_subj2 ^ "]") ;
    	        interpret menv venv abstr_fls
    	      )
    	    )
        )

    | PrimitiveInclude(abstr_file_name) -> (
          print_process "$PrimitiveInclude" ;
          let str_file_name =
            try Mcdout.mcdout (interpret menv venv abstr_file_name) with
            | IllegalOut -> ( report_error "illegal argument of \\include" ; "" )
          in (
            report_detail ("Included '" ^ str_file_name ^ "'.") ;
            let str_content =
              try Files.string_of_file_in str_file_name with
              | Sys_error(s) -> ( report_error ("System error at \\include - " ^ s) ; "" )
            in
            let lexed_content = Mcdlexer.mcdlex str_content in
            let parsed_content = Mcdparser.mcdparser lexed_content in
            let absed_content = Mcdabs.concrete_to_abstract parsed_content in
              interpret menv venv absed_content
          )
        )

    | DeeperIndent(abstr) -> (
          print_process "$DeeperIndent(" ;
          let res = interpret menv venv abstr in
            print_process ")" ; DeeperIndent(res)
        )

    | BreakAndIndent -> (
          print_process ("$BreakAndIndent") ;
          BreakAndIndent
        )

    | EmptyAbsBlock -> (
          print_process "$EmptyAbsBlock" ;
          EmptyAbsBlock
        )

    | AbsBlock(abstr_head, abstr_tail) -> (
          let value_head = interpret menv venv abstr_head in
          let value_tail = interpret menv venv abstr_tail in
            match value_head with
              EmptyAbsBlock -> value_tail
            | _ -> (
                  match value_tail with
                    EmptyAbsBlock -> value_head
                  | _ -> AbsBlock(value_head, value_tail)
                )
        )

    | Output(c) -> (
          print_process ("$Output: " ^ c) ;
          Output(c)
        )

    | ContentOf(v) -> (
          print_process ("$ContentOf: " ^ v) ;
          try
        (*   interpret menv venv !(Assoclist.get_value (!venv) v) *)
            !(Assoclist.get_value (!venv) v)
          with
            ValueNotFound
              -> ( report_error ("undefined variable '" ^ v ^ "'") ; Invalid )
        )

    | Separated(abstr_former, abstr_latter) -> (
          print_process "$Separated" ;
          let value_former = interpret menv venv abstr_former in
          let value_latter = interpret menv venv abstr_latter in
            Separated(value_former, value_latter)
        )

    | Pop(u, v, abstr_rawlist, abstr_content) -> (
          let value_rawlist = interpret menv venv abstr_rawlist in
            match value_rawlist with
            | EmptyAbsBlock -> (
                  print_process "$Pop (Empty)" ;
                  EmptyAbsBlock
                )
            | _ -> (
                  match pop_from_separated_tree value_rawlist UnderConstruction with
                    (value_former, value_latter) -> (
                        print_process "Pop (Content)" ;
                        let loc_former : location = ref value_former in
                        let loc_latter : location = ref value_latter in
                        let venv_content = ref (Assoclist.add v loc_latter (Assoclist.add u loc_former !venv)) in
                          interpret menv venv_content abstr_content
                      )
                )
        )

    | PopChar(u, v, abstr_raw, abstr_content) -> (
          let str_raw =
            try Mcdout.mcdout (interpret menv venv abstr_raw) with
            | IllegalOut -> ( report_error "illegal argument of \\pop-char" ; "" )
          in
            match str_raw with
            | "" -> (
                  print_process "$PopChar (Empty)" ;
                  EmptyAbsBlock
                )
            | _ -> (
                  print_process "$PopChar (Content)" ;
                  let value_former = Output(String.sub str_raw 0 1) in
                  let value_latter = Output(String.sub str_raw 1 ((String.length str_raw) - 1)) in
                    let loc_former : location = ref value_former in
                    let loc_latter : location = ref value_latter in
                      let venv_content = ref (Assoclist.add v loc_latter (Assoclist.add u loc_former !venv)) in
                        interpret menv venv_content abstr_content
                )
        )

    | Macro(f, var_list, abstr_noid, abstr_id) -> (
          print_process "$Macro" ;
          let loc : macro_location = ref DummyFunc in (* dummy *)
          let menv_new = ref (Assoclist.add f loc !menv) in
          (* menv{ f|->loc } *)
          let value = Func(var_list, abstr_noid, abstr_id, !menv_new, !venv) in
            ( loc := value ; menv := !menv_new ; EmptyAbsBlock )
        )

    | Apply(f, NoID, param_list) -> (
          print_process "$Apply (NoID)" ;
          let spec_f =
            try !(Assoclist.get_value (!menv) f) with
            | ValueNotFound -> (
                  report_error ("undefined control sequence '" ^ f ^ "'") ;
                  DummyFunc
                )
          in
            match spec_f with
              Func(var_list, abstr_noid, abstr_id, cont_menv_f, cont_venv_f) -> (
                  match f with
                  (* write individually macros that need other strategy than call-by-value *)

                    "\\ifempty" -> (
                        match param_list with
                          [abstr_b; abstr_tru; abstr_fls]
                            -> interpret menv venv (PrimitiveIfEmpty(abstr_b, abstr_tru, abstr_fls))
                        | _ -> ( report_error ("wrong number of arguments for '\\ifempty'") ; Invalid )
                      )

                  | "\\ifsame" -> (
                        match param_list with
                          [abstr_sa; abstr_sb; abstr_tru; abstr_fls]
                            -> interpret menv venv (PrimitiveIfSame(abstr_sa, abstr_sb, abstr_tru, abstr_fls))
                        | _ -> ( report_error ("wrong number of arguments for '\\ifsame'") ; Invalid )
                      )

                  | _ -> (
                        let value_list = interpret_list menv venv param_list in
                        let loc_list : location list = ref_list value_list in
                        let menv_new = ref cont_menv_f in
                        try
                          let venv_new =
                            ref (Assoclist.add_list var_list loc_list cont_venv_f)
                          in
                            (* venv_f{ v_1|->l_1, ..., v_n|->l_n } *)
                            interpret menv venv_new abstr_noid
                              (* modify 'menv_new' to 'menv' in order to make f globally defined *)
                              (* modify 'menv' to 'menv_new' in order to make f locally defined *)
                        with
                          IncorrespondenceOfLength -> (
                              report_error ("wrong number of arguments for '" ^ f ^ "'") ;
                              Invalid
                            )
                      )
                )
            | DummyFunc -> Invalid
        )
    | Apply(f, RealID(i), param_list) -> (
          print_process "$Apply (ID)" ;
          let spec_f =
            try
              !(Assoclist.get_value (!menv) f)
            with
            | ValueNotFound -> (
                  report_error ("undefined control sequence '" ^ f ^ "'") ;
                  DummyFunc
                )
          in
            match spec_f with (* !(menv(f)) *)
            | Func(var_list, abstr_noid, abstr_id, cont_menv_f, cont_venv_f) -> (
                  let value_list = interpret_list menv venv param_list in
                  let loc_list : location list = ref_list value_list in
                  let loc_id : location = ref (id_to_abstract_tree i) in
                  let menv_new = ref cont_menv_f in
                  try
                    let venv_new =
                      ref (Assoclist.add "@id" loc_id (Assoclist.add_list var_list loc_list cont_venv_f))
                    in
                    (* venv_f{ v_1|->l_1, ..., v_n|->l_n, @id|->loc_id } *)
                      interpret menv venv_new abstr_id
                        (* modify 'menv_new' to 'menv' in order to make f globally defined *)
                        (* modify 'menv' to 'menv_new' in order to make f locally defined *)
                  with
                    IncorrespondenceOfLength -> (
                        report_error ("wrong number of arguments for '" ^ f ^ "'") ;
                        Invalid
                      )
                )
            | DummyFunc -> (
                report_error "illegal Apply of DummyFunc" ;
                Invalid
              )
        )

    | _ -> Invalid

  (* macro_environment -> var_environment -> (abstract_tree list) -> (abstract_tree list) *)
  and interpret_list menv venv abstr_list =
    match abstr_list with
    | [] -> []
    | abstr_head :: abstr_tail -> (
          let intrprtd_head = interpret menv venv abstr_head in
          let intrprtd_tail = interpret_list menv venv abstr_tail in
            intrprtd_head :: intrprtd_tail
        )

  (* abstract_tree list -> location list *)
  and ref_list value_list =
    match value_list with
    | [] -> []
    | value_head :: value_tail -> (ref value_head) :: (ref_list value_tail)

  and id_to_abstract_tree id = Output((String.sub id 1 ((String.length id) - 1)))
    (* eliminate '#' *)

  (* abstract_tree -> abstract_tree -> (abstract_tree * abstract_tree) *)
  and pop_from_separated_tree abstr_in abstr_constr =
    match abstr_in with
    | Separated(abstr_former, abstr_latter) -> (
          match abstr_former with
          | Separated(a, b) -> (
              pop_from_separated_tree abstr_former (compensate abstr_constr (Separated(UnderConstruction, abstr_latter)))
            )
          | _ -> (abstr_former, compensate abstr_constr abstr_latter)
        )
    | _ -> (abstr_in, EmptyAbsBlock)

  (* abstract_tree -> abstract_tree -> abstract_tree *)
  and compensate abstr_under_constr abstr_cmpnstd =
    match abstr_under_constr with
    | Separated(abstr_former, abstr_latter)
        -> Separated((compensate abstr_former abstr_cmpnstd), (compensate abstr_latter abstr_cmpnstd))
    | UnderConstruction -> abstr_cmpnstd
    | abstr_other -> abstr_other

  and make_literal_legitimate lb abstr =
    match abstr with
    | AbsBlock(abstr_former, abstr_latter) -> (
          AbsBlock(make_literal_legitimate lb abstr_former, make_literal_legitimate lb abstr_latter)
        )
    | OutputOfLiteral(c) ->
        let value_after = (
          try Assoclist.get_value !replace_list (lb, c) with
            ValueNotFound -> c
        ) in
          Output(value_after)

    | _ -> (
        report_error "illegal token in literal block" ;
        Invalid
      )