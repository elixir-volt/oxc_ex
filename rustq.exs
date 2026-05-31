import RustQ.Config

rust_items "native/oxc_ex_nif/src/generated_term_helpers.rs",
  items: RustQ.Rustler.term_helpers(type_key: "a::r#type()")

rust_items "native/oxc_ex_nif/src/generated_ast_decoders.rs",
  items: [
    RustQ.Rustler.term_decoder(:ProgramInput,
      fields: [
        body: [type: {:vec, "Term<'a>"}, key: "a::body()", required: true]
      ]
    ),
    RustQ.Rustler.term_decoder(:IfStatementInput,
      result: "R",
      fields: [
        test: [type: "Term<'a>", key: "a::test()", required: true],
        consequent: [type: "Term<'a>", key: "a::consequent()", required: true],
        alternate: [type: {:option, "Term<'a>"}, key: "a::alternate()"]
      ]
    )
  ]
