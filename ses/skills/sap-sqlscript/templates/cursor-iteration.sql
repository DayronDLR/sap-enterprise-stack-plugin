/**
 * Cursor Iteration Pattern Templates
 *
 * Production-ready templates for SQLScript cursor operations with:
 * - Proper open/fetch/close lifecycle
 * - Error handling for cursor states
 * - FOR loop alternative (simpler syntax)
 * - Performance considerations
 *
 * WARNING: Cursors bypass the database optimizer and process rows sequentially.
 * Use set-based operations whenever possible. Cursors are appropriate for:
 * - Complex row-by-row validation that cannot be expressed in SQL
 * - Calling external procedures for each row
 * - Scenarios requiring sequential processing order
 *
 * @version 2.1.0
 * @last_updated 2025-12-27
 */

/**
 * Pattern 1: Classic Cursor with FETCH INTO
 * Use when you need explicit control over cursor lifecycle
 */
CREATE OR REPLACE PROCEDURE "<SCHEMA>"."CURSOR_CLASSIC_PATTERN"
(
    IN  iv_category     NVARCHAR(50),
    OUT ev_processed    INTEGER,
    OUT ev_errors       INTEGER,
    OUT et_results      TABLE (
        id              INTEGER,
        status          NVARCHAR(20),
        message         NVARCHAR(200)
    )
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
BEGIN
    /*******************************************************************
     * Variable Declarations
     *******************************************************************/
    DECLARE lv_id           INTEGER;
    DECLARE lv_name         NVARCHAR(100);
    DECLARE lv_amount       DECIMAL(15,2);
    DECLARE lv_status       NVARCHAR(20);
    DECLARE lv_message      NVARCHAR(200);
    DECLARE lv_row_count    INTEGER := 0;
    DECLARE lv_error_count  INTEGER := 0;

    -- Temporary table for results
    DECLARE lt_results TABLE (
        id      INTEGER,
        status  NVARCHAR(20),
        message NVARCHAR(200)
    );

    /*******************************************************************
     * Cursor Declaration
     * Can include parameters, joins, and complex conditions
     *******************************************************************/
    DECLARE CURSOR cur_items FOR
        SELECT
            id,
            name,
            amount
        FROM "<SCHEMA>"."ITEMS"
        WHERE category = :iv_category
          AND status = 'PENDING'
        ORDER BY id
        FOR UPDATE;  -- Lock rows if updating

    /*******************************************************************
     * Error Handler for Cursor Operations
     *******************************************************************/
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Always close cursor on error
        IF cur_items::ISOPEN THEN
            CLOSE cur_items;
        END IF;

        ev_processed := :lv_row_count;
        ev_errors := :lv_error_count + 1;
        et_results = SELECT * FROM :lt_results;
    END;

    /*******************************************************************
     * Cursor Processing Pattern
     *******************************************************************/

    -- Open cursor
    OPEN cur_items;

    -- First fetch
    FETCH cur_items INTO lv_id, lv_name, lv_amount;

    -- Process loop using ::NOTFOUND
    WHILE NOT cur_items::NOTFOUND DO

        -- Initialize row status
        lv_status := 'SUCCESS';
        lv_message := '';

        -- Process each row (example: validation and update)
        BEGIN
            -- Row-level error handler
            DECLARE EXIT HANDLER FOR SQLEXCEPTION
            BEGIN
                lv_status := 'ERROR';
                lv_message := 'Error [' || ::SQL_ERROR_CODE || ']: ' || ::SQL_ERROR_MESSAGE;
                lv_error_count := :lv_error_count + 1;
            END;

            -- Business logic for each row
            IF :lv_amount <= 0 THEN
                lv_status := 'SKIPPED';
                lv_message := 'Invalid amount: ' || :lv_amount;
            ELSE
                -- Example: Update the row
                UPDATE "<SCHEMA>"."ITEMS"
                SET status = 'PROCESSED',
                    processed_at = CURRENT_TIMESTAMP
                WHERE CURRENT OF cur_items;  -- Update current cursor row

                lv_message := 'Processed successfully. Amount: ' || :lv_amount;
            END IF;
        END;

        -- Record result
        INSERT INTO :lt_results VALUES (:lv_id, :lv_status, :lv_message);
        lv_row_count := :lv_row_count + 1;

        -- Fetch next row
        FETCH cur_items INTO lv_id, lv_name, lv_amount;

    END WHILE;

    -- Close cursor (important!)
    CLOSE cur_items;

    /*******************************************************************
     * Output Results
     *******************************************************************/
    ev_processed := :lv_row_count;
    ev_errors := :lv_error_count;
    et_results = SELECT * FROM :lt_results;

END;

/**
 * Pattern 2: FOR Loop Cursor (Simplified Syntax)
 * Automatically handles OPEN, FETCH, CLOSE
 * Recommended for most cursor use cases
 */
CREATE OR REPLACE PROCEDURE "<SCHEMA>"."CURSOR_FOR_LOOP_PATTERN"
(
    IN  iv_department   NVARCHAR(50),
    OUT ev_total        DECIMAL(15,2),
    OUT ev_count        INTEGER
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
READS SQL DATA
AS
BEGIN
    /*******************************************************************
     * Local Variables
     *******************************************************************/
    DECLARE lv_running_total DECIMAL(15,2) := 0;
    DECLARE lv_record_count  INTEGER := 0;

    /*******************************************************************
     * FOR Loop with Inline Cursor
     * Syntax: FOR <row_var> AS <cursor_name> [(<params>)] DO
     *
     * Benefits:
     * - No explicit OPEN/FETCH/CLOSE
     * - Automatic cleanup on exit
     * - Cleaner syntax
     *******************************************************************/

    FOR row AS cur_employees (
        SELECT
            employee_id,
            name,
            salary,
            bonus
        FROM "<SCHEMA>"."EMPLOYEES"
        WHERE department = :iv_department
          AND active = 1
        ORDER BY employee_id
    ) DO
        -- Access columns using row.<column_name>
        lv_running_total := :lv_running_total + row.salary + COALESCE(row.bonus, 0);
        lv_record_count := :lv_record_count + 1;

        -- Can perform DML operations
        -- UPDATE "<SCHEMA>"."EMPLOYEES"
        -- SET last_processed = CURRENT_TIMESTAMP
        -- WHERE employee_id = row.employee_id;

    END FOR;

    /*******************************************************************
     * Output
     *******************************************************************/
    ev_total := :lv_running_total;
    ev_count := :lv_record_count;

END;

/**
 * Pattern 3: Nested Cursors
 * Use sparingly - performance impact is multiplicative
 */
CREATE OR REPLACE PROCEDURE "<SCHEMA>"."CURSOR_NESTED_PATTERN"
(
    OUT et_summary TABLE (
        parent_id       INTEGER,
        parent_name     NVARCHAR(100),
        child_count     INTEGER,
        total_value     DECIMAL(15,2)
    )
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
READS SQL DATA
AS
BEGIN
    DECLARE lt_summary TABLE (
        parent_id   INTEGER,
        parent_name NVARCHAR(100),
        child_count INTEGER,
        total_value DECIMAL(15,2)
    );

    /*******************************************************************
     * Outer Cursor: Parents
     *******************************************************************/
    FOR parent_row AS cur_parents (
        SELECT id, name
        FROM "<SCHEMA>"."PARENT_TABLE"
        WHERE active = 1
        ORDER BY id
    ) DO

        DECLARE lv_child_count  INTEGER := 0;
        DECLARE lv_child_total  DECIMAL(15,2) := 0;

        /***************************************************************
         * Inner Cursor: Children of Current Parent
         ***************************************************************/
        FOR child_row AS cur_children (
            SELECT value
            FROM "<SCHEMA>"."CHILD_TABLE"
            WHERE parent_id = parent_row.id
        ) DO
            lv_child_count := :lv_child_count + 1;
            lv_child_total := :lv_child_total + child_row.value;
        END FOR;

        -- Record parent summary
        INSERT INTO :lt_summary VALUES (
            parent_row.id,
            parent_row.name,
            :lv_child_count,
            :lv_child_total
        );

    END FOR;

    et_summary = SELECT * FROM :lt_summary;

END;

/**
 * Pattern 4: Set-Based Alternative (PREFERRED)
 * Same result as nested cursors but using JOINs and GROUP BY
 */
CREATE OR REPLACE PROCEDURE "<SCHEMA>"."SET_BASED_ALTERNATIVE"
(
    OUT et_summary TABLE (
        parent_id       INTEGER,
        parent_name     NVARCHAR(100),
        child_count     INTEGER,
        total_value     DECIMAL(15,2)
    )
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
READS SQL DATA
AS
BEGIN
    /*******************************************************************
     * Set-Based Approach - MUCH faster than nested cursors
     * Uses JOIN and GROUP BY instead of row-by-row processing
     *******************************************************************/

    et_summary = SELECT
                     p.id AS parent_id,
                     p.name AS parent_name,
                     COUNT(c.id) AS child_count,
                     COALESCE(SUM(c.value), 0) AS total_value
                 FROM "<SCHEMA>"."PARENT_TABLE" p
                 LEFT JOIN "<SCHEMA>"."CHILD_TABLE" c
                     ON p.id = c.parent_id
                 WHERE p.active = 1
                 GROUP BY p.id, p.name
                 ORDER BY p.id;

END;

/*
 * Cursor Attribute Reference:
 *
 * cursor_name::ISOPEN    - TRUE if cursor is open
 * cursor_name::NOTFOUND  - TRUE after FETCH finds no more rows
 * cursor_name::ROWCOUNT  - Number of rows fetched so far
 *
 * Performance Guidelines:
 * 1. Always prefer set-based operations over cursors
 * 2. If cursor is necessary, use FOR loop syntax
 * 3. Limit cursor result set with WHERE conditions
 * 4. Index columns used in cursor WHERE clause
 * 5. Avoid nested cursors (exponential performance impact)
 * 6. Process in batches for large datasets
 */
