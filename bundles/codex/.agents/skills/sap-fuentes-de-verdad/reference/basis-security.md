# Fuentes de verdad — Basis & Security (ABAP Platform 2023 + BTP)

> La frescura de este archivo la marca el `prompt-meta` de
> `sap-fuentes-de-verdad/SKILL.md`, que cubre el skill entero.

## 1. Fuentes oficiales

| ID | Fuente | Autoritativa para | Enlace |
| --- | --- | --- | --- |
| `s4.security-guide-2023` | **Security Guide — SAP S/4HANA 2023** (PDF) | Seguridad por aplicación de S/4HANA: autorizaciones, datos personales, comunicaciones | [SEC_OP2023.pdf](https://help.sap.com/doc/d7c2c95f2ed2402c9efa2f58f7c233ec/2023/en-US/SEC_OP2023.pdf) |
| `abap.security-guide` | **ABAP Platform Security Guide (2023)** | Usuarios, parámetros de seguridad, RFC/ICF, SNC, hardening del stack ABAP | [ABAP Platform Security Guide](https://help.sap.com/docs/ABAP_PLATFORM_NEW/621bb4e3951b4a8ca633ca7ed1c0aba2/4aaf6fd65e233893e10000000a42189c.html?version=2023.latest) |
| `abap.role-admin` | **Role Administration (PFCG) — ABAP Platform 2023** | Roles simples y compuestos, roles derivados, generación de perfiles | [Role Administration](https://help.sap.com/docs/ABAP_PLATFORM_NEW/8ce194a1a3a24911ab5679318167e841/4d4fe1e272d51c91e10000000a42189e.html?version=2023.latest) |
| `abap.su24` | **Authorization Defaults (SU24) — ABAP Platform 2023** | Modificar los defaults de autorización entregados por SAP y su efecto en PFCG | [SU24](https://help.sap.com/docs/ABAP_PLATFORM_NEW/ad77b44570314f6d8c3a8a807273084c/1ece3075dd4e4116b23e006552374ffc.html?version=2023.latest) |
| `abap.auth-check-to-role` | **From the Programmed Authorization Check to a Role** | Cadena `AUTHORITY-CHECK` → objeto de autorización → SU24 → rol | [Del check al rol](https://help.sap.com/docs/ABAP_PLATFORM_NEW/ad77b44570314f6d8c3a8a807273084c/fc27cdec46fa4f77b8ac6b3d5169b72e.html?version=2023.latest) |
| `abap.auth-trace` | **Trace for Authorization Checks — ABAP Platform 2023** | Diagnóstico de autorizaciones faltantes con traza (`STAUTHTRACE`) | [Trace for Authorization Checks](https://help.sap.com/docs/ABAP_PLATFORM_NEW/ad77b44570314f6d8c3a8a807273084c/cac80adc77a440e0a855364a4267079f.html?version=2023.latest) |
| `abap.cts` | **Change and Transport System (CTS) — ABAP Platform 2023** | Órdenes Workbench/Customizing, capas y rutas de transporte | [Change and Transport System](https://help.sap.com/docs/ABAP_PLATFORM_NEW/4a368c163b08418890a406d413933ba7/48c4300fca5d581ce10000000a42189c.html?version=2023.latest) |
| `abap.tms` | **Transport Management System (TMS) — ABAP Platform 2023** | Dominio de transporte, rutas, colas de import (`STMS`) | [Transport Management System](https://help.sap.com/docs/ABAP_PLATFORM_NEW/4a368c163b08418890a406d413933ba7/0988f339db9911d2b41a00609419f767.html?version=2023.latest) |
| `btp.ctms` | **SAP Cloud Transport Management** | Nodos y rutas de transporte en BTP, transporte de MTAs y contenido cloud | [help.sap.com/docs/cloud-transport-management](https://help.sap.com/docs/cloud-transport-management) |
| `btp.ias` | **SAP Cloud Identity Services — Identity Authentication** | IdP corporativo, SSO, MFA, trust con BTP y S/4HANA | [help.sap.com/docs/cloud-identity-services](https://help.sap.com/docs/cloud-identity-services) |
| `btp.ips` | **SAP Cloud Identity Services — Identity Provisioning** | Aprovisionamiento de usuarios y grupos entre sistemas | [help.sap.com/docs/identity-provisioning](https://help.sap.com/docs/identity-provisioning) |
| `grc.access-control` | **SAP Access Control 12.0** (sólo si el cliente lo licencia) | Análisis SoD, gestión de accesos, emergency access, diseño de roles | [help.sap.com/docs/SAP_ACCESS_CONTROL](https://help.sap.com/docs/SAP_ACCESS_CONTROL) |
| `sap.security-notes` | **SAP Security Notes & News** (Patch Day) | Publicación mensual de Security Notes y su priorización | [Security Notes & News](https://support.sap.com/en/my-support/knowledge-base/security-notes-news.html) |
| `sap.notes` | **SAP Notes / KBA** (requiere S-user) | Correcciones, Security Notes concretas, restricciones por SP | [me.sap.com/notes](https://me.sap.com/notes) |
| — | Skills `sap-btp-best-practices`, `sap-btp-connectivity` (vendored) | Gobernanza BTP y patrones de conectividad | material de trabajo — **no es norma** |
| — | MCP `sap-adt` (`ListTransports`, `GetTransport`) | Leer las órdenes reales antes de proponer un import | herramienta, sólo lectura |

**Las páginas de ABAP Platform se citan fijadas a 2023** (`version=2023.latest`):
sin el parámetro, help.sap.com abre la última release, que no es la del cliente.

## 2. Qué NO citar en este stack

| No cites… | Porque… |
| --- | --- |
| Documentación de NetWeaver 7.x u otra release de ABAP Platform | Transacciones, defaults de SU24 y parámetros cambian por release |
| Doc de XSUAA o de Identity Authentication para roles ABAP | Son modelos distintos: el rol ABAP on-premise vive en PFCG |
| Doc de SAP Access Control si el cliente no lo tiene | Describe un control que no existe en el landscape |
| Un rol `SAP_*` o un valor de SU24 "de memoria" | Se lee en el sistema: cambia por release y por SU25 |
| Listas de `S_TCODE` o roles "todo en uno" de blogs | Pista, no fuente; rompen SoD |
| Doc del entorno Neo de BTP | Entorno en retiro; el landscape objetivo es Cloud Foundry |

## 3. Fuentes del proyecto

| Fuente | Datos |
| --- | --- |
| Roles en `PFCG` (export / órdenes de transporte) | Menús, objetos, valores de campo, derivaciones |
| Defaults `SU24` del cliente | Propuestas de autorización por transacción o servicio |
| Matriz de roles / SoD firmada (o reglas de SAP Access Control) | Qué combinaciones están prohibidas |
| Configuración `STMS` (dominio, rutas, capas) | Orden DEV → QAS → PRD y rutas de consolidación |
| Rutas y nodos de Cloud Transport Management | Transporte de MTAs y contenido BTP |
| Trust y role collections de cada subaccount BTP | IdP, grupos, mapeos de roles |
| Perfil de parámetros del sistema (`RZ10` / `RZ11`) | Parámetros de login, password, seguridad |

**Transacciones relevantes:** `PFCG`, `SU01`, `SU24`, `SU25`, `SU53`, `STAUTHTRACE`,
`SUIM`, `STMS`, `SE09`/`SE10`, `RZ10`, `RSAU_CONFIG`/`RSAU_READ_LOG` (Security Audit Log).
