{ mkMacro, ... }: mkMacro "grill-with-docs" "Interview and maintain the domain glossary and ADRs" ''

  ${builtins.readFile ../macro/grill.md}

  Once complete, use this shared understanding to synthesize domain documentation.

  ${builtins.readFile ../macro/domain-modeling.md}
''
