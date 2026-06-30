#!/bin/bash
# agent-reinforcement.sh
# UserPromptSubmit hook: detecta agente SAP activo y refuerza su contexto por turno
# Previene drift de contexto en sesiones largas (+50 turnos)

FLAG_FILE="${CLAUDE_PROJECT_DIR:-.}/tmp/.active-sap-agent"
mkdir -p "$(dirname "$FLAG_FILE")"

INPUT=$(cat)

# Extraer el prompt del usuario (soporta clave "prompt" o "message")
PROMPT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print((d.get('prompt') or d.get('message') or '').strip())
except:
    print('')
" 2>/dev/null)

# Detectar slash commands SAP y actualizar agente activo
DETECTED_AGENT=""
case "$PROMPT" in
    /sap-abap*)       DETECTED_AGENT="sap-abap" ;;
    /sap-cap*)        DETECTED_AGENT="sap-cap" ;;
    /sap-fiori*)      DETECTED_AGENT="sap-fiori" ;;
    /sap-hana*)       DETECTED_AGENT="sap-hana" ;;
    /sap-integration*) DETECTED_AGENT="sap-integration" ;;
    /sap-basis*)      DETECTED_AGENT="sap-basis" ;;
    /sap-req*)        DETECTED_AGENT="sap-req" ;;
    /sap-qa*)         DETECTED_AGENT="sap-qa" ;;
    /sap-doc*)        DETECTED_AGENT="sap-doc" ;;
    /sap-migration*)  DETECTED_AGENT="sap-migration" ;;
    /sap-devops*)     DETECTED_AGENT="sap-devops" ;;
    /sap-techlead*)   DETECTED_AGENT="sap-techlead" ;;
esac

if [ -n "$DETECTED_AGENT" ]; then
    printf '%s' "$DETECTED_AGENT" > "$FLAG_FILE"
    ACTIVE_AGENT="$DETECTED_AGENT"
elif [ -f "$FLAG_FILE" ]; then
    ACTIVE_AGENT=$(cat "$FLAG_FILE" 2>/dev/null)
fi

# Sin agente activo: no emitir nada
[ -z "$ACTIVE_AGENT" ] && exit 0

# Refuerzo por agente (conciso — máximo 2 reglas críticas)
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
