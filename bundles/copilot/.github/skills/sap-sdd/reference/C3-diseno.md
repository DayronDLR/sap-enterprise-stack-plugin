# C3 — Diseño

Perspectiva: **Solution Architect SAP**. Convertís el requerimiento y los
escenarios en una arquitectura y en la **lista cerrada de objetos** que se van a
construir o configurar. Esa lista es lo único que C4 puede estimar: lo que no
está en el inventario no se construye, y lo que está, se estima.

## Qué leer

1. `C2-escenarios/handoff.md` y `C2-escenarios/escenarios.md`, sobre todo los
   escenarios no funcionales: volumen, concurrencia e integraciones condicionan
   el diseño.
2. `C1-captura/requerimiento.md`, `fs.md` y `gap-analysis.md` si existe.
3. **No leas `entradas/`.**

## Qué producir

| Archivo | Obligatorio | Qué verifica el gate |
|---|---|---|
| `C3-diseno/diseno.md` | sí | al menos una cita; el inventario completo y bien formado |
| `C3-diseno/arquitectura.sapdiag.json` | sí | pasa el motor de `sap-diagrams` con el perfil de entrega (showcase) |
| `C3-diseno/handoff.md` | sí | — |
| `C3-diseno/arquitectura.drawio`, `C3-diseno/arquitectura.svg` | no | los genera `sapdiag deliver` |
| `C3-diseno/prototipo.html` | no | sólo si hay UI, con criterio Fiori |

## Clean Core: el orden de preferencia

Cada necesidad se resuelve con la primera opción de esta lista que alcance:

1. **Estándar**: el sistema ya lo hace; sólo hay que usarlo.
2. **Configuración**: customizing (SPRO), sin código.
3. **Extensión**: BAdI, CDS, RAP, extensibilidad in-app sobre APIs liberadas.
4. **BTP**: desarrollo lateral (CAP, Fiori, Integration Suite).

Una **modificación del estándar no es una opción**, y el gate la rechaza. Saltar
a una opción más cara cuando alcanza una más barata es la primera forma de
sobredimensionar un proyecto: el diseño la tiene que justificar.

## `diseno.md`

- **Contexto y decisiones**: cada decisión relevante, con la alternativa que se
  descartó y por qué. Cita el requerimiento.
- **Arquitectura**: qué muestra el diagrama y los flujos principales.
- **Inventario de objetos**: la tabla de abajo.
- **No funcionales**: cómo cumple cada escenario NFR de C2 (locking, volumen,
  idempotencia, observabilidad). Nombrá el mecanismo, no la intención.
- **Seguridad**: roles, objetos de autorización y restricciones.
- **Transportes**: qué viaja por qué ruta (gCTS, CTS+, cTMS).
- **Riesgos técnicos**: lo que C4 va a tener que cuantificar.

### El inventario

```markdown
## Inventario de objetos

| ID | Objeto | Tipo | Capa | Clean Core | Fuente |
|---|---|---|---|---|---|
| OBJ-01 | ZI_AgingAR | CDS view | Datos | Extensión | [C1-captura/requerimiento.md:4] |
| OBJ-02 | Intervalos de antigüedad | Customizing | Configuración | Configuración | [C1-captura/requerimiento.md:8] |
```

- **Una fila por objeto entregable y probable por sí mismo**: una vista CDS,
  una implementación de BAdI, una app Fiori, un iFlow, un grupo de actividades de
  customizing. Ni "el backend" ni cada campo por separado.
- **Lo que hay que configurar para que funcione también es un objeto**:
  conectividad (Cloud Connector, destinations, credenciales OAuth), roles y
  catálogos de Launchpad, jobs. Si no está en el inventario, C4 no lo puede
  estimar y el proyecto lo termina pagando sin plan.
- `Clean Core`: `Estándar`, `Configuración`, `Extensión` o `BTP`.
- `Fuente`: la regla que lo pide. Un objeto sin regla que lo pida no se
  construye.
- **Reusá antes de construir**: si un objeto existente o el estándar lo
  resuelve, la fila lo dice (`Estándar`) y en C4 cuesta su adaptación, no su
  construcción.
- Nada "por si acaso": una funcionalidad que el requerimiento no pide no entra,
  aunque sea buena idea. Va a `handoff.md` como propuesta, fuera del alcance.

## `arquitectura.sapdiag.json`

Usá el skill `sap-diagrams`: leé su `SKILL.md`, **un** schema y **un** ejemplo del
tipo que corresponde (casi siempre `architecture`), escribí la especificación y
validala hasta que pase:

```bash
node <sap-diagrams>/bin/sapdiag.mjs validate C3-diseno/arquitectura.sapdiag.json --quality showcase
```

Nunca escribas coordenadas ni XML de draw.io a mano. Para entregar el `.drawio`
y el `.svg`, `sapdiag deliver` los genera junto al `.json`.

## `handoff.md` — para C4

- El inventario resumido por capa, y qué objetos son reuso o estándar.
- Los supuestos que cambian el esfuerzo: volumen, calidad de los datos, APIs
  disponibles, sistemas de terceros.
- Los riesgos técnicos candidatos a contingencia.
- Lo que quedó fuera del alcance a propósito.

## No hacer

- Objetos sin regla que los pida, o funcionalidad que nadie pidió.
- Un desarrollo donde alcanzaba el estándar o la configuración.
- Diagramas hechos a mano o sin validar.
- Dejar `<!-- sdd:pendiente -->` en un archivo que se presenta.
