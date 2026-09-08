/**
 * Simple Stored Procedure Template
 *
 * A production-ready template for basic SQLScript procedures with:
 * - Input parameter validation
 * - Proper error handling with EXIT HANDLER
 * - Structured logging
 * - Documentation comments
 *
 * Usage: Replace placeholders (<SCHEMA>, <PROCEDURE_NAME>, etc.) with actual values
 *
 * @version 2.1.0
 * @last_updated 2025-12-27
 */

CREATE OR REPLACE PROCEDURE "<SCHEMA>"."<PROCEDURE_NAME>"
(
    -- Input Parameters
    IN  iv_input_id     INTEGER,                    -- Primary input identifier
    IN  iv_filter_value NVARCHAR(100) DEFAULT '',   -- Optional filter (default empty)

    -- Output Parameters
    OUT ev_success      INTEGER,                    -- 1 = success, 0 = failure
    OUT ev_message      NVARCHAR(500),              -- Status/error message
    OUT et_result       TABLE (                     -- Result set
        id          INTEGER,
        name        NVARCHAR(100),
        created_at  TIMESTAMP
    )
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
DEFAULT SCHEMA "<SCHEMA>"
READS SQL DATA
AS
BEGIN
    /*******************************************************************
     * Variable Declarations
     *******************************************************************/
    DECLARE lv_record_count INTEGER := 0;
    DECLARE lv_start_time   TIMESTAMP := CURRENT_TIMESTAMP;

    /*******************************************************************
     * Exception Handler - Catches all SQL exceptions
     *
     * ::SQL_ERROR_CODE    - Numeric error code
     * ::SQL_ERROR_MESSAGE - Error message text
     *******************************************************************/
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ev_success := 0;
        ev_message := 'Error [' || ::SQL_ERROR_CODE || ']: ' || ::SQL_ERROR_MESSAGE;

        -- Optional: Log error to audit table
        -- INSERT INTO "<SCHEMA>"."ERROR_LOG" (
        --     procedure_name, error_code, error_message, input_params, created_at
        -- ) VALUES (
        --     '<PROCEDURE_NAME>', ::SQL_ERROR_CODE, ::SQL_ERROR_MESSAGE,
        --     'iv_input_id=' || :iv_input_id, CURRENT_TIMESTAMP
        -- );
    END;

    /*******************************************************************
     * Input Validation
     *******************************************************************/
    IF :iv_input_id IS NULL OR :iv_input_id <= 0 THEN
        ev_success := 0;
        ev_message := 'Invalid input: iv_input_id must be a positive integer';
        RETURN;
    END IF;

    /*******************************************************************
     * Main Logic
     *******************************************************************/

    -- Example: Fetch data with optional filter
    IF :iv_filter_value = '' THEN
        et_result = SELECT
                        id,
                        name,
                        created_at
                    FROM "<SCHEMA>"."<SOURCE_TABLE>"
                    WHERE parent_id = :iv_input_id
                    ORDER BY created_at DESC;
    ELSE
        et_result = SELECT
                        id,
                        name,
                        created_at
                    FROM "<SCHEMA>"."<SOURCE_TABLE>"
                    WHERE parent_id = :iv_input_id
                      AND name LIKE '%' || :iv_filter_value || '%'
                    ORDER BY created_at DESC;
    END IF;

    -- Get record count for logging
    SELECT COUNT(*) INTO lv_record_count FROM :et_result;

    /*******************************************************************
     * Success Response
     *******************************************************************/
    ev_success := 1;
    ev_message := 'Success: Retrieved ' || :lv_record_count || ' records in ' ||
                  NANO100_BETWEEN(:lv_start_time, CURRENT_TIMESTAMP) / 10000 || 'ms';

END;

/*
 * Example Call:
 *
 * CALL "<SCHEMA>"."<PROCEDURE_NAME>"(
 *     iv_input_id     => 100,
 *     iv_filter_value => 'test',
 *     ev_success      => ?,
 *     ev_message      => ?,
 *     et_result       => ?
 * );
 */
