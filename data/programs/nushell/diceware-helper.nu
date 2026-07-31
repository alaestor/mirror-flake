def pw [
  --words (-w): int  # Override word count (otherwise random 4..7).
  --caps (-c): int   # Override capitalized word count (otherwise random 0..n).
  --sep (-s): string # Override the separator (otherwise "_").
] {
  let word_count = ($words | default (random int 4..7))
  let base = (@DICEWARE@ -d _ -n $word_count --no-caps)
  let cap_count = (
    [($caps | default (random int 0..$word_count)), $word_count]
      | math min
  )

  let words = ($base | split row "_")
  let capitalized = (
    0..($word_count - 1)
      | each { |index| $index }
      | shuffle
      | first $cap_count
  )
  let result = (
    $words
      | enumerate
      | each { |row|
          match ($capitalized | any { |index| $index == $row.index }) {
            true => ($row.item | str uppercase),
            false => $row.item,
          }
        }
      | str join ($sep | default "_")
  )
  print $result
}
