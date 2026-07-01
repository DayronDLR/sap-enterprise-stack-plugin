# SQLScript Glossary

Comprehensive glossary of SQLScript and SAP HANA database terminology.

---

## A

### AMDP (ABAP Managed Database Procedure)

A technology that allows SQLScript procedures to be written and managed within ABAP classes. Requires the `IF_AMDP_MARKER_HDB` interface and NetWeaver 7.40 SP05+.

### Anonymous Block

A SQLScript code block executed immediately without being stored in the database. Uses `DO BEGIN ... END;` syntax. Useful for testing and ad-hoc operations.

### Array

A one-dimensional ordered collection of elements of the same type. Declared with `ARRAY` keyword. Uses 1-based indexing. Cannot be returned from procedures.

---

## B

### Binding

The process of assigning host variables to SQL statements at runtime. In SQLScript, variables are bound using the colon prefix (`:variable_name`).

### Block Statement

A compound statement enclosed in `BEGIN ... END` that groups multiple statements. Can contain declarations, executable statements, and exception handlers.

---

## C

### Calculation Engine (CE)

SAP HANA's internal execution engine optimized for analytical processing. CE functions (e.g., `CE_CALC`, `CE_JOIN`) provide direct access to this engine but are deprecated in favor of SQL-based approaches.

### Code-to-Data Paradigm

The fundamental principle of pushing computation to where data resides (in the database) rather than moving data to the application layer. This minimizes data transfer and leverages HANA's in-memory processing.

### Column Store

SAP HANA's primary storage format where data is stored by columns rather than rows. Optimized for analytical queries, aggregations, and compression. Most tables should use column store.

### Condition

A named association with a specific SQL error code. Declared with `DECLARE condition_name CONDITION FOR SQL_ERROR_CODE number;`. Used with EXIT HANDLER for targeted error handling.

### Cursor

A database object that allows row-by-row processing of query results. Pattern: Declare → Open → Fetch → Close. Use sparingly as cursors bypass the optimizer.

---

## D

### DDL (Data Definition Language)

SQL statements that define database structure: CREATE, ALTER, DROP, TRUNCATE. DDL operations are auto-committed in HANA.

### Declarative Logic

SQL-based code that describes *what* result is wanted without specifying *how* to compute it. Converted to data flow graphs and executed in parallel. Preferred over imperative logic.

### Default Schema

The schema used when object names are not fully qualified. Set with `DEFAULT SCHEMA` clause in procedures or session-level `SET SCHEMA`.

### DML (Data Manipulation Language)

SQL statements that manipulate data: SELECT, INSERT, UPDATE, DELETE, MERGE. DML operations respect transaction boundaries.

### DUMMY

A single-row, single-column system table used for evaluating expressions without needing actual table data. `SELECT :variable FROM DUMMY;`

### Dynamic SQL

SQL statements constructed and executed at runtime using `EXECUTE IMMEDIATE`. Avoid when possible as it prevents optimization and poses security risks.

---

## E

### Engine Mixing

The anti-pattern of combining Row Store and Column Store operations in a single query, or mixing CE functions with SQL. Causes performance degradation due to data format conversion.

### EXIT HANDLER

An exception handler that executes when a specified condition occurs, then exits the current block. Declared with `DECLARE EXIT HANDLER FOR condition_value statement;`.

---

## F

### Function (UDF)

User-Defined Function. Two types:

- **Scalar UDF**: Returns a single value
- **Table UDF**: Returns a table (must be read-only)

---

## H

### HDI (HANA Deployment Infrastructure)

A container-based deployment model for SAP HANA artifacts. Provides isolated schema namespaces and supports version-controlled deployments via `.hdbtable`, `.hdbprocedure` files.

### Host Variable

A variable in SQLScript that holds values passed to or from SQL statements. Referenced with colon prefix (`:variable`).

---

## I

### Imperative Logic

Procedural code using control structures (IF, WHILE, FOR, LOOP) that specifies *how* to compute results step by step. Executes sequentially and prevents parallel processing. Use only when necessary.

### Implicit Declaration

Creating a table variable without explicit DECLARE by assigning a SELECT result: `lt_result = SELECT * FROM table;`

### INVOKER

SQL Security mode where the procedure executes with the privileges of the calling user. Compare with DEFINER mode.

---

## L

### L-Value

An expression that can appear on the left side of an assignment (can be assigned to). In SQLScript: scalar variables, table variables.

### Lateral Join

A join where the right side can reference columns from the left side. Uses `CROSS APPLY` or `OUTER APPLY` syntax. Enables correlated subquery-like patterns in FROM clause.

---

## N

### NULL

The absence of a value. Handled with COALESCE, IFNULL, NULLIF functions. Uninitialized variables default to NULL.

---

## O

### OUTER APPLY

A lateral join that returns all rows from the left side even when the right side returns no rows (similar to LEFT JOIN). Compare with CROSS APPLY.

---

## P

### Parallel Execution

The ability of SAP HANA to execute multiple operations simultaneously. Declarative SQL enables parallel execution; imperative logic prevents it.

### Plan Visualizer

SAP HANA tool for analyzing query execution plans. Shows operator breakdown, data flow, and identifies performance bottlenecks.

### Pragma

A compiler directive that influences code generation without changing logic. Example: `/*#RESULT_CACHE*/` for result caching.

### Procedure

A stored database object containing SQLScript logic with optional input/output parameters. Created with `CREATE PROCEDURE` and invoked with `CALL`.

---

## R

### READS SQL DATA

Procedure option indicating read-only operation (no DML changes). Required for procedures called from SQL expressions and table functions.

### RESIGNAL

Statement that re-throws the current exception from within an exception handler, optionally with a modified message.

### Row Store

SAP HANA storage format where data is stored by rows. Used for OLTP-style operations requiring frequent single-row access. Less common than Column Store.

### R-Value

An expression that can appear on the right side of an assignment (provides a value). In SQLScript: literals, expressions, function results.

---

## S

### Scalar Type

A data type that holds a single value (INTEGER, VARCHAR, DATE, etc.) as opposed to table types or arrays.

### SIGNAL

Statement that throws a user-defined exception with a custom error code (10000-19999) and message. `SIGNAL condition SET MESSAGE_TEXT = 'message';`

### SQL Security

Determines execution privileges for procedures:

- **DEFINER**: Runs with owner's privileges
- **INVOKER**: Runs with caller's privileges

### SQLEXCEPTION

A generic condition that matches any SQL exception. Used with EXIT HANDLER: `DECLARE EXIT HANDLER FOR SQLEXCEPTION ...`

### SQLScript

SAP HANA's procedural extension to SQL. Combines declarative SQL with imperative control structures for complex database logic.

---

## T

### Table Type

A user-defined type defining a table structure. Created with `CREATE TYPE name AS TABLE (...)`. Used for procedure parameters and structured data.

### Table Variable

A variable that holds a table structure and data. Can be implicitly or explicitly declared. Referenced with colon prefix in SQL context.

### Transaction

A logical unit of work comprising one or more database operations. Bounded by COMMIT or ROLLBACK. Note: DDL auto-commits.

---

## U

### UDF (User-Defined Function)

See Function.

### UNION ALL

Set operation combining results without removing duplicates. Faster than UNION which eliminates duplicates.

---

## V

### Variable Scope

The visibility of a variable within code:

- **Block scope**: Variables declared in a block are visible only within that block
- **Procedure scope**: Parameters visible throughout the procedure

---

## W

### Window Function

A function that performs calculations across a set of rows related to the current row, without collapsing results. Examples: ROW_NUMBER, RANK, LAG, LEAD, SUM OVER.

---

## Common Abbreviations

| Abbreviation | Full Form |
|--------------|-----------|
| AMDP | ABAP Managed Database Procedure |
| CE | Calculation Engine |
| CDS | Core Data Services |
| DDL | Data Definition Language |
| DML | Data Manipulation Language |
| HDI | HANA Deployment Infrastructure |
| HANA | High-performance ANalytic Appliance |
| UDF | User-Defined Function |
| XSA | Extended Application Services, Advanced |

---

## Related Terms

For function-specific terminology, see [built-in-functions.md](built-in-functions.md).
For AMDP-specific terminology, see [amdp-integration.md](amdp-integration.md).
For data type details, see [data-types.md](data-types.md).
