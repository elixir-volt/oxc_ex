use RustQ.Config

alias RustQ.{Rust, Rustler}

type_key = Rust.path([:a, "r#type"]) <> "()"

rust "native/oxc_ex_nif/src/generated_term_helpers.rs" do
  Rustler.term_helpers(type_key: type_key)
end

rust "native/oxc_ex_nif/src/generated_ast_decoders.rs" do
  Rustler.term_decoder(:ProgramInput,
    fields: [
      body: [type: {:vec, "Term<'a>"}, key: "a::body()", required: true]
    ]
  )

  Rustler.term_decoder(:IfStatementInput,
    result: "R",
    fields: [
      test: [type: "Term<'a>", key: "a::test()", required: true],
      consequent: [type: "Term<'a>", key: "a::consequent()", required: true],
      alternate: [type: {:option, "Term<'a>"}, key: "a::alternate()"]
    ]
  )
end
