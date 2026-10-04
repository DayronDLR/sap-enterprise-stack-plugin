# 🚀 AGENTE 08 — Ejemplos de Uso

## Ejemplo 1: Pipeline CI/CD con GitHub Actions para ABAP en S/4HANA

**Prompt de entrada:**

```text
Diseña un pipeline CI/CD completo con GitHub Actions para nuestro equipo ABAP en S/4HANA On-Premise.
Tenemos gCTS configurado. El pipeline debe: verificar ATC, correr unit tests, desplegar a DEV automático
y a QAS con aprobación manual (solo Basis puede aprobar).
Rama principal: main. Feature branches: feature/ZXXX-descripción.
```

**Output esperado del agente:**

```yaml
# .github/workflows/sap-abap-pipeline.yml
name: SAP ABAP CI/CD

on:
  push:
    branches: [ 'feature/**', 'main' ]
  pull_request:
    branches: [ main ]

jobs:
  atc-check:
    name: ATC Code Quality Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run ATC via abap-actions
        uses: SAP/gcts-actions/atc-check@v1
        with:
          host: ${{ secrets.SAP_HOST }}
          client: ${{ secrets.SAP_CLIENT }}
          username: ${{ secrets.SAP_USER }}
          password: ${{ secrets.SAP_PASS }}
          abap-package: Z_MY_PACKAGE
          fail-on-warnings: false

  unit-tests:
    name: ABAP Unit Tests
    needs: atc-check
    runs-on: ubuntu-latest
    steps:
      - name: Execute ABAP Unit Tests
        uses: SAP/gcts-actions/run-unit-tests@v1
        with:
          host: ${{ secrets.SAP_HOST }}
          package: Z_MY_PACKAGE

  deploy-dev:
    name: Deploy to DEV
    needs: unit-tests
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Push to DEV via gCTS
        uses: SAP/gcts-actions/deploy@v1
        with:
          host: ${{ secrets.SAP_DEV_HOST }}
          repo: Z_MY_REPO
          branch: main

  deploy-qas:
    name: Deploy to QAS (Manual Approval)
    needs: deploy-dev
    runs-on: ubuntu-latest
    environment:
      name: qas
      # Reviewers configurados en GitHub: solo equipo Basis
    steps:
      - name: Import Transport to QAS
        uses: SAP/gcts-actions/deploy@v1
        with:
          host: ${{ secrets.SAP_QAS_HOST }}
          repo: Z_MY_REPO
          branch: main
```

- Configuración de `environment: qas` en GitHub con required reviewers (equipo Basis)
- Secrets necesarios: SAP_HOST, SAP_CLIENT, SAP_USER, SAP_PASS para DEV y QAS
- Branch protection rules para `main`: require PR, require status checks, no direct push
- ATC Profile recomendado: Clean ABAP, Security, S/4HANA compatibility

---

## Ejemplo 2: Setup gCTS en S/4HANA + Estrategia Gitflow

**Prompt de entrada:**

```text
Guíame para configurar gCTS en nuestro S/4HANA 2022 y establecer la estrategia Gitflow.
Repositorio: Azure Repos (https://dev.azure.com/mycompany/SAP/_git/abap-repo).
Paquete a versionar: ZVENTAS (incluye subpaquetes ZSD_CUSTOM, ZFI_CUSTOM).
Equipo: 4 desarrolladores, 1 Basis.
```

**Output esperado del agente:**

- Guía paso a paso gCTS:
  1. Verificar prerequisito: nota SAP 2478813 aplicada
  2. Activar gCTS via `/n/GCTS/ADMIN` en SAP
  3. Crear repositorio remoto en Azure Repos (repo vacío, no inicializar)
  4. Configurar Remote Repository en `/GCTS/REPO_CONFIG`:
     - URL: `https://dev.azure.com/mycompany/SAP/_git/abap-repo`
     - Auth: Personal Access Token (PAT) de Azure DevOps
     - Branch: `main`
  5. Clonar repositorio en DEV: `/GCTS/REPO_CLONE`
  6. Asignar paquetes ZVENTAS, ZSD_CUSTOM, ZFI_CUSTOM al repositorio
  7. Commit inicial: push del estado actual a rama `main`

- Estrategia Gitflow definida:

```text
main ──────────────────────────────── (sincronizado con PRD)
  └── release/2025-Q1 ─────────────── (sincronizado con QAS)
        ├── feature/ZSD-001-bloqueo-credito  (desarrollador 1)
        ├── feature/ZFI-002-cierre-mes       (desarrollador 2)
        └── hotfix/ZSD-BUG-001              (crítico, va directo a main)
```

- Proceso diario del desarrollador:
  1. `git checkout -b feature/ZSD-XXX-descripcion` desde release actual
  2. Desarrollar en DEV, commits frecuentes con mensaje `[ZSD-XXX] Descripción`
  3. PR a rama release → revisión de Lead Dev → merge
  4. Pipeline auto-despliega a QAS → UAT → merge a main → PRD

---

## Ejemplo 3: Monitoreo Continuo con SAP Cloud ALM

**Prompt de entrada:**

```text
Configura monitoreo continuo de nuestra solución SAP S/4HANA + CPI usando SAP Cloud ALM.
Queremos alertas para: errores en iFlows, jobs batch fallidos, performance degradada (>5s respuesta),
usuarios con errores de autorización recurrentes.
```

**Output esperado del agente:**

- Arquitectura de monitoreo Cloud ALM:
  - CALM Integration: SolMan preparado → Cloud ALM tenant
  - Technical Monitoring → Integration Monitoring (CPI)
  - Real User Monitoring (RUM) para Fiori apps
  - Job Monitoring para batch críticos

- Configuración de alertas por categoría:
  1. **iFlow Errors**: Integration & Exception Monitoring → umbral: >0 errores críticos → alerta email a equipo CPI
  2. **Batch Jobs**: Job Monitoring → jobs RFEBKA00, MMPV, FAGLGVTR → fallo = alerta Slack inmediata
  3. **Performance**: Real User Monitoring → response time > 5s en apps Fiori → alerta dashboard
  4. **Authorization**: Security Monitoring → SU53 fallidos >5 por usuario en 1h → alerta a Basis

- Dashboard ejecutivo: 4 KPIs en pantalla principal (verde/amarillo/rojo)
- Runbook de respuesta a alertas: responsable, tiempo de respuesta, escalation path
- Revisión semanal: KPI meeting con métricas Cloud ALM exportadas

---

## Casos de Uso Frecuentes

- Migración de abapGit a gCTS para equipos que ya usan git pero no CI/CD
- Pipeline para SAP BTP / CAP applications con MTA build + cf deploy
- Automatización de quality gates: ATC obligatorio antes de cualquier import a QAS
- Integración CI/CD con JIRA: TR number en commit message → auto-update de ticket
- Alertas inteligentes: Cloud ALM + Slack/Teams integration para NOC SAP
