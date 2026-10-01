# 📋 AGENTE 01 — Ejemplos de Uso

## Ejemplo 1: Requerimiento de Bloqueo de Proveedores

**Prompt de entrada:**

```text
Necesito un Functional Spec para SAP MM: cuando un proveedor supere su límite de crédito 
definido en el Business Partner, el sistema debe bloquear automáticamente sus órdenes de 
compra y notificar al comprador responsable por email.
```

**Output esperado del agente:**

- FS con secciones completas
- Identificación: SAP MM + FI + BAdI ME_PROCESS_PO_CUST
- Transacciones: ME21N, ME22N, XK02, BP
- Configuración: Grupos de tolerancia, mensaje de usuario
- Dev: BAdI para lógica de validación
- Interface: BCS para notificación email

---

## Ejemplo 2: Blueprint de Proceso O2C

**Prompt de entrada:**

```text
Necesito el blueprint del proceso Order-to-Cash completo para una empresa industrial 
con ventas nacionales e internacionales en SAP S/4HANA.
```

**Output esperado:**

- Diagrama de proceso BPMN textual
- Módulos: SD + FI + MM (si hay picking)
- Transacciones por paso: VA01, VL01N, VF01, F-28
- Org structure: Org Ventas, Canal, División, Planta, Almacén
- Variantes internacionales: incoterms, moneda, impuestos

---

## Ejemplo 3: Gap Analysis

**Prompt de entrada:**

```text
Haz un gap analysis de los requerimientos de nómina para una empresa con 
empleados en México. El cliente quiere usar SAP SuccessFactors + SAP Payroll.
```

**Output esperado:**

- Tabla de gaps con todos los campos
- Integración SF ↔ ECP (Employee Central Payroll)
- Legislación MX: IMSS, SAT, INFONAVIT
- IDOCs de integración
- Gaps de localización

---

## Casos de Uso Frecuentes

- Requerimientos FI: pagos, conciliaciones, activos fijos
- Requerimientos MM: aprovisionamiento, inventarios, contratos
- Requerimientos SD: pedidos, entregas, facturación, crédito
- Requerimientos PP: órdenes de producción, planificación MRP
- Requerimientos HR: nómina, tiempo, viajes
