#!/usr/bin/env bash
# Devuelve la solicitud de la PoC a 'pending' entre corridas (SCRUM-962).
# Usa la API con un JWT de aliado, no la service key: mismo camino que el harness.
set -euo pipefail
SOL="a0000000-0000-4000-8000-900000000001"
TOKEN=$(python3 -c "import json;print(json.load(open('$(dirname "$0")/tokens.json'))[0])")
curl -s -X PATCH "$SUPABASE_URL/rest/v1/solicitud?id=eq.$SOL" \
  -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -H "Prefer: return=representation" \
  -d '{"estado":"pending","aliado_id":null}' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print("reset ->", d[0]["estado"], d[0]["aliado_id"]) if d else print("FALLO:", d)'
