#!/usr/bin/env bash
set -Eeuo pipefail

# ---------------------------------------------------------
# Configurações Padrão
# ---------------------------------------------------------
readonly DEFAULT_BASE_URL="https://resultados.tse.jus.br/oficial"
readonly -a CARGOS=(6 7 5 3 1) # Gov, Sen, Dep Fed, Dep Est, Pres

BASE_URL="${TSE_RESULTS_BASE_URL:-$DEFAULT_BASE_URL}"
YEAR="${TSE_RESULTS_YEAR:-2026}"
UF="${TSE_RESULTS_UF:-ma}"

# Requisito 1: Permite pesquisar todo o estado por predefinição
MUNICIPIO="${TSE_RESULTS_MUNICIPALITY:-}"
LIMIT="${TSE_RESULTS_LIMIT:-20}"

# Requisito 2: Separação de Turnos
TURNO="${TSE_RESULTS_TURNO:-1}"

FEDERAL_ELECTION_T1="${TSE_RESULTS_FEDERAL_ELECTION_T1:-6257}"
STATE_ELECTION_T1="${TSE_RESULTS_STATE_ELECTION_T1:-6259}"
FEDERAL_ELECTION_T2="${TSE_RESULTS_FEDERAL_ELECTION_T2:-6258}"
STATE_ELECTION_T2="${TSE_RESULTS_STATE_ELECTION_T2:-6260}"

COLOR_MODE="${TSE_RESULTS_COLOR:-auto}"

# ---------------------------------------------------------
# Funções Auxiliares
# ---------------------------------------------------------
die() { printf 'Erro: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null || die "Dependência não encontrada: curl"
command -v jq >/dev/null || die "Dependência não encontrada: jq"

# Validações melhoradas
[[ "$UF" =~ ^[[:alpha:]]{2}$ ]] || die "TSE_RESULTS_UF deve conter duas letras."
[[ -z "$MUNICIPIO" || "$MUNICIPIO" =~ ^[0-9]{5}$ ]] || die "TSE_RESULTS_MUNICIPALITY deve estar vazio (para o estado todo) ou conter cinco dígitos."
[[ "$YEAR" =~ ^[0-9]{4}$ ]] || die "TSE_RESULTS_YEAR deve conter quatro dígitos."
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || die "TSE_RESULTS_LIMIT deve ser um inteiro positivo."
[[ "$TURNO" =~ ^[12]$ ]] || die "TSE_RESULTS_TURNO deve ser 1 ou 2."
[[ "$COLOR_MODE" =~ ^(auto|always|never)$ ]] || die "TSE_RESULTS_COLOR deve ser auto, always ou never."

# Configuração dinâmica de eleição consoante o turno
if [[ "$TURNO" == "1" ]]; then
  FEDERAL_ELECTION="$FEDERAL_ELECTION_T1"
  STATE_ELECTION="$STATE_ELECTION_T1"
else
  FEDERAL_ELECTION="$FEDERAL_ELECTION_T2"
  STATE_ELECTION="$STATE_ELECTION_T2"
fi

UF="${UF,,}"
BASE_URL="${BASE_URL%/}"
LOCAL_PREFIX="${UF}${MUNICIPIO}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

use_color=false
if [[ "$COLOR_MODE" == always ]] || { [[ "$COLOR_MODE" == auto && -t 1 && "${TERM:-dumb}" != dumb ]] && [[ ! -v NO_COLOR ]]; }; then
  use_color=true
fi

print_rule() {
  local name_width="$1" number_width="$2" votes_width="$3"
  printf '+-%*s-+-%*s-+-%*s-+\n' "$name_width" '' "$number_width" '' "$votes_width" '' | tr ' ' '-'
}

print_table() {
  local -n table_rows="$1"
  local name_width=${#name_header} number_width=${#number_header} votes_width=${#votes_header}
  local row name number votes status display_name

  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes status <<<"$row"
    display_name="$name"
    # Requisito 3: Identifica claramente os eleitos
    [[ "$status" =~ ^Eleito ]] && display_name="$name (ELEITO)"
    
    (( ${#display_name} > name_width )) && name_width=${#display_name}
    (( ${#number} > number_width )) && number_width=${#number}
    (( ${#votes} > votes_width )) && votes_width=${#votes}
  done

  print_rule "$name_width" "$number_width" "$votes_width"
  printf '| %-*s | %*s | %*s |\n' "$name_width" "$name_header" "$number_width" "$number_header" "$votes_width" "$votes_header"
  print_rule "$name_width" "$number_width" "$votes_width"
  
  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes status <<<"$row"
    display_name="$name"
    
    local color_start=""
    local color_end=""
    
    if [[ "$status" =~ ^Eleito ]]; then
       display_name="$name (ELEITO)"
       $use_color && color_start="\033[1;33m" # Amarelo em negrito para eleitos
    elif $use_color; then
       color_start="\033[36m" # Ciano normal para restantes
    fi
    $use_color && color_end="\033[0m"

    if $use_color; then
      printf '| %b%-*s%b | %*s | \033[32m%*s\033[0m |\n' "$color_start" "$name_width" "$display_name" "$color_end" "$number_width" "$number" "$votes_width" "$votes"
    else
      printf '| %-*s | %*s | %*s |\n' "$name_width" "$display_name" "$number_width" "$number" "$votes_width" "$votes"
    fi
  done
  print_rule "$name_width" "$number_width" "$votes_width"
}

readonly name_header="NOME" number_header="NÚMERO" votes_header="VOTOS"

election_for_cargo() {
  case "$1" in
    1) printf '%s' "$FEDERAL_ELECTION" ;;
    3|5|6|7) printf '%s' "$STATE_ELECTION" ;;
    *) die "Cargo não suportado: $1" ;;
  esac
}

echo "A pesquisar dados - UF: ${UF^^} | Município: ${MUNICIPIO:-TODOS} | Turno: $TURNO"

for cargo in "${CARGOS[@]}"; do
  election="$(election_for_cargo "$cargo")"
  file="$tmp_dir/cargo-$cargo.json"
  printf -v cargo_padded '%04d' "$cargo"
  printf -v election_padded '%06d' "$election"
  url="$BASE_URL/ele$YEAR/$election/dados/$UF/${LOCAL_PREFIX}-c${cargo_padded}-e${election_padded}-u.json"

  # Requisito 4: Melhoria na tolerância a erros (ex: cargo sem 2º turno não deve quebrar o script todo)
  if ! curl --fail --silent --show-error --location \
    --retry 3 --retry-all-errors --connect-timeout 10 --max-time 30 \
    --output "$file" "$url"; then
    echo "Aviso: Sem dados para o cargo $cargo no $TURNOº turno (Pode não ter havido votação)." >&2
    continue
  fi
  
  if ! jq -e '.carg | type == "array"' "$file" >/dev/null 2>&1; then
    echo "Aviso: Resposta inválida para o cargo $cargo." >&2
    continue
  fi

  cargo_name="$(jq -r --arg cargo "$cargo" '.carg[] | select(.cd == $cargo) | .nmn' "$file" | head -n 1)"
  [[ -n "$cargo_name" ]] || { echo "Aviso: Cargo $cargo ausente." >&2; continue; }
  
  printf '\n%s (Cargo %s - %sº Turno)\n' "$cargo_name" "$cargo" "$TURNO"
  rows_file="$tmp_dir/cargo-$cargo.tsv"
  
  # Adicionada extração do status (.st) na query JQ
  jq -r --arg cargo "$cargo" --argjson limit "$LIMIT" '
    [
      .carg[] | select(.cd == $cargo)
      | .. | objects | .cand? // empty | .[]
      | select((.nmu // "") != "" and (.n // "") != "")
      | { nome: (.nmu | gsub("[[:cntrl:]]"; " ")), numero: .n, votos: ((.vap // "0") | tonumber), status: (.st // "") }
    ]
    | unique_by(.numero)
    | sort_by([-.votos, (.nome | ascii_downcase), .numero])
    | .[:$limit][]
    | [.nome, .numero, (.votos | tostring), .status] | @tsv
  ' "$file" >"$rows_file"
  
  mapfile -t rows <"$rows_file"
  if [[ ${#rows[@]} -gt 0 ]]; then
      print_table rows
  else
      echo "Nenhum candidato encontrado para exibição."
  fi
done