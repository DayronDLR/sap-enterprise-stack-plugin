#!/bin/bash
# log-agent-activity.sh
# SubagentStop hook: loggea actividad detallada de cada agent
# Escribe JSONL en .claude/logs/

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/logs"
mkdir -p "$LOG_DIR"

INPUT=$(cat)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Extraer datos del input JSON y formatear log entry
AGENT_DATA=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    out = {
        'timestamp': '$TIMESTAMP',
        'session_id': d.get('session_id', 'unknown'),
        'agent_name': d.get('agent_name', d.get('tool_name', 'unknown')),
        'event': 'completed',
        'last_message': (d.get('last_assistant_message', '') or '')[:200]
    }
    print(json.dumps(out))
except:
    print(json.dumps({'timestamp': '$TIMESTAMP', 'event': 'completed', 'agent_name': 'unknown'}))
" 2>/dev/null)

LOG_FILE="$LOG_DIR/agents-$(date +%Y-%m-%d).jsonl"
echo "$AGENT_DATA" >> "$LOG_FILE"

exit 0
