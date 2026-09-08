/**
 * AMDP Procedure SQLScript Template
 *
 * This file contains the SQLScript implementation that goes inside
 * an AMDP method. Use in conjunction with amdp-class.abap template.
 *
 * Key differences from standalone SQLScript:
 * - No CREATE PROCEDURE statement (defined by ABAP method signature)
 * - Parameters mapped from ABAP types
 * - COMMIT/ROLLBACK not allowed
 * - Transaction managed by ABAP layer
 * - Table names must be declared in USING clause
 *
 * @version 2.1.0
 * @last_updated 2025-12-27
 */

/*******************************************************************
 * AMDP Method Signature in ABAP:
 *
 * METHOD process_order
 *   BY DATABASE PROCEDURE
 *   FOR HDB
 *   LANGUAGE SQLSCRIPT
 *   OPTIONS READ-ONLY                    -- Or omit for read-write
 *   USING zorders zorder_items zinventory.
 *
 * Parameters (from ABAP method signature):
 *   iv_order_id     TYPE i              -- Input: Order ID
 *   iv_action       TYPE string         -- Input: Action (APPROVE/REJECT/SHIP)
 *   et_result       TYPE tt_order_line  -- Output: Processed line items
 *   ev_status       TYPE string         -- Output: New order status
 *   ev_message      TYPE string         -- Output: Status message
 *******************************************************************/

/*******************************************************************
 * SQLScript Implementation (Method Body)
 *******************************************************************/

-- Declare custom conditions for AMDP error handling
DECLARE order_not_found    CONDITION FOR SQL_ERROR_CODE 10001;
DECLARE invalid_action     CONDITION FOR SQL_ERROR_CODE 10002;
DECLARE insufficient_stock CONDITION FOR SQL_ERROR_CODE 10003;
DECLARE already_processed  CONDITION FOR SQL_ERROR_CODE 10004;

-- Local variables
DECLARE lv_current_status NVARCHAR(20);
DECLARE lv_product_id     NVARCHAR(40);
DECLARE lv_total_qty      INTEGER;
DECLARE lv_available_qty  INTEGER;

/*******************************************************************
 * Exception Handlers
 * Note: In AMDP, unhandled exceptions propagate to ABAP as cx_amdp_error
 *******************************************************************/

DECLARE EXIT HANDLER FOR order_not_found
BEGIN
    ev_status := 'ERROR';
    ev_message := 'Order ' || :iv_order_id || ' not found';
END;

DECLARE EXIT HANDLER FOR invalid_action
BEGIN
    ev_status := 'ERROR';
    ev_message := 'Invalid action: ' || :iv_action || '. Valid: APPROVE, REJECT, SHIP';
END;

DECLARE EXIT HANDLER FOR insufficient_stock
BEGIN
    ev_status := 'ERROR';
    ev_message := 'Insufficient stock. Required: ' || :lv_total_qty ||
                  ', Available: ' || :lv_available_qty;
END;

DECLARE EXIT HANDLER FOR already_processed
BEGIN
    ev_status := 'ERROR';
    ev_message := 'Order already processed. Current status: ' || :lv_current_status;
END;

DECLARE EXIT HANDLER FOR SQLEXCEPTION
BEGIN
    ev_status := 'ERROR';
    ev_message := 'SQL Error [' || ::SQL_ERROR_CODE || ']: ' || ::SQL_ERROR_MESSAGE;
END;

/*******************************************************************
 * Initialize Output
 *******************************************************************/
ev_status := '';
ev_message := '';

/*******************************************************************
 * Input Validation
 *******************************************************************/

-- Validate order exists
SELECT status INTO lv_current_status
FROM zorders
WHERE order_id = :iv_order_id;

IF :lv_current_status IS NULL THEN
    SIGNAL order_not_found;
END IF;

-- Validate action
IF UPPER(:iv_action) NOT IN ('APPROVE', 'REJECT', 'SHIP') THEN
    SIGNAL invalid_action;
END IF;

-- Check if already in final state
IF :lv_current_status IN ('SHIPPED', 'CANCELLED', 'REJECTED') THEN
    SIGNAL already_processed;
END IF;

/*******************************************************************
 * Business Logic by Action
 *******************************************************************/

CASE UPPER(:iv_action)

    WHEN 'APPROVE' THEN
        -- Can only approve PENDING orders
        IF :lv_current_status != 'PENDING' THEN
            ev_status := 'ERROR';
            ev_message := 'Can only approve PENDING orders';
            RETURN;
        END IF;

        -- Update order status
        UPDATE zorders
        SET status = 'APPROVED',
            approved_at = CURRENT_TIMESTAMP
        WHERE order_id = :iv_order_id;

        ev_status := 'APPROVED';
        ev_message := 'Order ' || :iv_order_id || ' approved successfully';

    WHEN 'REJECT' THEN
        -- Can reject PENDING or APPROVED orders
        IF :lv_current_status NOT IN ('PENDING', 'APPROVED') THEN
            ev_status := 'ERROR';
            ev_message := 'Can only reject PENDING or APPROVED orders';
            RETURN;
        END IF;

        -- Update order status
        UPDATE zorders
        SET status = 'REJECTED',
            rejected_at = CURRENT_TIMESTAMP
        WHERE order_id = :iv_order_id;

        ev_status := 'REJECTED';
        ev_message := 'Order ' || :iv_order_id || ' rejected';

    WHEN 'SHIP' THEN
        -- Can only ship APPROVED orders
        IF :lv_current_status != 'APPROVED' THEN
            ev_status := 'ERROR';
            ev_message := 'Can only ship APPROVED orders';
            RETURN;
        END IF;

        -- Check inventory per product (not total across all products)
        -- This ensures each product has sufficient stock individually
        DECLARE lt_insufficient TABLE (
            product_id      NVARCHAR(40),
            required_qty    INTEGER,
            available_qty   INTEGER
        );

        lt_insufficient = SELECT items.product_id,
                                 items.quantity AS required_qty,
                                 inv.available_qty
                          FROM zorder_items items
                          INNER JOIN zinventory inv
                              ON inv.product_id = items.product_id
                          WHERE items.order_id = :iv_order_id
                            AND inv.available_qty < items.quantity;

        IF NOT IS_EMPTY(:lt_insufficient) THEN
            -- Get first insufficient product for error message
            SELECT product_id, required_qty, available_qty
            INTO lv_product_id, lv_total_qty, lv_available_qty
            FROM :lt_insufficient
            LIMIT 1;
            SIGNAL insufficient_stock;
        END IF;

        -- Deduct inventory
        UPDATE zinventory
        SET available_qty = available_qty - (
            SELECT quantity
            FROM zorder_items
            WHERE order_id = :iv_order_id
              AND product_id = zinventory.product_id
        )
        WHERE product_id IN (
            SELECT product_id
            FROM zorder_items
            WHERE order_id = :iv_order_id
        );

        -- Update order status
        UPDATE zorders
        SET status = 'SHIPPED',
            shipped_at = CURRENT_TIMESTAMP
        WHERE order_id = :iv_order_id;

        ev_status := 'SHIPPED';
        ev_message := 'Order ' || :iv_order_id || ' shipped successfully';

END CASE;

/*******************************************************************
 * Return Order Line Items
 *******************************************************************/
et_result = SELECT
                items.item_id,
                items.product_id,
                items.quantity,
                items.unit_price,
                items.quantity * items.unit_price AS total_price,
                orders.status
            FROM zorder_items items
            INNER JOIN zorders orders
                ON items.order_id = orders.order_id
            WHERE items.order_id = :iv_order_id
            ORDER BY items.item_id;

/*
 * ABAP Type Mapping Reference:
 *
 * ABAP Type          | SQLScript Type
 * -------------------|------------------
 * i                  | INTEGER
 * int8               | BIGINT
 * p (packed)         | DECIMAL
 * f                  | DOUBLE
 * decfloat16/34      | DECIMAL
 * d                  | DATE (as YYYYMMDD string)
 * t                  | TIME (as HHMMSS string)
 * utclong            | TIMESTAMP
 * c, string          | NVARCHAR
 * x, xstring         | VARBINARY
 * abap_bool          | TINYINT
 *
 * Note: ABAP date (d) is passed as string 'YYYYMMDD'
 * Convert with: TO_DATE(:iv_date, 'YYYYMMDD')
 */
