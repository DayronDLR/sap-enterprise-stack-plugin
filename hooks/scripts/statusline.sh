#!/bin/bash
# statusline.sh — barra de estado del stack SAP.
#
# Muestra, de un vistazo: agente SAP activo, modo (SES_MODE), rama git, y el
# consumo real de la ventana de contexto con una barra de color.
#
# El objetivo del ultimo bloque es que el consumo de contexto sea VISIBLE
# mientras se trabaja, no algo que se descubre cuando el stack compacta. Es la
# contraparte en vivo de `pnpm run token:audit`, que mira hacia atras.
#
# Claude Code pasa por stdin un JSON con, entre otros:
#   .model.display_name
#   .context_window.used_percentage
#   .context_window.total_input_tokens
#   .context_window.context_window_size
#   .cost.total_cost_usd
#   .workspace.current_dir

set -u
INPUT=$(cat)

field() {
    printf '%s' "$INPUT" | node -e '
let r="";process.stdin.on("data",d=>r+=d).on("end",()=>{
  try{const j=JSON.parse(r);
    const v=process.argv[1].split(".").reduce((a,k)=>(a==null?a:a[k]),j);
    process.stdout.write(v==null?"":String(v));
  }catch{process.stdout.write("")}
})' "$1" 2>/dev/null
}

MODEL=$(field model.display_name)
PCT=$(field context_window.used_percentage)
USED=$(field context_window.total_input_tokens)
SIZE=$(field context_window.context_window_size)
COST=$(field cost.total_cost_usd)

# Agente SAP activo (lo escribe agent-reinforcement.sh)
AGENT=""
FLAG="${CLAUDE_PROJECT_DIR:-.}/tmp/.active-sap-agent"
[[ -f "$FLAG" ]] && AGENT=$(cat "$FLAG" 2>/dev/null)

MODE="${SES_MODE:-full}"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "-")

# Barra de 10 segmentos, coloreada por umbral. Verde hasta 60%, amarillo hasta
# 82% (donde compacta este stack), rojo por encima.
PCT_INT=${PCT%%.*}; PCT_INT=${PCT_INT:-0}
[[ "$PCT_INT" =~ ^[0-9]+$ ]] || PCT_INT=0
FILLED=$(( PCT_INT / 10 )); [[ "$FILLED" -gt 10 ]] && FILLED=10
BAR=""
for ((i=0;i<10;i++)); do [[ $i -lt $FILLED ]] && BAR="${BAR}█" || BAR="${BAR}░"; done
if   [[ "$PCT_INT" -lt 60 ]]; then COL=$'\033[32m'
elif [[ "$PCT_INT" -lt 82 ]]; then COL=$'\033[33m'
else                               COL=$'\033[31m'; fi
RST=$'\033[0m'; DIM=$'\033[2m'

OUT=""
[[ -n "$AGENT" ]] && OUT="${OUT}⚙ ${AGENT}  "
[[ -n "$MODEL" ]] && OUT="${OUT}${DIM}${MODEL}${RST}  "
OUT="${OUT}${DIM}${MODE}${RST}  ${DIM}⑂ ${BRANCH}${RST}"

if [[ -n "$USED" && -n "$SIZE" && "$SIZE" != "0" ]]; then
    K=$(( USED / 1000 )); TOTK=$(( SIZE / 1000 ))
    OUT="${OUT}\n${COL}${BAR}${RST} ${PCT_INT}%  ${DIM}${K}k/${TOTK}k${RST}"
    [[ -n "$COST" ]] && OUT="${OUT}  ${DIM}\$$(printf '%.2f' "$COST" 2>/dev/null || echo "$COST")${RST}"
fi

printf '%b\n' "$OUT"
