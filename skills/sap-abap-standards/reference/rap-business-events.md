# RAP Business Events — publicar eventos de negocio desde un BO

> Material de referencia del agente ABAP. Se lee bajo demanda.
>
> Aplica a SAP BTP ABAP Environment y a S/4HANA on-premise desde 2022 (ABAP
> Platform 2022), donde RAP Business Events llegó al stack local. El entorno por
> defecto del stack, S/4HANA 2023, lo soporta.
> Lo que dependa de release o de configuración del sistema está marcado como
> **`[verificar]`** — no lo afirmes sin comprobarlo contra el sistema real.

## Cuándo sí y cuándo no

| Situación | Decisión |
| --- | --- |
| Un cambio en un BO debe disparar una integración sin polling | Evento |
| El consumidor necesita respuesta y el emisor necesita el resultado | **No** — OData/RFC síncrono |
| El consumidor está en el mismo sistema y puede esperar al commit | Evento **local** (handler ABAP), sin Event Mesh |
| Hay un evento estándar SAP para ese BO | **Suscribirse al estándar**, no crear uno propio |
| Hay que replicar datos maestros completos | **No** — CDC / replicación; el evento es una notificación, no un ETL |

Clean Core: nunca se extiende el BO estándar para agregarle un evento. O el
evento estándar ya existe (catálogo en SAP Business Accelerator Hub, sección de
events del producto), o el evento se publica desde un BO Z propio.

## 1. Declarar el evento en la behavior definition

El evento se declara **dentro del cuerpo del behavior** de la entidad (raíz o
hija) del BO. El payload adicional, si hace falta, es una **CDS abstract
entity**.

> **Nombres.** El ejemplo usa la nomenclatura de los tutoriales de SAP
> (`ZR_…TP` para la entidad raíz transaccional, `ZA_` para abstract entities).
> En los proyectos del stack vale la de `agents/06-abap-developer`: la BDEF
> sobre la vista que corresponda y la clase `ZBP_…`.

```abap
"-- Payloads del evento (CDS abstract entities):
@EndUserText.label: 'Payload evento SalesOrder Approved'
define abstract entity ZA_SalesOrderApproved
{
  approvedBy   : abap.char(12);
  approvedAt   : timestampl;
  reasonCode   : abap.char(2);
  description  : abap.char(60);
}

@EndUserText.label: 'Payload evento SalesOrder Cancelled'
define abstract entity ZA_SalesOrderCancelled
{
  reasonCode   : abap.char(2);
  description  : abap.char(60);
}
```

```abap
"-- Behavior definition:
managed with additional save with full data
  implementation in class zbp_r_salesordertp unique;
strict ( 2 );

define behavior for ZR_SalesOrderTP alias SalesOrder
persistent table zsord_evt
lock master
authorization master ( instance )
etag master LocalLastChangedAt
{
  create;
  update;
  delete;

  "-- Evento sin payload extra: viaja solo la clave de la instancia
  event Created;

  "-- Evento con payload: la abstract entity define los campos adicionales
  event Approved  parameter ZA_SalesOrderApproved;
  event Cancelled parameter ZA_SalesOrderCancelled;

  mapping for zsord_evt corresponding;
}
```

Variantes de la sintaxis BDL:

| Forma | Qué hace |
| --- | --- |
| `event evt;` | Payload = clave de la instancia, nada más |
| `event evt parameter ZA_Entity;` | Agrega el payload de la abstract entity |
| `event evt deep parameter ZA_Entity;` **`[verificar]`** | Payload jerárquico; la abstract entity requiere `with hierarchy`. Release reciente |
| `managed event evt2 on evt parameter ZA_Otra;` **`[verificar]`** | **Evento derivado**: se dispara cuando se dispara `evt`, con otro payload. Release reciente |
| `event evt for side effects;` **`[verificar]`** | Evento para *side effects* de UI, referenciado desde el bloque `side effects { … }`; no sale del sistema. Release reciente |

Las dos primeras formas son las de base y valen en todo release con RAP Business
Events. Las tres marcadas llegaron después: **antes de escribirlas en un BDEF,
comprobá que el release del cliente las acepte** —un activate que las rechaza es
el síntoma—. Los *side effects* de UI se declaran en el bloque
`side effects { … }` (ver `sap-abap-standards/reference/rap.md`); el evento
`for side effects` sólo agrega un disparador a ese bloque.

`with additional save` en la cabecera es lo que habilita el saver propio donde
se hace el raise (en un BO managed; un BO unmanaged ya tiene el suyo). `with full data` pasa la instancia completa a `save_modified`
en vez de solo las claves: evita un `READ ENTITIES` extra para armar el payload.
En los updates, `%control` sigue diciendo **qué campos cambiaron**: es lo que
permite publicar una transición de estado y no cada modificación.

**Sin `with full data`**, `update-<entidad>` trae sólo los campos que el llamador
modificó: `<up>-ApprovedBy` o `<up>-LastChangedAt` llegan vacíos si el update
no los tocaba, y el payload sale con blancos. En ese caso, leé la instancia con
`READ ENTITIES … IN LOCAL MODE` antes de armar el payload.

## 2. Raise — y por qué el momento es lo único que importa

**El evento se dispara en la fase de late save**: en `save_modified` si el BO es
managed con `with additional save` o `with unmanaged save`, o en `save` si el BO
es unmanaged. No es una preferencia de
estilo: es la diferencia entre una integración correcta y una que miente.

### La secuencia de save de RAP

| Fase | Método | ¿Se puede volver atrás? |
| --- | --- | --- |
| Early save | `finalize` | Sí |
| Early save | `check_before_save` | Sí — acá se rechaza y se vuelve a la fase de interacción |
| **Point of no return** | — | **No.** A partir de acá: o commit, o rollback con dump |
| Late save | `adjust_numbers` (late numbering) | No |
| Late save | `save` / `save_modified` | No |
| Post-save | `cleanup` | — |

Consecuencia directa, y es la regla de oro del material:

- **Raise dentro de `save_modified`** ⇒ el evento solo existe si el LUW pasó el
  point of no return. Si la transacción se cae antes, el evento **no se emite**.
- **Raise en una determination, una validation, un handler de action o en
  `check_before_save`** ⇒ el evento puede emitirse y la transacción abortarse
  después. El suscriptor procesa un hecho que nunca ocurrió. Eso no se arregla
  aguas abajo: es un bug de diseño del emisor.

`RAISE ENTITY EVENT` solo se puede usar dentro de un **ABAP Behavior Pool**
(ABP) — no desde un report, una clase cualquiera o un BAdI. Y dentro del ABP
**no** está permitido `COMMIT WORK` / `ROLLBACK WORK`: el dueño de la
transacción es RAP.

### El raise

```abap
CLASS lsc_zr_salesordertp DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
ENDCLASS.

CLASS lsc_zr_salesordertp IMPLEMENTATION.
  METHOD save_modified.

    "-- Alta: evento sin payload adicional
    IF create-salesorder IS NOT INITIAL.
      RAISE ENTITY EVENT zr_salesordertp~Created
        FROM VALUE #( FOR <cr> IN create-salesorder
                      ( %key = VALUE #( SalesOrderId = <cr>-SalesOrderId ) ) ).
    ENDIF.

    "-- Aprobación: solo las instancias que PASARON a aprobadas en este save.
    "   Filtrar por el valor solo (ApprovalStatus = 'A') publicaría Approved
    "   otra vez en cada update de una orden ya aprobada —cambiar la
    "   descripción, por ejemplo—. `%control` dice que el campo cambió ahora.
    IF update-salesorder IS NOT INITIAL.
      RAISE ENTITY EVENT zr_salesordertp~Approved
        FROM VALUE #( FOR <up> IN update-salesorder
                      WHERE ( %control-ApprovalStatus = if_abap_behv=>mk-on
                              AND ApprovalStatus = 'A' )
                      ( %key  = VALUE #( SalesOrderId = <up>-SalesOrderId )
                        %param = VALUE #( approvedBy  = <up>-ApprovedBy
                                          approvedAt  = <up>-LastChangedAt
                                          reasonCode  = '01'
                                          description = 'Approved by workflow' ) ) ).
    ENDIF.

    "-- Baja: el payload viaja en el evento porque la fila ya no existe
    IF delete-salesorder IS NOT INITIAL.
      RAISE ENTITY EVENT zr_salesordertp~Cancelled
        FROM VALUE #( FOR <de> IN delete-salesorder
                      ( %key  = VALUE #( SalesOrderId = <de>-SalesOrderId )
                        %param = VALUE #( reasonCode  = '02'
                                          description = 'Cancelled by customer' ) ) ).
    ENDIF.

  ENDMETHOD.
ENDCLASS.
```

La tabla del `FROM` es del tipo derivado `TYPE TABLE FOR EVENT
<entidad>~<evento>`: clave de la instancia y, si el evento declara `parameter`,
el componente `%param` con la estructura de la abstract entity.

En una baja, lo que el suscriptor va a necesitar **tiene que viajar en el
payload**: después del commit no hay fila que leer.

## 3. Del BO al broker — event binding y configuración

Un evento disparado sin **event binding** solo existe dentro del sistema. El
binding mapea el evento RAP a un **event type** en formato CloudEvents, que es
lo que el broker enruta.

### Event binding (objeto de repositorio, se crea en ADT)

| Campo | Contenido | Ejemplo |
| --- | --- | --- |
| Namespace | Sin camelCase ni espacios | `zsales` |
| Business object | Sin espacios | `salesorder` |
| Root entity name | La behavior definition raíz | `ZR_SalesOrderTP` |
| Entity event name | El evento declarado en la BDEF | `Approved` |
| Operation / version | La operación y su versión mayor | `Approved` / `v1` |

El type/topic resultante concatena namespace, business object, operación y
versión (`zsales.salesorder.Approved.v1` en el tutorial oficial). **`[verificar]`**
la forma exacta con la que ese type se traduce a topic en el broker: depende del
namespace del canal y del release — los eventos estándar S/4 se ven como
`sap/S4HANA/Events/ce/sap/s4/beh/<bo>/v1/<BO>/<Operación>/v1`, con el segmento
`ce` marcando conformidad CloudEvents.

La **versión del event type es contrato público**: cambiar el payload de forma
incompatible exige `v2` y convivencia de ambas, no editar `v1`.

### Configuración del lado del sistema — S/4HANA on-premise

Enterprise Event Enablement (EEE) es el framework que saca el evento del ABAP.

| Transacción | Para qué |
| --- | --- |
| `/IWXBE/CONFIG` | Crear/administrar el **canal** (conexión a la instancia del broker, vía service key) |
| `/IWXBE/OUTBOUND_CFG` | **Outbound bindings**: qué event types publica este sistema por ese canal |
| `/IWXBE/INBOUND_CFG` | Inbound bindings, para eventos que el sistema consume |
| `/IWXBE/EVENT_MONITOR` | Monitor de eventos — el primer lugar donde mirar cuando "el evento no llegó" |
| `SBGRFCMON` | Monitor bgRFC: cola de salida con los mensajes que el sistema no pudo enviar **`[verificar]`** contra el release |

Sin outbound binding, el evento se dispara y no se publica. Es la causa número
uno de "funciona en ADT pero el suscriptor no ve nada".

En **BTP ABAP Environment** la configuración equivalente es un communication
arrangement con el broker y las apps de Enterprise Event Enablement del sistema;
los nombres de communication scenario dependen del release: **`[verificar]`**
contra el sistema antes de escribirlos en un documento de diseño.

## 4. Consumo

### Consumo local (mismo sistema, sin broker)

Útil para desacoplar lógica dentro del BO sin pagar una integración.

```abap
"-- Clase global de event handler (objeto propio en ADT):
CLASS zcl_salesorder_evt_handler DEFINITION PUBLIC ABSTRACT FINAL
  FOR EVENTS OF zr_salesordertp.
ENDCLASS.
CLASS zcl_salesorder_evt_handler IMPLEMENTATION.
ENDCLASS.

"-- En el include CCIMP (pestaña Local Types) de esa clase:
CLASS lhe_salesorder DEFINITION INHERITING FROM cl_abap_behavior_event_handler.
  PRIVATE SECTION.
    METHODS on_approved FOR ENTITY EVENT approved FOR zr_salesordertp~Approved.
ENDCLASS.

CLASS lhe_salesorder IMPLEMENTATION.
  METHOD on_approved.
    "-- `approved` es TYPE TABLE FOR EVENT zr_salesordertp~Approved

    "-- El handler corre en su PROPIO LUW, después del commit del emisor, y
    "   arranca en fase de modificación. Para escribir directo en la base
    "   (una tabla propia, un log) hay que pasar primero a fase de guardado:
    "   sin esto, el runtime rechaza la escritura. [verificar] en el release
    "   si, para modificar OTRO BO por EML, alcanza con MODIFY ENTITIES +
    "   COMMIT ENTITIES sin este paso.
    cl_abap_tx=>save( ).

    LOOP AT approved INTO DATA(ls_evt).
      "-- Lógica idempotente: este método puede ejecutarse más de una vez
      "   para la misma instancia. Verificar por clave natural antes de escribir.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
```

Los métodos de event handler se llaman **de forma asíncrona** respecto de la
transacción que disparó el evento. No hay `COMMIT WORK` / `ROLLBACK WORK`
permitido dentro de ellos, y no tienen parámetros de respuesta RAP: un error acá
**no** revierte el BO.

### Consumo externo (suscriptor)

| Suscriptor | Cómo |
| --- | --- |
| Otro sistema ABAP | **Event Consumption Model** generado por el wizard de ADT **`[verificar]`** disponibilidad por release |
| App CAP | Servicio de messaging de CAP suscrito al topic — ver `sap-btp-standards/reference/cap-arquitectura.md` |
| iFlow de CPI | Adapter AMQP sobre la queue del broker — ver el agente `02-integration` |
| Endpoint HTTP propio | Webhook del broker (ver abajo: los webhooks **no** garantizan orden) |

Regla de diseño para cualquier suscriptor: **suscribirse a una queue durable, no
a un topic efímero**. Si el consumidor está caído y el evento va a un topic sin
queue detrás, el evento se pierde y nadie se entera.

## 5. Qué se rompe en producción

Esta sección es obligatoria en cualquier diseño de eventos del stack. Las reglas
duras del catálogo NFR (`shared/non-functional-requirements.md`) aplican tal
cual: idempotencia, reintentos, observabilidad.

### 5.1 Entrega duplicada — es la norma, no la excepción

El broker reentrega los mensajes que no recibieron acknowledge. Un consumidor
que se cae después de procesar y antes de hacer ack va a recibir el mismo evento
otra vez. **Asumí at-least-once y diseñá el consumidor idempotente**; la entrega
exactly-once no existe como garantía del transporte.

Patrones aceptables, en orden de preferencia:

1. **Deduplicar por id del evento.** El header CloudEvents `ce-id` identifica la
   entrega; guardarlo en una tabla de eventos procesados con TTL y descartar el
   repetido. **`[verificar]`** que el broker y el release propaguen `ce-id` en el
   canal usado antes de construir sobre eso.
2. **Idempotencia por clave natural + estado.** `UPSERT` con clave completa, o
   verificación previa: "¿esta orden ya está en estado aprobado?" → salir sin
   escribir. Funciona aunque no haya id de evento.
3. **Nunca** `INSERT` ciego ni contadores incrementales (`saldo = saldo + x`) en
   el handler de un evento: la segunda entrega duplica el efecto.

### 5.2 Orden no garantizado

Dos eventos de la misma instancia pueden llegar invertidos, y con webhooks es
directamente esperable: el broker toma varios mensajes por adelantado y los entrega en
paralelo. Consecuencia: `Approved` puede procesarse después de `Cancelled`.

Mitigaciones, de menor a mayor costo:

- **Evento delgado + read-back**: el payload lleva la clave y el consumidor lee
  el estado actual por OData/API. El orden deja de importar porque siempre gana
  el estado real. Costo: una llamada por evento, y una ventana de lectura
  desfasada si el read-back pega en una réplica.
- **Marca monotónica en el payload**: incluir `LastChangedAt` (o la ETag) y
  descartar en el consumidor todo evento más viejo que lo ya aplicado.
- **Ordenamiento por partición** en el broker, si el broker lo soporta para esa
  queue: **`[verificar]`** contra el producto y el plan contratados.

### 5.3 El commit falla después del raise

| Momento del fallo | Qué pasa | Qué hacer |
| --- | --- | --- |
| Antes del point of no return | El evento nunca se disparó | Nada: correcto por construcción |
| Rollback tras el point of no return | El raise ocurrió dentro del LUW que se revirtió; el evento no se publica | Nada — **siempre que el raise esté en `save_modified`** |
| Raise en la fase de interacción o en early save, y luego rollback | **Evento publicado de una transacción que no existió** | Bug: mover el raise a `save_modified` (o a `save` en unmanaged). El compilador ya impide disparar fuera del ABP; el error posible es el handler equivocado *dentro* del ABP |
| Commit OK, envío al broker falla | El evento queda en la cola de salida y se reintenta | Monitorear `/IWXBE/EVENT_MONITOR` y la cola bgRFC; sin monitoreo es una integración silenciosamente detenida |

El último renglón es el que más duele: desde el ABAP "todo salió bien". El fallo
vive en la cola, no en el BO. **Sin una alerta sobre esa cola no hay sign-off.**

### 5.4 Volumen

Un evento por instancia significa que un job masivo que toca 50.000 órdenes
dispara 50.000 eventos. Antes de liberar:

- Medir el pico real de eventos/minuto y compararlo contra la capacidad del
  canal y de la queue **`[verificar]`** contra el plan contratado.
- Si el proceso es masivo, evaluar un evento agregado ("lote N procesado") en
  vez de uno por registro, o filtrar en `save_modified` con `%control` como en
  el ejemplo (solo las instancias que cambiaron de estado, no todo `update-`).
- Los `COMMIT WORK` por paquete del proceso masivo (500–2.000 registros) siguen
  aplicando: cada paquete publica sus eventos al cerrar, y eso es lo correcto —
  un solo commit al final publicaría todo de golpe.

### 5.5 Seguridad del payload

El payload **sale del sistema y no pasa por DCL**: la autorización del BO no
protege al suscriptor. No poner en el payload datos personales, condiciones de
precio o cualquier campo que el consumidor no tenga derecho a ver. Otro
argumento a favor del evento delgado: el read-back sí pasa por la autorización
del consumidor.

### 5.6 Observabilidad

- Del lado emisor: `/IWXBE/EVENT_MONITOR` y la cola bgRFC. Alerta sobre
  entradas en error, no inspección manual.
- Del lado consumidor: log con el id del evento, la clave de negocio y el
  veredicto (aplicado / descartado por duplicado / descartado por viejo). Si a
  las 3 AM no se puede responder "¿este evento llegó y qué se hizo con él?", el
  log no sirve.
- Correlación: propagar el id del evento en el log de todos los saltos.

## 6. Testing

- El BO se prueba con `cl_abap_behv_test_environment` como cualquier otro (ver
  `sap-abap-standards/reference/rap.md`).
- Si el evento se dispara en `save_modified`, el test tiene que llegar a
  `COMMIT ENTITIES` para que la save sequence corra: un test que solo hace
  `MODIFY ENTITIES` no dispara nada.
- **`[verificar]`** si el release permite **asertar directamente los eventos
  disparados** desde el test double framework. Si no, la alternativa verificable es
  testear el handler local de consumo como unidad, con su tabla
  `TYPE TABLE FOR EVENT` armada a mano — incluyendo el caso de entrega duplicada.

## 7. Checklist antes de dar por cerrado un evento

- [ ] El `RAISE ENTITY EVENT` está en `save_modified` / `save`, no en una
      determination, validation o action handler.
- [ ] La BDEF declara `with additional save` (y `with full data` si el payload
      necesita datos de la instancia).
- [ ] Un evento de transición filtra por `%control` del campo, no sólo por su
      valor: si no, se publica de nuevo en cada update posterior.
- [ ] Existe el **event binding** y el **outbound binding** del canal; se
      verificó una publicación real, no solo la activación del objeto.
- [ ] El event type está versionado y el payload documentado como contrato.
- [ ] El consumidor es **idempotente** y se probó reenviando el mismo evento.
- [ ] Se probó con los eventos llegando **fuera de orden**.
- [ ] El payload no lleva datos que el suscriptor no está autorizado a ver.
- [ ] Hay alerta (no inspección manual) sobre la cola de salida en error.
- [ ] Se midió el volumen pico de eventos y se comparó contra la capacidad del
      canal.
- [ ] El log del consumidor permite reconstruir qué se hizo con un evento dado.

## Anti-patrones

| Anti-patrón | Por qué falla |
| --- | --- |
| Raise en una determination "porque es más temprano" | Publica hechos que la transacción puede revertir |
| Filtrar la transición sólo por el valor nuevo | Cada update posterior de la instancia vuelve a publicar el evento |
| Payload con el registro completo de datos maestros | El evento se vuelve un ETL frágil, con orden y versión como problema |
| Consumidor con `INSERT` sin deduplicar | La primera reentrega duplica los datos |
| Esperar respuesta del suscriptor | Los eventos son unidireccionales; si hace falta respuesta, es una API |
| Suscripción a topic sin queue durable | Consumidor caído = eventos perdidos sin rastro |
| Cambiar el payload de `v1` en producción | Rompe a todo suscriptor existente sin aviso |
| Asumir exactly-once | Ningún broker del stack lo garantiza |

## Afirmaciones que este material NO verificó

Marcadas arriba como **`[verificar]`**. Resumen, para que nadie las copie a un
documento de cliente como si fueran hechos:

| Afirmación | Por qué no se verificó |
| --- | --- |
| Forma exacta del topic en el broker para un evento custom | Depende del namespace del canal y del release |
| Nombres de communication scenario en BTP ABAP Environment | Varían por release |
| Disponibilidad de `SBGRFCMON` / nombre de la cola de salida de EEE | Documentado en blogs de SAP, no confirmado contra un sistema |
| Propagación del header `ce-id` en todos los canales | Depende del broker y del release |
| Soporte de ordenamiento por partición en la queue | Depende del producto y del plan contratado |
| Wizard de Event Consumption Model en ADT por release | No confirmado contra un sistema |
| Aserción directa de eventos disparados en el test double framework | No confirmado contra la documentación de la versión |
| Sintaxis `deep parameter`, `managed event … on …` y `event … for side effects` | Llegaron en releases posteriores a los eventos básicos; el release exacto no se confirmó |
| Si un handler local que modifica otro BO por EML necesita `cl_abap_tx=>save( )` | La documentación lo exige para escrituras directas; para EML no se confirmó |

## Fuentes

Citalas por su ID del catálogo `sap-fuentes-de-verdad`, que el hook de cierre
verifica:

| Para | Fuente |
| --- | --- |
| Sintaxis BDL de `event`, save sequence, event binding, handler local | `[fuente:abap.rap]` |
| `RAISE ENTITY EVENT`, `save_modified`, clase y método de event handler | `[fuente:abap.keyword-doc]` |
| Qué está permitido en ABAP Cloud (release contract) | `[fuente:abap.cloud]` |
| Eventos estándar publicados por el producto | `[fuente:sap.api-hub]` |
| Restricciones o correcciones por SP | `[fuente:sap.notes]`, con el número de nota |
