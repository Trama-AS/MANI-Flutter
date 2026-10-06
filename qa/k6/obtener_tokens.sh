#!/usr/bin/env bash
# =====================================================================
# MANI — Cache de tokens para el harness de CFG-09
# =====================================================================
# Ticket: SCRUM-926 · Subtarea: SCRUM-962
#
# POR QUE EXISTE
#   Supabase Auth limita el endpoint de token a ~30 peticiones por 5
#   minutos por IP. Autenticar 50 aliados de corrido devuelve
#   429 over_request_rate_limit a mitad de camino y aborta la corrida.
#
#   Ademas conviene por metodo: el login no debe ocurrir dentro de la
#   ventana medida. Aqui se paga una vez y se reutiliza en las N corridas
#   mientras los JWT sigan vigentes (1 hora por defecto).
#
# USO
#   set -a; source .env; set +a
#   bash qa/k6/obtener_tokens.sh [N] [LOTE] [ESPERA_SEG]
#
# SALIDA
#   qa/k6/tokens.json — gitignoreado, son credenciales de sesion.
# =====================================================================
set -euo pipefail

N=${1:-50}
LOTE=${2:-25}
ESPERA=${3:-310}
SALIDA="$(dirname "$0")/tokens.json"

: "${SUPABASE_URL:?falta SUPABASE_URL}"
: "${SUPABASE_ANON_KEY:?falta SUPABASE_ANON_KEY}"

echo "[]" > "$SALIDA"
echo "Autenticando $N aliados en lotes de $LOTE (espera ${ESPERA}s entre lotes)..."

for i in $(seq 1 "$N"); do
  RESP=$(curl -s -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" \
    -d "{\"email\":\"aliado.poc.$i@poc.mani.test\",\"password\":\"QaSeed2026!\"}")

  TOKEN=$(printf '%s' "$RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null || true)

  if [ -z "$TOKEN" ]; then
    echo "FALLO en aliado $i: $(printf '%s' "$RESP" | head -c 200)"
    exit 1
  fi

  python3 - "$SALIDA" "$TOKEN" <<'PY'
import json, sys
ruta, token = sys.argv[1], sys.argv[2]
datos = json.load(open(ruta))
datos.append(token)
json.dump(datos, open(ruta, 'w'))
PY

  # Pausa entre lotes para no chocar con el limite de 30/5min por IP.
  if [ $((i % LOTE)) -eq 0 ] && [ "$i" -lt "$N" ]; then
    echo "  $i/$N listos — esperando ${ESPERA}s para el siguiente lote"
    sleep "$ESPERA"
  fi
done

echo "OK: $N tokens en $SALIDA"
