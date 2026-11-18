# Diceware passphrases with a random word count and randomly uppercased words.
usage() {
  printf 'Usage: pw [-w|--words COUNT] [-c|--caps COUNT] [-s|--sep STRING]\n'
}
fail() {
  printf 'pw: %s\n' "$1" >&2
  exit 2
}
words=''
caps=''
words_set=false
caps_set=false
separator='_'
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -w|--words|-c|--caps|-s|--sep)
      [ "$#" -ge 2 ] || fail "missing value for $1"
      case "$1" in
        -w|--words) words=$2; words_set=true ;;
        -c|--caps) caps=$2; caps_set=true ;;
        -s|--sep) separator=$2 ;;
      esac
      shift 2
      ;;
    --words=*) words=${1#*=}; words_set=true; shift ;;
    --caps=*) caps=${1#*=}; caps_set=true; shift ;;
    --sep=*) separator=${1#*=}; shift ;;
    *) fail "unknown argument: $1" ;;
  esac
done

# Bound decimal inputs before using Bash arithmetic, including leading zeroes.
if "$words_set"; then
  [[ "$words" =~ ^[0-9]{1,9}$ ]] || fail 'words must be a positive integer'
  words=$((10#$words))
  [ "$words" -gt 0 ] || fail 'words must be a positive integer'
else
  words=$(shuf --random-source=/dev/urandom -i 4-7 -n 1)
fi
if "$caps_set"; then
  [[ "$caps" =~ ^[0-9]{1,9}$ ]] || fail 'caps must be a nonnegative integer'
  caps=$((10#$caps))
  if [ "$caps" -gt "$words" ]; then caps=$words; fi
else
  caps=$(shuf --random-source=/dev/urandom -i "0-$words" -n 1)
fi

base=$(diceware -d _ -n "$words" --no-caps)
IFS=_ read -r -a passphrase <<< "$base"
[ "${#passphrase[@]}" -eq "$words" ] || fail 'diceware returned an unexpected word count'
indices=$(shuf --random-source=/dev/urandom -i "0-$((words - 1))" -n "$caps")
for index in $indices; do
  passphrase[index]=${passphrase[index]^^}
done
printf '%s' "${passphrase[0]}"
for ((index = 1; index < words; index++)); do
  printf '%s%s' "$separator" "${passphrase[index]}"
done
printf '\n'
