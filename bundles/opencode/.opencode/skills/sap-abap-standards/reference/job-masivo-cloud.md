# Job masivo reanudable en ABAP Cloud

> **Uso:** patrón completo del agente ABAP (`agents/06-abap-developer`, sección
> «Patron obligatorio para batch masivos»). Se lee cuando la tarea es un proceso
> masivo; las reglas están en el prompt del agente.

Application job (S/4HANA 2023, ABAP language version 5). Todo lo que usa está
released: `IF_APJ_DT_EXEC_OBJECT` / `IF_APJ_RT_EXEC_OBJECT`, `CL_BALI_*`,
`CL_ABAP_LOCK_OBJECT_FACTORY`. En Standard ABAP justificado el mismo patrón puede
ser un report con `ENQUEUE_<objeto>` y `BAL_*`: en ABAP Cloud esos FMs no están
released y el syntax check los rechaza.

```abap
"-- Application job: catálogo (SAJC) + template (SAJT) en ADT; se programa desde la
"   app Fiori "Application Jobs". Objeto de log ZORDER/BATCH (APLO). Lock object EZORDER.
CLASS zcl_order_batch_job DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_exec_object.
  PRIVATE SECTION.
    CONSTANTS gc_job   TYPE zjob_checkpoint-job_id VALUE 'ZORDER_BATCH'.
    CONSTANTS gc_chunk TYPE i VALUE 1000.
ENDCLASS.

CLASS zcl_order_batch_job IMPLEMENTATION.
  METHOD if_apj_dt_exec_object~get_parameters.
    CLEAR: et_parameter_def, et_parameter_val.
  ENDMETHOD.

  METHOD if_apj_rt_exec_object~execute.
    TYPES ty_order_range TYPE RANGE OF zorder_in-order_id.
    DATA lo_log  TYPE REF TO if_bali_log.
    DATA lo_lock TYPE REF TO if_abap_lock_object.
    TRY.
        lo_log  = cl_bali_log=>create_with_header( header = cl_bali_header_setter=>create(
                    object = 'ZORDER' subobject = 'BATCH' external_id = CONV #( gc_job ) ) ).
        lo_lock = cl_abap_lock_object_factory=>get_instance( iv_name = 'EZORDER' ).
      CATCH cx_bali_runtime cx_abap_lock_failure.
        RAISE EXCEPTION TYPE cx_apj_rt_content.   "-- el job queda en error en "Application Jobs"
    ENDTRY.

    "-- 0) Reanudar desde el checkpoint: si cayó en el registro 47.000, sigue en el siguiente
    SELECT SINGLE last_id FROM zjob_checkpoint WHERE job_id = @gc_job INTO @DATA(lv_last_id).

    DO.
      "-- Campos explícitos (nunca SELECT *), ordenados por la clave
      SELECT order_id, amount FROM zorder_in
        WHERE status = 'NEW' AND order_id > @lv_last_id
        ORDER BY order_id
        INTO TABLE @DATA(lt_orders) UP TO @gc_chunk ROWS.
      IF lt_orders IS INITIAL.
        EXIT.
      ENDIF.

      "-- 1) Lock por registro: sólo los bloqueados con éxito se procesan; el resto se
      "--    loguea y queda NEW para la próxima corrida (nunca saltar en silencio)
      DATA(lr_ok) = VALUE ty_order_range( ).
      LOOP AT lt_orders INTO DATA(ls_order).
        TRY.
            lo_lock->enqueue( it_parameter = VALUE #( ( name = 'ORDER_ID' value = REF #( ls_order-order_id ) ) ) ).
            lr_ok = VALUE #( BASE lr_ok ( sign = 'I' option = 'EQ' low = ls_order-order_id ) ).
          CATCH cx_abap_foreign_lock cx_abap_lock_failure.
            MESSAGE w001(zorder) WITH ls_order-order_id INTO DATA(lv_msg) ##NEEDED.   "-- llena sy-msg* para create_from_sy
            TRY.
                lo_log->add_item( cl_bali_message_setter=>create_from_sy( ) ).
              CATCH cx_bali_runtime.
            ENDTRY.
        ENDTRY.
      ENDLOOP.
      lv_last_id = lt_orders[ lines( lt_orders ) ]-order_id.

      TRY.
          "-- 2) Una sola escritura por paquete (sin SELECT/MODIFY DB dentro del LOOP)
          IF lr_ok IS NOT INITIAL.
            UPDATE zorder_in SET status = 'DONE' WHERE order_id IN @lr_ok AND status = 'NEW'.
            DATA(lv_esperados) = lines( lr_ok ).
            IF sy-dbcnt <> lv_esperados.
              "-- alguno cambió de estado entre el SELECT y el lock: no se pierde en silencio
              MESSAGE w002(zorder) WITH sy-dbcnt lv_esperados INTO lv_msg.
              lo_log->add_item( cl_bali_message_setter=>create_from_sy( ) ).
            ENDIF.
          ENDIF.
          "-- 3) Checkpoint en la misma LUW; MODIFY lo crea en la primera corrida
          MODIFY zjob_checkpoint FROM @( VALUE zjob_checkpoint( job_id = gc_job last_id = lv_last_id ) ).
          "-- 4) Log por paquete (SLG1 on-prem y detalle del application job)
          cl_bali_log_db=>get_instance( )->save_log( log = lo_log assign_to_current_appl_job = abap_true ).
          "-- 5) COMMIT por paquete (permitido en ABAP Cloud fuera de handlers RAP); no hay cursor abierto
          COMMIT WORK.
        CATCH cx_sy_open_sql_db cx_bali_runtime INTO DATA(lx_err).
          ROLLBACK WORK.   "-- el paquete vuelve a NEW; el checkpoint no avanza
          TRY.
              lo_log->add_item( cl_bali_exception_setter=>create(
                                  severity = if_bali_constants=>c_severity_error exception = lx_err ) ).
              "-- 2ª conexión: el log del error sobrevive al ROLLBACK
              cl_bali_log_db=>get_instance( )->save_log_2nd_db_connection(
                                  log = lo_log assign_to_current_appl_job = abap_true ).
            CATCH cx_bali_runtime.
          ENDTRY.
          RAISE EXCEPTION TYPE cx_apj_rt_content.
      ENDTRY.
      cl_abap_lock_object_factory=>dequeue_all( ).
    ENDDO.

    "-- 6) Corrida completa: se borra el checkpoint para que la próxima tome los NEW
    "--    que quedaron atrás por un lock
    DELETE FROM zjob_checkpoint WHERE job_id = @gc_job.
    COMMIT WORK.
  ENDMETHOD.
ENDCLASS.
```

**Reglas que el ejemplo no puede mostrar:**

- **Releer después del lock.** El `AND status = 'NEW'` del `UPDATE` protege este ejemplo,
  pero la lógica de negocio que va en ese lugar tiene que trabajar sobre el registro
  leído **después** del `enqueue`, no sobre el del `SELECT` del paquete.
- **Una sola instancia del job.** La fila de checkpoint es por job: dos instancias
  la adelantarían o la borrarían una a la otra. Programar el template sin ejecuciones
  en paralelo, o tomar un lock a nivel job con su propio lock object y liberar los de
  registro con `dequeue` (no `dequeue_all`, que también soltaría el del job).
- **Errores transitorios** (lock timeout, deadlock): el paquete vuelve a NEW y se
  reintenta en la próxima corrida; un paquete que falla siempre (dato inválido) se
  aísla registro por registro para no bloquear el job.

Verificar con F2 en ADT, antes de publicarlo en un proyecto, las firmas de
`cl_bali_exception_setter=>create`, `save_log_2nd_db_connection` y
`cl_abap_lock_object_factory=>dequeue_all` en el release del cliente.
