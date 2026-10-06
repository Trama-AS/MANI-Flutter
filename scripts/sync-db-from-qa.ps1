<#
.SYNOPSIS
    Sincroniza la base de datos local de Docker con el estado multi-tenant oficial de QA para MANI.
.DESCRIPTION
    1. Asegura que el contenedor `mani-postgres` esté corriendo.
    2. Aplica las migraciones de esquema base (`database/migrations/*.sql`).
    3. Ejecuta el seed oficial de QA (`supabase/seed/seed_qa_multitenant.sql`), dejando
       los 2 tenants (`acme-servicios`, `nova-mantenimiento`), las 3 zonas (`Bogotá`,
       `Chapinero`, `Suba`) y los 6 usuarios de prueba con sus roles idénticos a QA.
#>

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  MANI — Sincronización de Base de Datos (QA -> DEV Local)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Verificar si el contenedor de PostgreSQL está corriendo
$containerRunning = docker ps --filter "name=mani-postgres" --filter "status=running" -q
if (-not $containerRunning) {
    Write-Host "`n[1/4] Iniciando contenedor 'mani-postgres' con docker compose up -d..." -ForegroundColor Yellow
    docker compose up -d postgres
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[1/4] Contenedor 'mani-postgres' en ejecución." -ForegroundColor Green
}

# 2. Aplicar migraciones de esquema pendientes
Write-Host "[2/4] Verificando y aplicando migraciones de esquema..." -ForegroundColor Cyan
if (Test-Path "scripts/migrate-local.ps1") {
    & powershell -ExecutionPolicy Bypass -File "scripts/migrate-local.ps1"
} else {
    Write-Host "  [WARN] No se encontró scripts/migrate-local.ps1, aplicando 001_initial_schema.sql..." -ForegroundColor Yellow
    Get-Content -Path "database/migrations/001_initial_schema.sql" -Raw | docker exec -i mani-postgres psql -U postgres -d mani_db -v ON_ERROR_STOP=1
}

# 3. Validar existencia del seed de QA
$seedFile = "supabase/seed/seed_qa_multitenant.sql"
if (-not (Test-Path $seedFile)) {
    Write-Host "`n[ERROR] No se encontró el archivo de seed de QA en '$seedFile'." -ForegroundColor Red
    exit 1
}

# 4. Aplicar el seed de QA
Write-Host "`n[3/4] Aplicando seed oficial de QA ($seedFile)..." -ForegroundColor Cyan
Get-Content -Path $seedFile -Raw | docker exec -i mani-postgres psql -U postgres -d mani_db -v ON_ERROR_STOP=1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [ÉXITO] Seed multi-tenant de QA aplicado correctamente." -ForegroundColor Green
} else {
    Write-Host "  [ERROR] Falló la ejecución del seed de QA." -ForegroundColor Red
    exit 1
}

# 5. Resumen final
Write-Host "`n[4/4] Sincronización completada exitosamente!" -ForegroundColor Green
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Estado en Docker local (mani-postgres:5432 / mani_db):"
Write-Host "  * Tenant 1: acme-servicios     (UUID: 10000000-0000-4000-8000-000000000011)"
Write-Host "  * Tenant 2: nova-mantenimiento (UUID: 10000000-0000-4000-8000-000000000021)"
Write-Host "  * Zonas: Bogotá D.C., Chapinero, Suba"
Write-Host "  * Usuarios: admin.t1@qa.mani.test, cliente.t1@qa.mani.test, etc."
Write-Host "  * Gestor Web: http://localhost:8088 (Adminer)"
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
