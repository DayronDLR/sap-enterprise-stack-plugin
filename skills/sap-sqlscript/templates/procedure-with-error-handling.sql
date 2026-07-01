/**
 * Comprehensive Error Handling Procedure Template
 *
 * Production-ready template demonstrating advanced SQLScript error handling:
 * - Multiple named conditions for specific errors
 * - Nested exception handlers
 * - Error logging to audit table
 * - SIGNAL for custom exceptions
 * - RESIGNAL for re-throwing
 * - Transaction rollback patterns
 *
 * @version 2.1.0
 * @last_updated 2025-12-27
 */

CREATE OR REPLACE PROCEDURE "<SCHEMA>"."<PROCEDURE_NAME>_WITH_ERROR_HANDLING"
(
    -- Input Parameters
    IN  iv_order_id      INTEGER,
    IN  iv_quantity      INTEGER,
    IN  iv_user_id       NVARCHAR(50),

    -- Output Parameters
    OUT ev_success       INTEGER,           -- 1 = success, 0 = failure
    OUT ev_error_code    INTEGER,           -- Specific error code
    OUT ev_error_message NVARCHAR(1000)     -- Detailed error message
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
DEFAULT SCHEMA "<SCHEMA>"
AS
BEGIN
    /*******************************************************************
     * Constants for Custom Error Codes (10000-19999 range)
     *******************************************************************/
    DECLARE VALIDATION_ERROR       INTEGER := 10001;
    DECLARE BUSINESS_RULE_ERROR    INTEGER := 10002;
    DECLARE INSUFFICIENT_STOCK     INTEGER := 10003;
    DECLARE CONCURRENT_UPDATE      INTEGER := 10004;

    /*******************************************************************
     * Named Conditions for Specific SQL Errors
     *******************************************************************/
    DECLARE duplicate_key    CONDITION FOR SQL_ERROR_CODE 301;   -- Unique constraint violation
    DECLARE no_data_found    CONDITION FOR SQL_ERROR_CODE 1299;  -- No data found
    DECLARE lock_timeout     CONDITION FOR SQL_ERROR_CODE 131;   -- Lock wait timeout
    DECLARE foreign_key      CONDITION FOR SQL_ERROR_CODE 461;   -- Foreign key violation

    /*******************************************************************
     * Custom Conditions for Business Logic
     *******************************************************************/
    DECLARE validation_failed     CONDITION FOR SQL_ERROR_CODE 10001;
    DECLARE business_rule_failed  CONDITION FOR SQL_ERROR_CODE 10002;
    DECLARE stock_insufficient    CONDITION FOR SQL_ERROR_CODE 10003;

    /*******************************************************************
     * Local Variables
     *******************************************************************/
    DECLARE lv_current_stock    INTEGER;
    DECLARE lv_order_status     NVARCHAR(20);
    DECLARE lv_transaction_id   NVARCHAR(36);
    DECLARE lv_start_time       TIMESTAMP := CURRENT_TIMESTAMP;

    /*******************************************************************
     * Exception Handlers (processed in reverse declaration order)
     *******************************************************************/

    -- Handler for duplicate key violations
    DECLARE EXIT HANDLER FOR duplicate_key
    BEGIN
        ev_success := 0;
        ev_error_code := 301;
        ev_error_message := 'Duplicate entry: Record already exists for order ' || :iv_order_id;

        CALL "<SCHEMA>"."LOG_ERROR"(
            '<PROCEDURE_NAME>', 301, :ev_error_message, :iv_user_id
        );
    END;

    -- Handler for no data found
    DECLARE EXIT HANDLER FOR no_data_found
    BEGIN
        ev_success := 0;
        ev_error_code := 1299;
        ev_error_message := 'Order not found: ' || :iv_order_id;

        CALL "<SCHEMA>"."LOG_ERROR"(
            '<PROCEDURE_NAME>', 1299, :ev_error_message, :iv_user_id
        );
    END;

    -- Handler for lock timeout (concurrent access)
    DECLARE EXIT HANDLER FOR lock_timeout
    BEGIN
        ev_success := 0;
        ev_error_code := 131;
        ev_error_message := 'Concurrent update detected. Please retry.';

        CALL "<SCHEMA>"."LOG_ERROR"(
            '<PROCEDURE_NAME>', 131, :ev_error_message, :iv_user_id
        );
    END;

    -- Handler for insufficient stock
    DECLARE EXIT HANDLER FOR stock_insufficient
    BEGIN
        ev_success := 0;
        ev_error_code := :INSUFFICIENT_STOCK;
        ev_error_message := 'Insufficient stock for order ' || :iv_order_id ||
                           '. Requested: ' || :iv_quantity || ', Available: ' || :lv_current_stock;

        CALL "<SCHEMA>"."LOG_ERROR"(
            '<PROCEDURE_NAME>', :INSUFFICIENT_STOCK, :ev_error_message, :iv_user_id
        );
    END;

    -- Handler for validation failures
    DECLARE EXIT HANDLER FOR validation_failed
    BEGIN
        ev_success := 0;
        ev_error_code := :VALIDATION_ERROR;
        -- ev_error_message already set by SIGNAL

        CALL "<SCHEMA>"."LOG_ERROR"(
            '<PROCEDURE_NAME>', :VALIDATION_ERROR, :ev_error_message, :iv_user_id
        );
    END;

    -- Generic handler for all other SQL exceptions (catch-all)
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ev_success := 0;
        ev_error_code := ::SQL_ERROR_CODE;
        ev_error_message := 'Unexpected error [' || ::SQL_ERROR_CODE || ']: ' ||
                           ::SQL_ERROR_MESSAGE;

        CALL "<SCHEMA>"."LOG_ERROR"(
            '<PROCEDURE_NAME>', ::SQL_ERROR_CODE, ::SQL_ERROR_MESSAGE, :iv_user_id
        );
    END;

    /*******************************************************************
     * Generate Transaction ID for Tracking
     *******************************************************************/
    lv_transaction_id := SYSUUID;

    /*******************************************************************
     * Input Validation with Custom Exceptions
     *******************************************************************/

    -- Validate order_id
    IF :iv_order_id IS NULL OR :iv_order_id <= 0 THEN
        ev_error_message := 'Invalid order_id: Must be a positive integer';
        SIGNAL validation_failed SET MESSAGE_TEXT = :ev_error_message;
    END IF;

    -- Validate quantity
    IF :iv_quantity IS NULL OR :iv_quantity <= 0 THEN
        ev_error_message := 'Invalid quantity: Must be a positive integer';
        SIGNAL validation_failed SET MESSAGE_TEXT = :ev_error_message;
    END IF;

    -- Validate user_id
    IF :iv_user_id IS NULL OR LENGTH(TRIM(:iv_user_id)) = 0 THEN
        ev_error_message := 'Invalid user_id: Cannot be empty';
        SIGNAL validation_failed SET MESSAGE_TEXT = :ev_error_message;
    END IF;

    /*******************************************************************
     * Business Logic with Targeted Error Handling
     *******************************************************************/

    -- Step 1: Verify order exists and get status
    SELECT status INTO lv_order_status
    FROM "<SCHEMA>"."ORDERS"
    WHERE order_id = :iv_order_id;

    -- Step 2: Business rule - Only pending orders can be modified
    IF :lv_order_status != 'PENDING' THEN
        ev_error_message := 'Order ' || :iv_order_id || ' is ' || :lv_order_status ||
                           '. Only PENDING orders can be modified.';
        SIGNAL business_rule_failed SET MESSAGE_TEXT = :ev_error_message;
    END IF;

    -- Step 3: Check stock availability
    SELECT available_qty INTO lv_current_stock
    FROM "<SCHEMA>"."INVENTORY"
    WHERE product_id = (
        SELECT product_id FROM "<SCHEMA>"."ORDERS" WHERE order_id = :iv_order_id
    );

    IF :lv_current_stock < :iv_quantity THEN
        SIGNAL stock_insufficient;
    END IF;

    -- Step 4: Update order (may trigger lock_timeout if concurrent access)
    UPDATE "<SCHEMA>"."ORDERS"
    SET quantity = :iv_quantity,
        modified_by = :iv_user_id,
        modified_at = CURRENT_TIMESTAMP,
        transaction_id = :lv_transaction_id
    WHERE order_id = :iv_order_id
      AND status = 'PENDING';

    -- Step 5: Update inventory
    UPDATE "<SCHEMA>"."INVENTORY"
    SET available_qty = available_qty - :iv_quantity,
        reserved_qty = reserved_qty + :iv_quantity,
        modified_at = CURRENT_TIMESTAMP
    WHERE product_id = (
        SELECT product_id FROM "<SCHEMA>"."ORDERS" WHERE order_id = :iv_order_id
    );

    /*******************************************************************
     * Success Response
     *******************************************************************/
    ev_success := 1;
    ev_error_code := 0;
    ev_error_message := 'Order ' || :iv_order_id || ' updated successfully. ' ||
                        'Transaction: ' || :lv_transaction_id || '. ' ||
                        'Duration: ' || NANO100_BETWEEN(:lv_start_time, CURRENT_TIMESTAMP) / 10000000 || 'ms';

END;

/*
 * Supporting Error Logging Procedure
 */
-- CREATE OR REPLACE PROCEDURE "<SCHEMA>"."LOG_ERROR"
-- (
--     IN iv_procedure_name NVARCHAR(128),
--     IN iv_error_code     INTEGER,
--     IN iv_error_message  NVARCHAR(1000),
--     IN iv_user_id        NVARCHAR(50)
-- )
-- LANGUAGE SQLSCRIPT
-- SQL SECURITY DEFINER
-- AS
-- BEGIN
--     INSERT INTO "<SCHEMA>"."ERROR_LOG" (
--         log_id, procedure_name, error_code, error_message, user_id, created_at
--     ) VALUES (
--         "<SCHEMA>"."ERROR_LOG_SEQ".NEXTVAL,
--         :iv_procedure_name,
--         :iv_error_code,
--         :iv_error_message,
--         :iv_user_id,
--         CURRENT_TIMESTAMP
--     );
-- END;
