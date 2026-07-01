/**
 * Table User-Defined Function (Table UDF) Template
 *
 * Production-ready template for SQLScript table functions with:
 * - Parameter validation with CASE expressions (no IF in functions)
 * - Proper READS SQL DATA declaration
 * - Efficient set-based operations
 * - Documentation and usage examples
 *
 * Note: Table UDFs cannot perform DML (INSERT/UPDATE/DELETE)
 *       and must return a table type.
 *
 * @version 2.1.0
 * @last_updated 2025-12-27
 */

CREATE OR REPLACE FUNCTION "<SCHEMA>"."<FUNCTION_NAME>_TABLE_UDF"
(
    -- Input Parameters (all IN by default, cannot have OUT params)
    iv_start_date   DATE,
    iv_end_date     DATE,
    iv_category     NVARCHAR(50) DEFAULT '',    -- Optional filter
    iv_limit        INTEGER DEFAULT 1000        -- Row limit for safety
)
RETURNS TABLE (
    -- Return column definitions
    record_id       INTEGER,
    category_name   NVARCHAR(100),
    metric_value    DECIMAL(15,2),
    record_date     DATE,
    status          NVARCHAR(20),
    row_rank        INTEGER
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
READS SQL DATA                    -- Required for table functions
AS
BEGIN
    /*******************************************************************
     * Note: Table functions cannot use:
     * - IF/ELSE statements (use CASE WHEN instead)
     * - DECLARE for variables (inline expressions only)
     * - DML statements (INSERT, UPDATE, DELETE)
     * - Exception handlers in the main body
     *
     * They CAN use:
     * - Complex SELECT statements
     * - JOINs, subqueries, CTEs
     * - Window functions
     * - CASE expressions for conditional logic
     *******************************************************************/

    /*******************************************************************
     * Main Logic with Inline Validation using CASE
     *******************************************************************/

    RETURN
        SELECT
            t.id AS record_id,
            c.name AS category_name,
            t.value AS metric_value,
            t.record_date,
            CASE
                WHEN t.value >= 1000 THEN 'HIGH'
                WHEN t.value >= 100 THEN 'MEDIUM'
                ELSE 'LOW'
            END AS status,
            ROW_NUMBER() OVER (
                PARTITION BY c.name
                ORDER BY t.value DESC
            ) AS row_rank
        FROM "<SCHEMA>"."TRANSACTIONS" t
        INNER JOIN "<SCHEMA>"."CATEGORIES" c
            ON t.category_id = c.id
        WHERE
            -- Date range validation with COALESCE for NULL handling
            t.record_date >= COALESCE(:iv_start_date, ADD_DAYS(CURRENT_DATE, -30))
            AND t.record_date <= COALESCE(:iv_end_date, CURRENT_DATE)
            -- Optional category filter using CASE
            AND (
                :iv_category = ''
                OR c.name = :iv_category
            )
        ORDER BY t.record_date DESC, t.value DESC
        LIMIT CASE
            WHEN :iv_limit <= 0 THEN 1000
            WHEN :iv_limit > 10000 THEN 10000
            ELSE :iv_limit
        END;

END;

/*
 * Example Usage:
 *
 * -- Basic call with date range
 * SELECT * FROM "<SCHEMA>"."<FUNCTION_NAME>_TABLE_UDF"(
 *     iv_start_date => '2025-01-01',
 *     iv_end_date   => '2025-12-31',
 *     iv_category   => '',
 *     iv_limit      => 100
 * );
 *
 * -- With category filter
 * SELECT * FROM "<SCHEMA>"."<FUNCTION_NAME>_TABLE_UDF"(
 *     iv_start_date => '2025-01-01',
 *     iv_end_date   => '2025-12-31',
 *     iv_category   => 'Electronics',
 *     iv_limit      => 500
 * );
 *
 * -- Using in JOIN
 * -- Note: record_id corresponds to TRANSACTIONS.id (see line 59)
 * SELECT
 *     u.user_name,
 *     f.category_name,
 *     f.metric_value
 * FROM "<SCHEMA>"."USERS" u
 * INNER JOIN "<SCHEMA>"."<FUNCTION_NAME>_TABLE_UDF"(
 *     '2025-01-01', '2025-12-31', '', 1000
 * ) f ON u.id = f.record_id  -- Join on user ID, not category_id
 * WHERE f.row_rank <= 10;
 *
 * -- Alternative: Join through TRANSACTIONS table for clarity
 * SELECT
 *     u.user_name,
 *     f.category_name,
 *     f.metric_value
 * FROM "<SCHEMA>"."USERS" u
 * INNER JOIN "<SCHEMA>"."TRANSACTIONS" t ON u.id = t.user_id
 * INNER JOIN "<SCHEMA>"."<FUNCTION_NAME>_TABLE_UDF"(
 *     '2025-01-01', '2025-12-31', '', 1000
 * ) f ON t.id = f.record_id
 * WHERE f.row_rank <= 10;
 *
 * -- Using in CTE
 * WITH ranked_data AS (
 *     SELECT * FROM "<SCHEMA>"."<FUNCTION_NAME>_TABLE_UDF"(
 *         iv_start_date => ADD_DAYS(CURRENT_DATE, -90),
 *         iv_end_date   => CURRENT_DATE,
 *         iv_category   => 'Sales',
 *         iv_limit      => 500
 *     )
 * )
 * SELECT
 *     category_name,
 *     SUM(metric_value) AS total_value,
 *     COUNT(*) AS record_count
 * FROM ranked_data
 * WHERE row_rank <= 5
 * GROUP BY category_name;
 */

/**
 * Alternative: Table Function with TYPE for Complex Return Structure
 */

-- First create the return type
-- CREATE TYPE "<SCHEMA>"."TT_METRICS_RESULT" AS TABLE (
--     record_id       INTEGER,
--     category_name   NVARCHAR(100),
--     metric_value    DECIMAL(15,2),
--     record_date     DATE,
--     status          NVARCHAR(20),
--     row_rank        INTEGER
-- );

-- Then use it in function
-- CREATE OR REPLACE FUNCTION "<SCHEMA>"."<FUNCTION_NAME>_WITH_TYPE"(
--     iv_start_date DATE,
--     iv_end_date   DATE
-- )
-- RETURNS "<SCHEMA>"."TT_METRICS_RESULT"
-- LANGUAGE SQLSCRIPT
-- READS SQL DATA
-- AS
-- BEGIN
--     RETURN SELECT ... ;
-- END;
