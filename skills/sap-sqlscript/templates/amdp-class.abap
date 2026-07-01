*&---------------------------------------------------------------------*
*& AMDP Class Template
*&
*& Production-ready ABAP Managed Database Procedure (AMDP) class with:
*& - Proper interface implementation (IF_AMDP_MARKER_HDB)
*& - Multiple method types (procedure, function, CDS)
*& - Error handling compatible with ABAP exception handling
*& - Documentation and usage examples
*&
*& Prerequisites:
*& - NetWeaver 7.40 SP05 or higher
*& - SAP HANA database
*& - Eclipse ADT for development
*&
*& @version 2.1.0
*& @last_updated 2025-12-27
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Class Definition
*----------------------------------------------------------------------*
CLASS zcl_amdp_template DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Required marker interface for HANA database procedures
    INTERFACES if_amdp_marker_hdb.

    "!-----------------------------------------------------------------*
    "! Type Definitions
    "!-----------------------------------------------------------------*

    "! Structure for single record result
    TYPES: BEGIN OF ty_result,
             id          TYPE i,
             name        TYPE string,
             amount      TYPE p LENGTH 15 DECIMALS 2,
             status      TYPE c LENGTH 10,
             created_at  TYPE timestamp,
           END OF ty_result.

    "! Table type for multiple records
    TYPES: tt_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    "! Structure for error information
    TYPES: BEGIN OF ty_error,
             error_code    TYPE i,
             error_message TYPE string,
           END OF ty_error.

    "!-----------------------------------------------------------------*
    "! AMDP Procedure Method (can perform read and write operations)
    "!-----------------------------------------------------------------*
    "! @parameter iv_filter_id   | Filter by ID
    "! @parameter iv_status      | Filter by status
    "! @parameter et_result      | Result table
    "! @parameter ev_count       | Number of records
    "! @raising   cx_amdp_error  | AMDP execution error
    CLASS-METHODS get_filtered_data
      IMPORTING
        VALUE(iv_filter_id) TYPE i DEFAULT 0
        VALUE(iv_status)    TYPE string DEFAULT ''
      EXPORTING
        VALUE(et_result)    TYPE tt_result
        VALUE(ev_count)     TYPE i
      RAISING
        cx_amdp_error.

    "!-----------------------------------------------------------------*
    "! AMDP Table Function (read-only, can be used in SELECT)
    "!-----------------------------------------------------------------*
    "! @parameter iv_start_date | Start date for filter
    "! @parameter iv_end_date   | End date for filter
    "! @return    rt_result     | Result table
    CLASS-METHODS get_data_by_date
      IMPORTING
        VALUE(iv_start_date) TYPE d
        VALUE(iv_end_date)   TYPE d
      RETURNING
        VALUE(rt_result)     TYPE tt_result.

    "!-----------------------------------------------------------------*
    "! AMDP Procedure with Error Handling
    "!-----------------------------------------------------------------*
    "! @parameter iv_id         | Record ID to process
    "! @parameter iv_new_amount | New amount value
    "! @parameter ev_success    | 1 = success, 0 = failure
    "! @parameter ev_error      | Error details if failed
    CLASS-METHODS update_record
      IMPORTING
        VALUE(iv_id)         TYPE i
        VALUE(iv_new_amount) TYPE p LENGTH 15 DECIMALS 2
      EXPORTING
        VALUE(ev_success)    TYPE i
        VALUE(ev_error)      TYPE ty_error.

  PROTECTED SECTION.

  PRIVATE SECTION.
    "! Internal helper method (not AMDP)
    CLASS-METHODS validate_input
      IMPORTING
        iv_id     TYPE i
      RETURNING
        VALUE(rv_valid) TYPE abap_bool.

ENDCLASS.

*----------------------------------------------------------------------*
* Class Implementation
*----------------------------------------------------------------------*
CLASS zcl_amdp_template IMPLEMENTATION.

*&---------------------------------------------------------------------*
*& AMDP Procedure: get_filtered_data
*&---------------------------------------------------------------------*
  METHOD get_filtered_data
    BY DATABASE PROCEDURE
    FOR HDB
    LANGUAGE SQLSCRIPT
    OPTIONS READ-ONLY                    " Read-only for better performance
    USING ztable_data.                   " Declare used database tables

    /*******************************************************************
     * SQLScript Implementation
     * Note: ABAP types are automatically mapped to SQLScript types
     *******************************************************************/

    -- Declare exit handler for error propagation
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
      -- In AMDP, errors propagate to ABAP as cx_amdp_error
      RESIGNAL;
    END;

    -- Main query with optional filters
    et_result = SELECT
                    id,
                    name,
                    amount,
                    status,
                    created_at
                FROM ztable_data
                WHERE
                    -- Filter by ID if provided
                    ( :iv_filter_id = 0 OR id = :iv_filter_id )
                    -- Filter by status if provided
                    AND ( :iv_status = '' OR status = :iv_status )
                ORDER BY created_at DESC;

    -- Get count
    SELECT COUNT(*) INTO ev_count FROM :et_result;

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& AMDP Table Function: get_data_by_date
*& Can be used in ABAP SELECT: SELECT * FROM zcl_amdp_template=>get_data_by_date(...)
*&---------------------------------------------------------------------*
  METHOD get_data_by_date
    BY DATABASE FUNCTION
    FOR HDB
    LANGUAGE SQLSCRIPT
    OPTIONS READ-ONLY
    USING ztable_data.

    /*******************************************************************
     * Table Function Implementation
     * Note: Must RETURN a table, cannot use OUT parameters
     *******************************************************************/

    RETURN SELECT
               id,
               name,
               amount,
               status,
               created_at
           FROM ztable_data
           WHERE created_at >= TO_TIMESTAMP(:iv_start_date, 'YYYYMMDD')
             AND created_at <= TO_TIMESTAMP(:iv_end_date || '235959', 'YYYYMMDDHH24MISS')
           ORDER BY created_at DESC;

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& AMDP Procedure with Error Handling: update_record
*&---------------------------------------------------------------------*
  METHOD update_record
    BY DATABASE PROCEDURE
    FOR HDB
    LANGUAGE SQLSCRIPT
    " No READ-ONLY - this method performs updates
    USING ztable_data.

    /*******************************************************************
     * DML Operations in AMDP
     * Note: COMMIT/ROLLBACK not allowed in AMDP
     *       Transaction control handled by ABAP layer
     *******************************************************************/

    DECLARE lv_exists INTEGER := 0;

    -- Custom condition for business errors
    DECLARE record_not_found CONDITION FOR SQL_ERROR_CODE 10001;
    DECLARE invalid_amount   CONDITION FOR SQL_ERROR_CODE 10002;

    -- Handler for record not found
    DECLARE EXIT HANDLER FOR record_not_found
    BEGIN
      ev_success := 0;
      ev_error.error_code := 10001;
      ev_error.error_message := 'Record not found: ' || :iv_id;
    END;

    -- Handler for invalid amount
    DECLARE EXIT HANDLER FOR invalid_amount
    BEGIN
      ev_success := 0;
      ev_error.error_code := 10002;
      ev_error.error_message := 'Invalid amount: Must be positive';
    END;

    -- Handler for general SQL exceptions
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
      ev_success := 0;
      ev_error.error_code := ::SQL_ERROR_CODE;
      ev_error.error_message := ::SQL_ERROR_MESSAGE;
    END;

    -- Initialize output
    ev_success := 0;
    ev_error.error_code := 0;
    ev_error.error_message := '';

    -- Validate amount
    IF :iv_new_amount < 0 THEN
      SIGNAL invalid_amount;
    END IF;

    -- Check if record exists
    SELECT COUNT(*) INTO lv_exists
    FROM ztable_data
    WHERE id = :iv_id;

    IF :lv_exists = 0 THEN
      SIGNAL record_not_found;
    END IF;

    -- Perform update
    UPDATE ztable_data
    SET amount = :iv_new_amount,
        modified_at = CURRENT_TIMESTAMP
    WHERE id = :iv_id;

    -- Success
    ev_success := 1;

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Helper Method (Not AMDP)
*&---------------------------------------------------------------------*
  METHOD validate_input.
    rv_valid = COND #( WHEN iv_id > 0 THEN abap_true ELSE abap_false ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Example Usage in ABAP Program
*----------------------------------------------------------------------*
* REPORT z_test_amdp.
*
* DATA: lt_result TYPE zcl_amdp_template=>tt_result,
*       lv_count  TYPE i,
*       ls_error  TYPE zcl_amdp_template=>ty_error,
*       lv_success TYPE i.
*
* " Call AMDP Procedure
* TRY.
*     zcl_amdp_template=>get_filtered_data(
*       EXPORTING
*         iv_filter_id = 100
*         iv_status    = 'ACTIVE'
*       IMPORTING
*         et_result    = lt_result
*         ev_count     = lv_count
*     ).
*     WRITE: / 'Found', lv_count, 'records'.
*   CATCH cx_amdp_error INTO DATA(lx_amdp).
*     WRITE: / 'AMDP Error:', lx_amdp->get_text( ).
* ENDTRY.
*
* " Use AMDP Table Function in SELECT
* SELECT * FROM zcl_amdp_template=>get_data_by_date(
*            iv_start_date = '20250101',
*            iv_end_date   = '20251231'
*          ) INTO TABLE @lt_result.
*
* " Call AMDP with error handling
* zcl_amdp_template=>update_record(
*   EXPORTING
*     iv_id         = 100
*     iv_new_amount = '1500.00'
*   IMPORTING
*     ev_success    = lv_success
*     ev_error      = ls_error
* ).
*
* IF lv_success = 1.
*   WRITE: / 'Update successful'.
* ELSE.
*   WRITE: / 'Error:', ls_error-error_code, ls_error-error_message.
* ENDIF.
