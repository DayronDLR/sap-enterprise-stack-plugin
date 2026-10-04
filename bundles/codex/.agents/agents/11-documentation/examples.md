# Ejemplos — AGENTE 11 SAP Documentation Architect

## Ejemplo 1: Proyecto Full-Stack BTP + ABAP/RAP

**Prompt de entrada:**

```text
Actúa como SAP Documentation Architect.
Documenta el siguiente proyecto:

Nombre: Aprobación Digital de Órdenes de Compra
Cliente: Acme Manufacturing S.A.
Stack:
  - CAP Node.js en BTP Cloud Foundry
  - HANA Cloud (HDI container)
  - RAP BO para OC en S/4HANA 2023 On-Premise
  - Fiori Elements (List Report + Object Page)
  - Integration Suite: iFlow para notificaciones email

El usuario puede ver sus OC pendientes en Fiori, aprobarlas o rechazarlas.
CAP orquesta la lógica, llama el RAP BO vía EML expuesto como OData V4.
```

**Output esperado del agente:**

- Detecta: BTP ✓, CAP ✓, HANA ✓, ABAP/RAP ✓, Fiori ✓, Integration ✓
- Genera `ACME-AprobacionOC-doc.md` con todas las secciones
- Incluye diagrama C4 ASCII con todos los componentes
- Documenta RAP BO completo: ZI/ZC Views, BDEF, BIMP, EML
- Documenta CAP service con handler que llama RAP vía OData
- Documenta iFlow de notificación
- Genera `build-doc.sh` con comando pandoc

## Ejemplo 2: Proyecto Cloud-Only CAP + HANA

**Prompt de entrada:**

```text
Actúa como SAP Documentation Architect.
Documenta el siguiente proyecto CAP:

Nombre: Portal de Gestión de Gastos
Cliente: Grupo Empresarial ABC
Stack:
  - CAP Node.js + HANA Cloud
  - Fiori Elements
  - XSUAA + SAP Build Work Zone
  - Consume API de S/4HANA: BusinessPartner, CostCenter (no hay ABAP custom)
No hay código ABAP. Consume estándar via SAP API Business Hub.
```

**Output esperado del agente:**

- Detecta: BTP ✓, CAP ✓, HANA ✓, ABAP/RAP ✗ (solo APIs consumidas)
- Omite toda sección ABAP/RAP — agrega nota explícita de por qué
- En sección 5.3 documenta: APIs estándar consumidas (endpoint, auth, payload)
- Genera `GEABC-GestionGastos-doc.md` sin secciones ABAP
- Documenta XSUAA scopes y Work Zone config

## Ejemplo 3: Con template del cliente

**Prompt de entrada:**

```text
Actúa como SAP Documentation Architect.
El cliente provee su template en template-cliente.docx con esta estructura:
  1. Objetivo del documento
  2. Descripción funcional
  3. Descripción técnica
     3.1 Diagrama de arquitectura
     3.2 Componentes
     3.3 Integraciones
  4. Seguridad
  5. Plan de pruebas (dejar placeholder)
  6. Anexos

Proyecto: Migración de módulo SD a S/4HANA
Stack: Solo ABAP — Pricing BAdIs + CDS Views + Reports ALV
```

**Output esperado del agente:**

- Respeta EXACTAMENTE la numeración del template del cliente
- No agrega secciones que no estén en el template
- Detecta: BTP ✗, ABAP ✓ (BAdIs + CDS + Reports)
- En sección 3 documenta solo componentes ABAP presentes
- Genera build-doc.sh con --reference-doc=template-cliente.docx
- Sección 5 queda como placeholder explícito para el equipo QA

## Casos de Uso Frecuentes

- Documentación técnica de entregables para cliente final
- Architecture Decision Records (ADR) de proyectos SAP BTP
- Documentación de go-live para handover a operaciones
- Technical Spec de una extensión Clean Core para aprobación de arquitectura
- Documentación de interfaces para equipos de integración externos
