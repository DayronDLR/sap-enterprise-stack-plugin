# 🧪 AGENTE 09 — Ejemplos de Uso

## Ejemplo 1: Casos de Prueba para Proceso de Liberación de OC

**Prompt de entrada:**

```text
Genera los casos de prueba para el siguiente Functional Spec:
El proceso de liberación de órdenes de compra en SAP MM tiene 2 niveles:
- Nivel 1: Comprador jefe aprueba OCs entre $5,000 y $50,000 (ME29N)
- Nivel 2: Gerente de compras aprueba OCs > $50,000 (ME29N)
- Notificación automática por email al aprobador al crear la OC
- OCs < $5,000 se autoliberan
Sistema: SAP S/4HANA 2023.
```

**Output esperado del agente:**

- 12 casos de prueba con formato estándar:
  - TC-MM-RELEASE-001: OC $4,999 → autoliberación (positivo)
  - TC-MM-RELEASE-002: OC $5,000 → requiere Nivel 1 (borde)
  - TC-MM-RELEASE-003: OC $25,000 → solo Nivel 1 (positivo)
  - TC-MM-RELEASE-004: OC $50,000 → requiere Nivel 1 (borde)
  - TC-MM-RELEASE-005: OC $50,001 → requiere Nivel 2 (borde)
  - TC-MM-RELEASE-006: OC $100,000 → Nivel 1 + Nivel 2 (positivo)
  - TC-MM-RELEASE-007: Usuario sin rol aprobador intenta liberar (negativo)
  - TC-MM-RELEASE-008: Email enviado al crear OC $10,000 (integración)
  - TC-MM-RELEASE-009: Rechazar OC desde ME29N (negativo workflow)
  - TC-MM-RELEASE-010: OC con 2 posiciones, monto combinado > $50,000 (borde)
  - TC-MM-RELEASE-011: Modificar OC ya liberada → requiere re-liberación (negativo)
  - TC-MM-RELEASE-012: Liberación en masa via ME28 (positivo)
- Datos de prueba sugeridos por caso
- Criterios de aceptación: tiempo de respuesta < 3s, email en < 2 min

---

## Ejemplo 2: Plan UAT para Go-Live Módulo FI

**Prompt de entrada:**

```text
Crea el plan UAT para el go-live de SAP FI en una empresa de manufactura.
Módulos: GL, AP, AR, AA (activos fijos).
Fecha go-live: 15 de marzo.
Usuarios clave: 5 contadores, 1 jefe de contabilidad, 1 tesorero.
Desarrollos custom: 2 reports, 1 BAdI de cierre.
Interfaces: integración bancaria HSBC para conciliación automática.
```

**Output esperado del agente:**

- Plan UAT completo con:
  - Objetivo: validar 100% de transacciones críticas FI antes del go-live
  - Alcance: GL (FB01, FB50, F-02), AP (MIRO, F-53, F110), AR (F-22, F-28), AA (AS91, ABSO, AFAB)
  - Equipo: 7 usuarios de negocio + 1 líder de pruebas SAP
  - Calendario 3 semanas:
    - Semana 1 (24 feb): setup datos, GL y AP básico
    - Semana 2 (3 mar): AR, AA, desarrollos custom
    - Semana 3 (10 mar): integración bancaria, cierre de período, regresión
  - Criterios de entrada: datos migrados en QAS, roles asignados, manuales disponibles
  - Criterios de salida: 0 defectos críticos, ≤3 defectos altos con workaround, sign-off gerente
  - Proceso de defectos: JIRA, severidad 1-4, SLA 4h/8h/2d/5d
  - Checklist: 45 ítems agrupados por área

---

## Ejemplo 3: Go-Live Checklist para Implementación S/4HANA

**Prompt de entrada:**

```text
Genera el Go-Live Checklist completo para:
Proyecto: Implementación S/4HANA FI + MM + SD
Desarrollos: 12 reports, 5 BAdIs, 3 interfaces CPI
Datos migrados: materiales (5,000), clientes (800), proveedores (300), saldos GL
Fecha go-live: primer día del mes fiscal (1 de abril)
Landscape: DEV → QAS → PRD
```

**Output esperado del agente:**

- Checklist de 60+ ítems agrupados en 8 categorías:
  1. **Técnico/Basis** (15 items): todos los TRs importados, smoke tests sistema, performance OK, backup PRD tomado, usuarios desbloqueados
  2. **Configuración** (8 items): períodos contables abiertos, variantes de ejercicio, tipos de cambio cargados, numeraciones configuradas
  3. **Desarrollos** (10 items): 12 reports en PRD + probados, 5 BAdIs activos, ATC sin errores críticos
  4. **Interfaces** (6 items): 3 iFlows CPI activos en producción, prueba de extremo a extremo por cada interfaz
  5. **Datos Migrados** (8 items): reconciliación materiales 5,000/5,000, clientes 800/800, saldos GL = saldos legacy, activos fijos cuadrados
  6. **Seguridad** (6 items): roles asignados a usuarios, SU10 masiva ejecutada, accesos de consultoría bloqueados
  7. **Usuarios** (5 items): entrenamiento completado 100%, manual de usuario en portal, soporte helpdesk listo
  8. **Business Sign-off** (4 items): firmas obtenidas FI, MM, SD + Dirección
- Plan de contingencia/rollback: criterios para pausar go-live, pasos de rollback en < 4h

---

## Casos de Uso Frecuentes

- Casos de prueba de integración end-to-end (P2P, O2C, R2R)
- Validación de desarrollos ABAP: report de aging, BAdIs de validación
- Testing de interfaces CPI: happy path + error handling
- Regresión post-upgrade S/4HANA
- SIT (System Integration Testing) con múltiples módulos interconectados
