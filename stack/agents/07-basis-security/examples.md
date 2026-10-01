# 🛡️ AGENTE 04 — Ejemplos de Uso

## Ejemplo 1: Diseño de Roles para Proceso Procure-to-Pay

**Prompt de entrada:**

```text
Diseña los roles SAP para el proceso Procure-to-Pay (P2P) en S/4HANA.
Perfiles de usuario: Solicitante, Comprador, Aprobador de OC, Jefe de Almacén, Contabilidad Proveedores.
Módulos: MM + FI + WM.
Restricciones: el Comprador solo ve su organización de compras (1000 o 2000).
Evitar conflictos SoD entre crear OC y aprobar OC.
```

**Output esperado del agente:**

- 5 roles derivados con estructura:
  - `ZMM_SOLICITANTE` (ME51N, ME52N — sin autorizar ni liberar)
  - `ZMM_COMPRADOR_1000` y `ZMM_COMPRADOR_2000` (ME21N, ME22N, ME2N — org compras derivada)
  - `ZMM_APROBADOR_OC` (ME29N, ME28 — solo liberar, sin crear)
  - `ZWM_JEFE_ALMACEN` (MIGO, LT0A, LS24 — movimientos de almacén)
  - `ZFI_CUENTAS_PAGAR` (MIRO, MR8M, FB60 — solo FI)
- Análisis SoD: conflicto detectado ME21N + ME29N → roles separados obligatorio
- Objetos de autorización por rol: M_BEST_BSA, M_BEST_EKG, M_BEST_EKO, F_BKPF_BUK
- Configuración PFCG: rol maestro + roles derivados por org de compras
- Proceso de alta de usuarios: SE solicitud → aprobación → SU01 asignación

---

## Ejemplo 2: Estrategia de Transportes para Proyecto Agile

**Prompt de entrada:**

```text
Define la estrategia de transportes para un proyecto S/4HANA con metodología Agile.
Equipo: 8 desarrolladores ABAP + 2 Basis.
Landscape: DEV → QAS → PRD.
Sprints de 2 semanas.
Herramienta: gCTS + STMS.
El cliente pide freeze de transportes los viernes a las 18h.
```

**Output esperado del agente:**

- Diagrama del landscape con carriles por equipo (lane ABAP, lane Basis, lane FI, lane SD)
- Reglas de transporte:
  - Feature branch por historia de usuario (git branch en gCTS)
  - Lunes-Jueves: imports a QAS abiertos (previa validación ATC)
  - Viernes 18h → Freeze QAS/PRD hasta el lunes
  - Release a PRD: ventana domingo 22h o lunes 6h
  - Hotfix: proceso de emergencia documentado (max 2h, doble aprobación)
- Checklist pre-import a PRD: ATC sin errores, unit tests verdes, UAT sign-off, backup confirmado
- Calendario de releases: 1 release por sprint (semana 2, jueves 20h → viernes QAS, lunes PRD)
- Manejo de conflictos: resolución en DEV, nunca en QAS/PRD
- Roles y responsabilidades: Basis owner del pipeline, Lead Dev aprueba imports a QAS

---

## Ejemplo 3: Análisis de SoD y Remediación en GRC

**Prompt de entrada:**

```text
Tenemos una auditoría interna que detectó 15 usuarios con conflicto SoD:
pueden crear proveedores (XK01) Y aprobar pagos (F110).
El sistema es SAP S/4HANA con SAP GRC Access Control.
Necesito un plan de remediación y controles compensatorios.
```

**Output esperado del agente:**

- Matriz SoD documentada: "Crear Proveedor" (XK01, FK01, MK01) vs "Ejecutar Pago" (F110, F-53)
- Análisis de riesgo: Alto — permite fraude de proveedor ficticio + desvío de fondos
- Plan de remediación en 3 fases:
  1. Inmediata (1 semana): revocar F110 a los 15 usuarios, asignar a rol dedicado ZFI_TESORERIA
  2. Corto plazo (1 mes): crear rol segregado ZMM_PROVEEDOR_MASTER sin acceso FI
  3. Largo plazo (3 meses): configurar SAP GRC Access Control con regla de riesgo R_AP_001
- Controles compensatorios mientras se remedian:
  - Monitor semanal en GRC de transacciones de ambos tipos por mismo usuario
  - Aprobación doble para pagos > $50,000 USD
  - Reporte ejecutivo mensual al CFO de excepciones activas
- Configuración GRC: Risk ID, Function definitions, Mitigation Control, Periodic review

---

## Casos de Uso Frecuentes

- Diseño de roles para go-live de nuevos módulos (SD, FI, MM, PP)
- Auditoría de usuarios con SAP_ALL o acceso excesivo
- Configuración de Cloud Connector para conectar on-premise con SAP BTP
- Estrategia de system copy (refresh de QAS desde PRD)
- Monitoreo de performance: análisis de work processes SM50/SM66, jobs SM37
