# 🔗 AGENTE 02 — Ejemplos de Uso

## Ejemplo 1: iFlow de Replicación de Órdenes de Compra a WMS Externo

**Prompt de entrada:**

```text
Diseña un iFlow en SAP CPI para enviar órdenes de compra liberadas desde SAP S/4HANA
a un WMS externo (Manhattan Associates) en tiempo real.
Trigger: evento ORDERS.CREATED de SAP Event Mesh.
Protocolo salida: REST POST en el WMS.
Formato: S/4HANA devuelve IDoc ORDERS05, WMS espera JSON.
Volumen: ~500 POs/día.
```

**Output esperado del agente:**

- Interface Spec completa: `INT-MM-WMS-001`
- iFlow con nodos: Event Mesh Sender → Content Modifier (enrich headers) → XSLT IDoc→JSON → HTTP Receiver
- Script Groovy para mapeo de campos clave (LIFNR → supplierId, BEDAT → orderDate)
- Exception Subprocess con retry (3 intentos, 5 min backoff) + alerta correo
- Dead Letter Queue en Event Mesh para mensajes fallidos
- Configuración de destino HTTP en BTP (OAuth 2.0 con WMS token endpoint)
- Estrategia de pruebas: postman collection + SAP Integration Advisor

---

## Ejemplo 2: OData Service para App Fiori de Aprobación de Facturas

**Prompt de entrada:**

```text
Diseña el servicio OData V4 para una app Fiori de aprobación de facturas de proveedores.
La app necesita: listar facturas pendientes, ver detalle con posiciones, aprobar/rechazar.
Fuente de datos: S/4HANA tablas RBKP, RSEG, LFA1.
Consumidor: App Fiori Elements en SAP BTP.
Seguridad: solo facturas de la org. de compras del usuario.
```

**Output esperado del agente:**

- Diseño OData V4 con Entity Types: `SupplierInvoice`, `InvoiceItem`, `Supplier`
- Navigation: `SupplierInvoice/to_Items`, `SupplierInvoice/to_Supplier`
- Bound Actions: `SupplierInvoice/approve()`, `SupplierInvoice/reject(reason)`
- Filtros soportados: status eq 'PENDING', purchOrg, companyCode, postingDate
- $expand: `?$expand=to_Items,to_Supplier`
- Seguridad: restricción de filas por purchasing org via XSUAA scope
- CDS View base: `ZC_VENDOR_INVOICE` con anotaciones `@OData.publish:true`
- Especificación de autorización: objeto `F_RECH_BUK` + `M_BEST_ORG`

---

## Ejemplo 3: Integración Bidireccional SAP → Salesforce (Oportunidades/Cotizaciones)

**Prompt de entrada:**

```text
Diseña la integración entre SAP S/4HANA y Salesforce CRM.
Flujo 1: Cuando se gana una oportunidad en Salesforce, crear cotización SD en SAP (VA21).
Flujo 2: Cuando la cotización cambia de status en SAP, actualizar el stage en Salesforce.
SAP Integration Suite disponible. Salesforce con API REST habilitada.
Volumen: 200 oportunidades/día.
```

**Output esperado del agente:**

- Diagrama de integración bidireccional con SAP CPI como hub
- Interface Spec Flujo 1: `INT-SD-SFDC-001` (Salesforce → SAP)
  - Webhook Salesforce → CPI HTTP Sender
  - Groovy script para mapear campos SFDC → BAPI `SD_SALESDOCUMENT_CREATE`
  - Manejo de errores: rollback + notificación a equipo CRM
- Interface Spec Flujo 2: `INT-SD-SFDC-002` (SAP → Salesforce)
  - BAdI `SD_DOCUMENT_SAVE_20` en SAP dispara RFC → iFlow CPI
  - iFlow llama PATCH `/services/data/v58.0/sobjects/Opportunity/{id}`
  - OAuth 2.0 Client Credentials para autenticar con Salesforce
- Estrategia de idempotencia: ID externo SFDC guardado en VBKD-BSTNK

---

## Casos de Uso Frecuentes

- Integración SAP ↔ Microsoft (Teams notificaciones, SharePoint documentos, Azure AD users)
- Replicación de Business Partners SAP → CRM externo via IDoc CREMAS/DEBMAS
- EDI con proveedores: recepción de ORDERS/DESADV/INVOIC en formato EDIFACT/X12
- SAP → Power BI via OData para dashboards ejecutivos
- Webhooks de SAP S/4HANA (SAP Event Mesh) hacia microservicios en BTP
