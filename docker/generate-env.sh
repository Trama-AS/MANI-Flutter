#!/bin/sh
set -e

ENV_FILE="/usr/share/nginx/html/assets/.env"

# Si se configuran variables de entorno para Supabase o Gateway, regenera assets/.env
if [ -n "$SUPABASE_URL" ] || [ -n "$API_GATEWAY_URL" ]; then
    echo "[flutter-web] Configurando $ENV_FILE desde variables de entorno de runtime..."
    mkdir -p "$(dirname "$ENV_FILE")"
    cat <<EOF > "$ENV_FILE"
# Configuracion de Flutter Web generada en tiempo de ejecucion (SCRUM-1361)
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
API_GATEWAY_URL=${API_GATEWAY_URL}
TENANT_SLUG=${TENANT_SLUG:-acme-servicios}
EOF
fi
