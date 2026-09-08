/**
 * Bulk Operations Pattern Templates
 *
 * Production-ready templates for high-performance SQLScript bulk operations:
 * - Set-based INSERT, UPDATE, DELETE
 * - MERGE (UPSERT) operations
 * - Batch processing with chunking
 * - Transaction management patterns
 * - Performance optimization techniques
 *
 * @version 2.1.0
 * @last_updated 2025-12-27
 */

/**
 * Pattern 1: Bulk INSERT from Table Variable
 * Inserts multiple rows in a single operation
 */
CREATE OR REPLACE PROCEDURE "<SCHEMA>"."BULK_INSERT_PATTERN"
(
    IN  it_data         TABLE (
        id              INTEGER,
        name            NVARCHAR(100),
        category        NVARCHAR(50),
        amount          DECIMAL(15,2)
    ),
    OUT ev_inserted     INTEGER,
    OUT ev_message      NVARCHAR(500)
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
BEGIN
    DECLARE lv_count INTEGER := 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ev_inserted := 0;
        ev_message := 'Insert failed [' || ::SQL_ERROR_CODE || ']: ' || ::SQL_ERROR_MESSAGE;
    END;

    /*******************************************************************
     * Get input count
     *******************************************************************/
    SELECT COUNT(*) INTO lv_count FROM :it_data;

    IF :lv_count = 0 THEN
        ev_inserted := 0;
        ev_message := 'No data to insert';
        RETURN;
    END IF;

    /*******************************************************************
     * Bulk INSERT - Single statement for all rows
     * Much faster than row-by-row INSERT in a loop
     *******************************************************************/
    INSERT INTO "<SCHEMA>"."TARGET_TABLE" (
        id, name, category, amount, created_at
    )
    SELECT
        id,
        name,
        category,
        amount,
        CURRENT_TIMESTAMP
    FROM :it_data;

    ev_inserted := ::ROWCOUNT;
    ev_message := 'Successfully inserted ' || :ev_inserted || ' records';

END;

/**
 * Pattern 2: Bulk UPDATE from Table Variable
 * Updates multiple rows in a single operation
 */
CREATE OR REPLACE PROCEDURE "<SCHEMA>"."BULK_UPDATE_PATTERN"
(
    IN  it_updates      TABLE (
        id              INTEGER,
        new_amount      DECIMAL(15,2),
        new_status      NVARCHAR(20)
    ),
    OUT ev_updated      INTEGER,
    OUT ev_message      NVARCHAR(500)
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
BEGIN
    DECLARE lv_count INTEGER := 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ev_updated := 0;
        ev_message := 'Update failed [' || ::SQL_ERROR_CODE || ']: ' || ::SQL_ERROR_MESSAGE;
    END;

    SELECT COUNT(*) INTO lv_count FROM :it_updates;

    IF :lv_count = 0 THEN
        ev_updated := 0;
        ev_message := 'No data to update';
        RETURN;
    END IF;

    /*******************************************************************
     * Bulk UPDATE using JOIN pattern
     * Updates target table based on matching source records
     *******************************************************************/
    UPDATE "<SCHEMA>"."TARGET_TABLE" AS t
    SET t.amount = u.new_amount,
        t.status = u.new_status,
        t.modified_at = CURRENT_TIMESTAMP
    FROM :it_updates AS u
    WHERE t.id = u.id;

    ev_updated := ::ROWCOUNT;
    ev_message := 'Successfully updated ' || :ev_updated || ' records';

END;

/**
 * Pattern 3: MERGE (UPSERT) Operation
 * Inserts new records, updates existing ones
 */
CREATE OR REPLACE PROCEDURE "<SCHEMA>"."MERGE_PATTERN"
(
    IN  it_data         TABLE (
        id              INTEGER,
        name            NVARCHAR(100),
        amount          DECIMAL(15,2)
    ),
    OUT ev_inserted     INTEGER,
    OUT ev_updated      INTEGER,
    OUT ev_message      NVARCHAR(500)
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
BEGIN
    DECLARE lv_before_count INTEGER;
    DECLARE lv_after_count INTEGER;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ev_inserted := 0;
        ev_updated := 0;
        ev_message := 'Merge failed [' || ::SQL_ERROR_CODE || ']: ' || ::SQL_ERROR_MESSAGE;
    END;

    -- Get count before merge
    SELECT COUNT(*) INTO lv_before_count FROM "<SCHEMA>"."TARGET_TABLE";

    /*******************************************************************
     * MERGE Statement (UPSERT)
     * WHEN MATCHED: Update existing records
     * WHEN NOT MATCHED: Insert new records
     *******************************************************************/
    MERGE INTO "<SCHEMA>"."TARGET_TABLE" AS target
    USING :it_data AS source
    ON target.id = source.id
    WHEN MATCHED THEN
        UPDATE SET
            target.name = source.name,
            target.amount = source.amount,
            target.modified_at = CURRENT_TIMESTAMP
    WHEN NOT MATCHED THEN
        INSERT (id, name, amount, created_at)
        VALUES (source.id, source.name, source.amount, CURRENT_TIMESTAMP);

    -- Capture ROWCOUNT immediately after MERGE (before any other statement)
    DECLARE lv_merge_count INTEGER := ::ROWCOUNT;

    -- Calculate inserted vs updated
    SELECT COUNT(*) INTO lv_after_count FROM "<SCHEMA>"."TARGET_TABLE";

    ev_inserted := :lv_after_count - :lv_before_count;
    ev_updated := :lv_merge_count - :ev_inserted;
    ev_message := 'Merge complete. Inserted: ' || :ev_inserted || ', Updated: ' || :ev_updated;

END;

/**
 * Pattern 4: Batch Processing with Chunking
 * Processes large datasets in manageable chunks
 * Prevents memory issues and allows progress tracking
 */
CREATE OR REPLACE PROCEDURE "<SCHEMA>"."BATCH_PROCESSING_PATTERN"
(
    IN  iv_batch_size   INTEGER DEFAULT 1000,   -- Records per batch
    IN  iv_max_batches  INTEGER DEFAULT 100,    -- Max iterations
    OUT ev_total        INTEGER,
    OUT ev_batches      INTEGER,
    OUT ev_message      NVARCHAR(500)
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
BEGIN
    DECLARE lv_offset       INTEGER := 0;
    DECLARE lv_batch_count  INTEGER := 0;
    DECLARE lv_total_count  INTEGER := 0;
    DECLARE lv_processed    INTEGER := 0;

    -- Table variable to hold current batch
    DECLARE lt_batch TABLE (
        id      INTEGER,
        name    NVARCHAR(100),
        amount  DECIMAL(15,2)
    );

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ev_total := :lv_total_count;
        ev_batches := :lv_batch_count;
        ev_message := 'Batch processing failed at batch ' || :lv_batch_count ||
                      ' [' || ::SQL_ERROR_CODE || ']: ' || ::SQL_ERROR_MESSAGE;
    END;

    -- Get total records to process
    SELECT COUNT(*) INTO lv_total_count
    FROM "<SCHEMA>"."SOURCE_TABLE"
    WHERE status = 'PENDING';

    IF :lv_total_count = 0 THEN
        ev_total := 0;
        ev_batches := 0;
        ev_message := 'No records to process';
        RETURN;
    END IF;

    /*******************************************************************
     * Batch Processing Loop
     *******************************************************************/
    WHILE :lv_processed < :lv_total_count AND :lv_batch_count < :iv_max_batches DO

        -- Fetch next batch
        lt_batch = SELECT id, name, amount
                   FROM "<SCHEMA>"."SOURCE_TABLE"
                   WHERE status = 'PENDING'
                   ORDER BY id
                   LIMIT :iv_batch_size OFFSET :lv_offset;

        -- Check if batch is empty
        IF IS_EMPTY(:lt_batch) THEN
            -- No more records
            BREAK;
        END IF;

        -- Process batch: Mark as processing
        UPDATE "<SCHEMA>"."SOURCE_TABLE"
        SET status = 'PROCESSING',
            batch_id = :lv_batch_count
        WHERE id IN (SELECT id FROM :lt_batch);

        -- Process batch: Apply business logic
        UPDATE "<SCHEMA>"."SOURCE_TABLE"
        SET processed_amount = amount * 1.1,  -- Example transformation
            status = 'COMPLETED',
            processed_at = CURRENT_TIMESTAMP
        WHERE id IN (SELECT id FROM :lt_batch);

        -- Update counters
        lv_processed := :lv_processed + CARDINALITY(:lt_batch);
        lv_batch_count := :lv_batch_count + 1;
        lv_offset := :lv_offset + :iv_batch_size;

    END WHILE;

    /*******************************************************************
     * Results
     *******************************************************************/
    ev_total := :lv_processed;
    ev_batches := :lv_batch_count;
    ev_message := 'Processed ' || :lv_processed || ' records in ' ||
                  :lv_batch_count || ' batches';

END;

/**
 * Pattern 5: Bulk DELETE with Safety Checks
 * Deletes multiple records with validation and logging
 */
CREATE OR REPLACE PROCEDURE "<SCHEMA>"."BULK_DELETE_PATTERN"
(
    IN  it_ids          TABLE (id INTEGER),
    IN  iv_hard_delete  INTEGER DEFAULT 0,      -- 0 = soft delete, 1 = hard delete
    OUT ev_deleted      INTEGER,
    OUT ev_message      NVARCHAR(500)
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
BEGIN
    DECLARE lv_count INTEGER := 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ev_deleted := 0;
        ev_message := 'Delete failed [' || ::SQL_ERROR_CODE || ']: ' || ::SQL_ERROR_MESSAGE;
    END;

    SELECT COUNT(*) INTO lv_count FROM :it_ids;

    IF :lv_count = 0 THEN
        ev_deleted := 0;
        ev_message := 'No IDs provided for deletion';
        RETURN;
    END IF;

    /*******************************************************************
     * Safety Check: Verify records exist and can be deleted
     *******************************************************************/
    DECLARE lt_valid_ids TABLE (id INTEGER);

    lt_valid_ids = SELECT t.id
                   FROM "<SCHEMA>"."TARGET_TABLE" t
                   INNER JOIN :it_ids i ON t.id = i.id
                   WHERE t.status NOT IN ('LOCKED', 'ARCHIVED');

    SELECT COUNT(*) INTO lv_count FROM :lt_valid_ids;

    IF :lv_count = 0 THEN
        ev_deleted := 0;
        ev_message := 'No valid records found for deletion';
        RETURN;
    END IF;

    /*******************************************************************
     * Archive before delete (audit trail)
     *******************************************************************/
    INSERT INTO "<SCHEMA>"."TARGET_TABLE_ARCHIVE" (
        id, name, amount, status, deleted_at
    )
    SELECT
        t.id, t.name, t.amount, t.status, CURRENT_TIMESTAMP
    FROM "<SCHEMA>"."TARGET_TABLE" t
    INNER JOIN :lt_valid_ids v ON t.id = v.id;

    /*******************************************************************
     * Delete Records
     *******************************************************************/
    IF :iv_hard_delete = 1 THEN
        -- Hard delete: Remove records completely
        DELETE FROM "<SCHEMA>"."TARGET_TABLE"
        WHERE id IN (SELECT id FROM :lt_valid_ids);
    ELSE
        -- Soft delete: Mark as deleted
        UPDATE "<SCHEMA>"."TARGET_TABLE"
        SET status = 'DELETED',
            deleted_at = CURRENT_TIMESTAMP
        WHERE id IN (SELECT id FROM :lt_valid_ids);
    END IF;

    ev_deleted := ::ROWCOUNT;
    ev_message := CASE :iv_hard_delete
                      WHEN 1 THEN 'Hard deleted '
                      ELSE 'Soft deleted '
                  END || :ev_deleted || ' records';

END;

/*
 * Performance Guidelines for Bulk Operations:
 *
 * 1. ALWAYS prefer set-based operations over cursors
 * 2. Use MERGE instead of separate INSERT/UPDATE logic
 * 3. Process in batches for datasets > 10,000 rows
 * 4. Index columns used in WHERE and JOIN conditions
 * 5. Use table variables to pass data between operations
 * 6. Avoid dynamic SQL in bulk operations
 * 7. Consider partitioning for very large tables
 * 8. Monitor memory usage with large result sets
 *
 * Transaction Guidelines:
 * - DDL operations auto-commit
 * - Explicit COMMIT only allowed in top-level procedures
 * - COMMIT not allowed in AMDP
 * - Use autonomous transactions for logging
 */
