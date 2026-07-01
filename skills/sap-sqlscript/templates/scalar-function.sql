/**
 * Scalar User-Defined Function (Scalar UDF) Template
 *
 * Production-ready template for SQLScript scalar functions with:
 * - Type-safe return values
 * - NULL handling patterns
 * - Inline validation using CASE expressions
 * - Performance considerations
 *
 * Note: Scalar UDFs return a single value and can be used in
 *       SELECT lists, WHERE clauses, and other SQL expressions.
 *
 * @version 2.1.0
 * @last_updated 2025-12-27
 */

/**
 * Example 1: String Processing Function
 * Formats a full name from components with proper NULL handling
 */
CREATE OR REPLACE FUNCTION "<SCHEMA>"."FORMAT_FULL_NAME"
(
    iv_first_name   NVARCHAR(100),
    iv_middle_name  NVARCHAR(100),
    iv_last_name    NVARCHAR(100),
    iv_suffix       NVARCHAR(20) DEFAULT ''
)
RETURNS NVARCHAR(400)
LANGUAGE SQLSCRIPT
DETERMINISTIC              -- Same inputs always produce same output (enables caching)
SQL SECURITY INVOKER
AS
BEGIN
    /*******************************************************************
     * NULL Handling: Return NULL if required fields are NULL
     * Use COALESCE and NULLIF for safe string operations
     *******************************************************************/

    DECLARE lv_result NVARCHAR(400);

    -- Return NULL if both first and last name are NULL/empty
    IF COALESCE(TRIM(:iv_first_name), '') = '' AND COALESCE(TRIM(:iv_last_name), '') = '' THEN
        RETURN NULL;
    END IF;

    -- Build full name with proper spacing
    lv_result := TRIM(
        COALESCE(TRIM(:iv_first_name), '') ||
        CASE
            WHEN COALESCE(TRIM(:iv_middle_name), '') != ''
            THEN ' ' || TRIM(:iv_middle_name)
            ELSE ''
        END ||
        CASE
            WHEN COALESCE(TRIM(:iv_last_name), '') != ''
            THEN ' ' || TRIM(:iv_last_name)
            ELSE ''
        END ||
        CASE
            WHEN COALESCE(TRIM(:iv_suffix), '') != ''
            THEN ', ' || TRIM(:iv_suffix)
            ELSE ''
        END
    );

    RETURN :lv_result;

END;

/**
 * Example 2: Numeric Calculation Function
 * Calculates compound interest with validation
 */
CREATE OR REPLACE FUNCTION "<SCHEMA>"."CALCULATE_COMPOUND_INTEREST"
(
    iv_principal    DECIMAL(15,2),      -- Initial amount
    iv_rate         DECIMAL(5,4),       -- Annual interest rate (e.g., 0.0525 for 5.25%)
    iv_periods      INTEGER,            -- Number of compounding periods
    iv_compounds    INTEGER DEFAULT 12  -- Compounds per year (12 = monthly)
)
RETURNS DECIMAL(15,2)
LANGUAGE SQLSCRIPT
DETERMINISTIC
SQL SECURITY INVOKER
AS
BEGIN
    /*******************************************************************
     * Formula: A = P(1 + r/n)^(periods)
     * Where:
     *   A = Final amount
     *   P = Principal (iv_principal)
     *   r = Annual interest rate (iv_rate)
     *   n = Compounds per year (iv_compounds)
     *   periods = Total number of compounding periods (iv_periods = n*t)
     *            e.g., 60 for 5 years of monthly compounding (12*5)
     *                 or 60 for 60 months of monthly compounding
     *******************************************************************/

    DECLARE lv_result DECIMAL(15,2);

    -- Validation: Return NULL for invalid inputs
    IF :iv_principal IS NULL OR :iv_principal <= 0 THEN
        RETURN NULL;
    END IF;

    IF :iv_rate IS NULL OR :iv_rate < 0 THEN
        RETURN NULL;
    END IF;

    IF :iv_periods IS NULL OR :iv_periods < 0 THEN
        RETURN NULL;
    END IF;

    IF :iv_compounds IS NULL OR :iv_compounds <= 0 THEN
        RETURN NULL;
    END IF;

    -- Calculate compound interest
    lv_result := ROUND(
        :iv_principal * POWER(
            1 + (:iv_rate / :iv_compounds),
            :iv_periods
        ),
        2
    );

    RETURN :lv_result;

END;

/**
 * Example 3: Date Utility Function
 * Returns business days between two dates (excludes weekends)
 */
CREATE OR REPLACE FUNCTION "<SCHEMA>"."BUSINESS_DAYS_BETWEEN"
(
    iv_start_date   DATE,
    iv_end_date     DATE
)
RETURNS INTEGER
LANGUAGE SQLSCRIPT
DETERMINISTIC
SQL SECURITY INVOKER
AS
BEGIN
    DECLARE lv_days INTEGER := 0;
    DECLARE lv_current DATE;
    DECLARE lv_total_days INTEGER;

    -- Handle NULL inputs
    IF :iv_start_date IS NULL OR :iv_end_date IS NULL THEN
        RETURN NULL;
    END IF;

    -- Handle reversed dates
    IF :iv_start_date > :iv_end_date THEN
        RETURN -1 * "<SCHEMA>"."BUSINESS_DAYS_BETWEEN"(:iv_end_date, :iv_start_date);
    END IF;

    -- Calculate using set-based approach for better performance
    SELECT COUNT(*) INTO lv_days
    FROM (
        SELECT GENERATED_PERIOD_START AS day_date
        FROM SERIES_GENERATE_DATE('INTERVAL 1 DAY', :iv_start_date, ADD_DAYS(:iv_end_date, 1))
    )
    WHERE WEEKDAY(day_date) NOT IN (5, 6);  -- 5 = Saturday, 6 = Sunday

    RETURN :lv_days;

END;

/**
 * Example 4: Status/Enum Mapping Function
 * Converts status codes to human-readable labels
 */
CREATE OR REPLACE FUNCTION "<SCHEMA>"."GET_STATUS_LABEL"
(
    iv_status_code  NVARCHAR(10),
    iv_language     NVARCHAR(2) DEFAULT 'EN'
)
RETURNS NVARCHAR(100)
LANGUAGE SQLSCRIPT
DETERMINISTIC
SQL SECURITY INVOKER
AS
BEGIN
    /*******************************************************************
     * Use CASE expression for status mapping
     * Supports multiple languages
     *******************************************************************/

    RETURN
        CASE UPPER(:iv_language)
            WHEN 'EN' THEN
                CASE UPPER(:iv_status_code)
                    WHEN 'A' THEN 'Active'
                    WHEN 'I' THEN 'Inactive'
                    WHEN 'P' THEN 'Pending'
                    WHEN 'C' THEN 'Completed'
                    WHEN 'X' THEN 'Cancelled'
                    WHEN 'E' THEN 'Error'
                    ELSE 'Unknown'
                END
            WHEN 'DE' THEN
                CASE UPPER(:iv_status_code)
                    WHEN 'A' THEN 'Aktiv'
                    WHEN 'I' THEN 'Inaktiv'
                    WHEN 'P' THEN 'Ausstehend'
                    WHEN 'C' THEN 'Abgeschlossen'
                    WHEN 'X' THEN 'Storniert'
                    WHEN 'E' THEN 'Fehler'
                    ELSE 'Unbekannt'
                END
            ELSE
                CASE UPPER(:iv_status_code)
                    WHEN 'A' THEN 'Active'
                    WHEN 'I' THEN 'Inactive'
                    WHEN 'P' THEN 'Pending'
                    WHEN 'C' THEN 'Completed'
                    WHEN 'X' THEN 'Cancelled'
                    WHEN 'E' THEN 'Error'
                    ELSE 'Unknown'
                END
        END;

END;

/*
 * Example Usage:
 *
 * -- Format name
 * SELECT "<SCHEMA>"."FORMAT_FULL_NAME"('John', 'Q', 'Public', 'Jr.') FROM DUMMY;
 * -- Result: 'John Q Public, Jr.'
 *
 * -- Calculate interest
 * SELECT "<SCHEMA>"."CALCULATE_COMPOUND_INTEREST"(10000, 0.05, 60, 12) FROM DUMMY;
 * -- Result: 12833.59 (5% for 60 months compounded monthly)
 *
 * -- Business days
 * SELECT "<SCHEMA>"."BUSINESS_DAYS_BETWEEN"('2025-01-01', '2025-01-31') FROM DUMMY;
 * -- Result: 23
 *
 * -- Status label with language
 * SELECT "<SCHEMA>"."GET_STATUS_LABEL"('P', 'DE') FROM DUMMY;
 * -- Result: 'Ausstehend'
 *
 * -- Use in SELECT
 * SELECT
 *     order_id,
 *     "<SCHEMA>"."GET_STATUS_LABEL"(status, 'EN') AS status_text,
 *     "<SCHEMA>"."FORMAT_FULL_NAME"(first_name, NULL, last_name, '') AS customer_name
 * FROM "<SCHEMA>"."ORDERS";
 */
