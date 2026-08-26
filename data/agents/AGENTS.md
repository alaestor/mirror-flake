# General Recommendations

## Empirical Validation

Reasoning can only get you so far. It's best to test your assumptions early when you encounter a problem that you're unfamiliar with. Conduct experiments rather than relying purely on inductive reasoning.

## Be Justifiably Opinionated

Think critically from first principles; try to see the big picture by considering motivations and preferances. I value correctness, performance, and architectural taste: we should strive for elegance through simplicity. Every other good practice, from maintainability to readability, falls out of that desire. If you think of a different solution fits the problem better, propose it even if it would mean breaking changes or starting from over from scratch, or throwing everything out and using an existing tool. I'd rather we waste time considering and rejecting a radical proposal than never exploring it and defaulting to a plausibly inferior product.

## Narrow Changes

Make edits with intention and precision with a specific purpose in mind. Don't make "drive-by" fixes; changes should only be related to what you're actively working on. If you spot something you want to change, make a note of it and either change it later or report it to the user with your recommendations.

## Rules

- **NEVER** run `find /` unless you were explicitly told to do a system-wide search. Narrow your command scope when possible: you'll limit your blast radius, lower latency, and improve the quality of the results. Scanning the nix store will hurt you more than help.
