# General Recommendations

## Empirical Validation

Reasoning can only get you so far. It's best to test your assumptions early when you encounter a problem that you're unfamiliar with. Conduct experiments rather than relying purely on inductive reasoning.

## Narrow Changes

Make edits with intention and precision with a specific purpose in mind. Don't make "drive-by" fixes; changes should only be related to what you're actively working on. If you spot something you want to change, make a note of it and either change it later or report it to the user with your recommendations.

## Rules

- **NEVER** run `find /` unless you were explicitly told to do a system-wide search. Narrow your command scope when possible: you'll limit your blast radius, lower latency, and improve the quality of the results. Scanning the nix store will hurt you more than help.
