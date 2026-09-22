#!/usr/bin/env bash
set -euo pipefail

echo "============================================================"
echo "  MANI — Sincronización de Base de Datos (QA -> DEV Local)"
echo "============================================================"

# 1. Verificar si el contenedor de PostgreSQL está corriendo
if [ -z "$(docker ps -q -f name=mani-postgres -f status=running)" ]; then
    echo -e "\n[1/4] Iniciando contenedor 'mani-postgres' con docker compose up -d..."
    docker compose up -d postgres
    sleep 3
else
    echo -e "\n[1/4] Contenedor 'mani-postgres' en ejecución."
fi

# 2. Aplicar migraciones de esquema pendientes
echo "[2/4] Verificando y aplicando migraciones de esquema..."
if [ -f "scripts/migrate-local.sh" ]; then
    bash scripts/migrate-local.sh
else
    echo "  [WARN] No se encontró scripts/migrate-local.sh, aplicando 001_initial_schema.sql..."
    docker exec -i mani-postgres psql -U postgres -d mani_db -v ON_ERROR_STOP=1 < database/migrations/001_initial_schema.sql
fi

# 3. Validar existencia del seed de QA
SEED_FILE="supabase/seed/seed_qa_multitenant.sql"
if [ ! -f "$SEED_FILE" ]; then
    echo -e "\n[ERROR] No se encontró el archivo de seed de QA en '$SEED_FILE'."
    exit 1
fi

# 4. Aplicar el seed de QA
echo -e "\n[3/4] Aplicando seed oficial de QA ($SEED_FILE)..."
docker exec -i mani-postgres psql -U postgres -d mani_db -v ON_ERROR_STOP=1 < "$SEED_FILE"
echo "  [ÉXITO] Seed multi-tenant de QA aplicado correctamente."

# 5. Resumen final
echo -e "\n[4/4] Sincronización completada exitosamente!"
echo "------------------------------------------------------------"
echo "Estado en Docker local (mani-postgres:5432 / mani_db):"
echo "  * Tenant 1: acme-servicios     (UUID: 10000000-0000-4000-8000-000000000011)"
echo "  * Tenant 2: nova-mantenimiento (UUID: 10000000-0000-4000-8000-000000000021)"
echo "  * Zonas: Bogotá D.C., Chapinero, Suba"
echo "  * Usuarios: admin.t1@qa.mani.test, cliente.t1@qa.mani.test, etc."
echo "  * Gestor Web: http://localhost:8088 (Adminer)"
echo "------------------------------------------------------------"
