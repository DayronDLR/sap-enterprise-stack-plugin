#!/bin/bash
# agent-reinforcement.sh
# UserPromptSubmit hook: detecta el agente SAP activo y refuerza su contexto.
#
# Corre en CADA prompt, asi que cambiaron dos cosas respecto de la version previa:
#   1. Sin spawn de python3 — se extrae el prompt con matching de bash. Un
#      interprete por prompt es latencia pura para leer un campo.
#   2. Ya no emite el refuerzo en todos los turnos. Emite al cambiar de agente y
#      luego cada REINFORCE_EVERY turnos. El objetivo era frenar el drift en
#      sesiones largas; repetirlo en cada turno lo paga en cada request posterior
#      sin agregar señal.

set -u

# Cadencia segun SES_MODE (ver lib/dod-common.sh):
#   lite  -> sin refuerzo (un spike no necesita anti-drift)
#   full  -> cada 10 turnos
#   ultra -> cada 5, porque el drift en codigo que va a PRD cuesta mas caro
case "${SES_MODE:-full}" in
    lite)  exit 0 ;;
    ultra) DEFAULT_EVERY=5 ;;
    *)     DEFAULT_EVERY=10 ;;
esac
REINFORCE_EVERY="${REINFORCE_EVERY:-$DEFAULT_EVERY}"
TMP_DIR="${CLAUDE_PROJECT_DIR:-.}/tmp"
FLAG_FILE="${TMP_DIR}/.active-sap-agent"
# El contador va por sesion: dos sesiones de Claude sobre el mismo repo
# compartirian el archivo y se pisarian el conteo entre si.
SESSION_KEY=$(printf '%s' "${CLAUDE_SESSION_ID:-nosession}" | tr -c 'a-zA-Z0-9' '_')
TURN_FILE="${TMP_DIR}/.agent-turn-count-${SESSION_KEY}"
mkdir -p "$TMP_DIR" 2>/dev/null

INPUT=$(cat)

PROMPT=""
if [[ "$INPUT" =~ \"(prompt|message)\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    PROMPT="${BASH_REMATCH[2]}"
fi

DETECTED_AGENT=""
case "$PROMPT" in
    /sap-abap*)        DETECTED_AGENT="sap-abap" ;;
    /sap-cap*)         DETECTED_AGENT="sap-cap" ;;
    /sap-fiori*)       DETECTED_AGENT="sap-fiori" ;;
    /sap-hana*)        DETECTED_AGENT="sap-hana" ;;
    /sap-integration*) DETECTED_AGENT="sap-integration" ;;
    /sap-basis*)       DETECTED_AGENT="sap-basis" ;;
    /sap-req*)         DETECTED_AGENT="sap-req" ;;
    /sap-qa*)          DETECTED_AGENT="sap-qa" ;;
    /sap-doc*)         DETECTED_AGENT="sap-doc" ;;
    /sap-migration*)   DETECTED_AGENT="sap-migration" ;;
    /sap-devops*)      DETECTED_AGENT="sap-devops" ;;
    /sap-techlead*)    DETECTED_AGENT="sap-techlead" ;;
esac

PREVIOUS=""
[[ -f "$FLAG_FILE" ]] && PREVIOUS=$(cat "$FLAG_FILE" 2>/dev/null)

SWITCHED=0
if [[ -n "$DETECTED_AGENT" ]]; then
    [[ "$DETECTED_AGENT" != "$PREVIOUS" ]] && SWITCHED=1
    printf '%s' "$DETECTED_AGENT" > "$FLAG_FILE"
    ACTIVE_AGENT="$DETECTED_AGENT"
else
    ACTIVE_AGENT="$PREVIOUS"
fi

[ -z "$ACTIVE_AGENT" ] && exit 0

# Contador de turnos desde el ultimo refuerzo.
TURNS=0
[[ -f "$TURN_FILE" ]] && TURNS=$(cat "$TURN_FILE" 2>/dev/null || echo 0)
[[ "$TURNS" =~ ^[0-9]+$ ]] || TURNS=0
TURNS=$((TURNS + 1))

if [[ "$SWITCHED" = "0" ]] && [[ "$TURNS" -lt "$REINFORCE_EVERY" ]]; then
    printf '%s' "$TURNS" > "$TURN_FILE"
    exit 0
fi
printf '0' > "$TURN_FILE"

case "$ACTIVE_AGENT" in
    sap-abap)
        MSG="Agente activo: SAP ABAP Developer. Aplicar Clean Core (BAdIs, CDS, RAP — sin modificaciones estándar). Verificar con ATC + SyntaxCheck antes de activar." ;;
    sap-cap)
        MSG="Agente activo: BTP & CAP Developer. Consultar cds-mcp:search_docs antes de implementar. Scope: CAP Node.js, MTA, XSUAA, Cloud Foundry." ;;
    sap-fiori)
        MSG="Agente activo: Fiori/UI5 Developer. Metodología ECPIV obligatoria. Consultar ui5-mcp:get_api_reference. Ejecutar run_ui5_linter + run_manifest_validation. viewPath PROHIBIDO en manifest v2." ;;
    sap-hana)
        MSG="Agente activo: HANA Cloud Specialist. Optimizar SQLScript para column store. Verificar cardinalidades y proyecciones en Calculation Views." ;;
    sap-integration)
        MSG="Agente activo: Integration Architect. Documentar endpoints OData/API con contratos. Manejo de errores en todos los iFlows." ;;
    sap-basis)
        MSG="Agente activo: Basis & Security. Verificar SoD antes de asignar roles. Transportes requieren confirmación QAS → PRD." ;;
    sap-req)
        MSG="Agente activo: Requirements Analyst. Producir FS/blueprint con secciones AS-IS, TO-BE y gap analysis. Validar con stakeholder antes de continuar." ;;
    sap-qa)
        MSG="Agente activo: QA & Testing. Casos de prueba deben cubrir happy path + errores + edge cases. Go-live checklist obligatorio." ;;
    sap-doc)
        MSG="Agente activo: Documentation Architect. Formato cliente: Word-compatible markdown. Incluir diagramas de flujo y transacciones SAP relevantes." ;;
    sap-migration)
        MSG="Agente activo: Data Migration Lead. Mapeo de campos validado contra estructura destino. Scripts de rollback obligatorios antes de cualquier carga." ;;
    sap-devops)
        MSG="Agente activo: SAP DevOps Engineer. Pipeline: lint → test → build → deploy. gCTS para transportes, ATC en pre-push." ;;
    sap-techlead)
        MSG="Agente activo: Tech Lead Orquestador. Distribuir tareas con dependencias explícitas. Bloquear en ambigüedades antes de delegar." ;;
    *)
        MSG="Agente SAP activo: $ACTIVE_AGENT. Seguir principios Clean Core. Consultar MCPs disponibles antes de implementar." ;;
esac

echo "[SAP Stack] $MSG"

exit 0
