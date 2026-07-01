# SAP SQLScript Skill

Comprehensive SQLScript development skill for SAP HANA database programming.

## Overview

This skill provides complete guidance for SQLScript development, including:

- Stored procedures and user-defined functions
- Anonymous blocks for ad-hoc execution
- Control structures and exception handling
- Built-in functions (string, date, numeric, aggregate, window)
- AMDP (ABAP Managed Database Procedures) integration
- Performance optimization techniques
- Troubleshooting common errors

## Plugin Components

This plugin includes specialized agents, commands, templates, and validation hooks for comprehensive SQLScript development support.

### Agents

| Agent | Purpose | Trigger Phrases |
|-------|---------|-----------------|
| **sqlscript-analyzer** | Analyze SQLScript code for performance issues and best practices | "analyze my SQLScript", "review HANA procedure", "check procedure performance" |
| **procedure-generator** | Generate procedures interactively (asks clarifying questions first) | "create a SQLScript procedure", "generate HANA procedure", "write stored procedure for" |
| **amdp-helper** | Help with AMDP class creation and debugging | "create an AMDP class", "help with AMDP", "ABAP managed database procedure" |

### Slash Commands

| Command | Usage | Description |
|---------|-------|-------------|
| `/sqlscript-validate` | `/sqlscript-validate [file] --fix` | Validate SQLScript code with auto-fix capability |
| `/sqlscript-optimize` | `/sqlscript-optimize [file] --fix` | Analyze performance issues with auto-fix |
| `/sqlscript-convert` | `/sqlscript-convert [file] --to amdp\|standalone\|cds-function` | Convert between standalone and AMDP formats |

### Templates

Production-ready templates with full error handling:

| Template | Description |
|----------|-------------|
| `simple-procedure.sql` | Basic stored procedure with error handling and input validation |
| `procedure-with-error-handling.sql` | Comprehensive error handling with logging and custom conditions |
| `table-function.sql` | Table UDF with parameter validation |
| `scalar-function.sql` | Scalar UDF examples (name formatting, calculations, status mapping) |
| `amdp-class.abap` | Complete AMDP class with interface and multiple method types |
| `amdp-procedure.sql` | AMDP implementation with type mapping reference |
| `cursor-iteration.sql` | Cursor patterns (classic, FOR loop, nested, set-based alternatives) |
| `bulk-operations.sql` | Bulk INSERT, UPDATE, DELETE, MERGE, batch processing |

### Validation Hooks

Automatic code quality checks on Write/Edit operations:

- Error handling completeness (EXIT HANDLER, cursor management)
- Security vulnerabilities (hardcoded schemas, SQL injection)
- Performance anti-patterns (cursors in loops, SELECT *, missing WHERE)
- Naming conventions (lv_, lt_, iv_, et_ prefixes)
- AMDP compliance (interface, USING clause, pass-by-value)

## Keywords

### Technology Terms

- SQLScript
- SAP HANA
- HANA database
- SAP HANA Cloud
- SAP HANA Platform
- SQL Script
- HANA SQL
- database procedure
- stored procedure
- user-defined function
- UDF
- scalar UDF
- table UDF
- table function
- anonymous block

### Programming Concepts

- code-to-data paradigm
- declarative logic
- imperative logic
- procedural SQL
- cursor
- table variable
- table type
- array
- exception handling
- EXIT HANDLER
- SIGNAL
- RESIGNAL
- CONDITION

### HANA Specific

- Column Store
- Row Store
- Calculation Engine
- Plan Visualizer
- Expensive Statement Trace
- SQL Analyzer
- HANA Studio
- SAP Web IDE
- Business Application Studio

### ABAP Integration

- AMDP
- ABAP Managed Database Procedures
- IF_AMDP_MARKER_HDB
- BY DATABASE PROCEDURE
- code pushdown
- ABAP CDS
- S/4HANA

### Control Structures

- IF THEN ELSE
- ELSEIF
- WHILE DO
- FOR loop
- LOOP
- BREAK
- CONTINUE
- CASE WHEN

### Data Types

- INTEGER
- BIGINT
- SMALLINT
- TINYINT
- DECIMAL
- DOUBLE
- REAL
- VARCHAR
- NVARCHAR
- ALPHANUM
- DATE
- TIME
- TIMESTAMP
- SECONDDATE
- CLOB
- BLOB

### Built-in Functions

- string functions
- date functions
- numeric functions
- aggregate functions
- window functions
- conversion functions
- CONCAT
- SUBSTRING
- LENGTH
- TRIM
- UPPER
- LOWER
- ADD_DAYS
- DAYS_BETWEEN
- CURRENT_DATE
- CURRENT_TIMESTAMP
- TO_VARCHAR
- TO_DATE
- TO_INTEGER
- CAST
- SUM
- COUNT
- AVG
- MIN
- MAX
- ROW_NUMBER
- RANK
- DENSE_RANK
- LEAD
- LAG
- PARTITION BY
- TO_DATS
- TO_TIMS
- CONVERT_CURRENCY
- session_context
- record_count
- lateral join
- JSON functions
- query hints
- APPLY_FILTER
- ARRAY_AGG
- TRIM_ARRAY
- CE functions
- CONTINUE HANDLER
- Code Analyzer
- Plan Profiler
- Pragmas

### Error Handling

- SQL_ERROR_CODE
- SQL_ERROR_MESSAGE
- DECLARE EXIT HANDLER
- SQLEXCEPTION
- error code 301
- unique constraint violation
- error logging

### Performance

- query optimization
- parallel execution
- UNION ALL vs UNION
- avoid dynamic SQL
- reduce data volume
- set-based operations
- execution plan
- index optimization

### Common Tasks

- create procedure
- create function
- create table type
- declare variable
- declare cursor
- fetch cursor
- insert data
- update data
- delete data
- select into
- execute immediate
- dynamic SQL

### Error Messages

- invalid column name
- invalid table name
- variable not defined
- cursor not open
- memory allocation failed
- insufficient privilege
- unique constraint violation
- foreign key violation

### Plugin Features

- sqlscript-validate
- sqlscript-optimize
- sqlscript-convert
- sqlscript-analyzer
- procedure-generator
- amdp-helper
- auto-fix
- code validation
- performance analysis

## File Structure

```
sap-sqlscript/
├── .claude-plugin/
│   └── plugin.json                # Plugin manifest
├── skills/sap-sqlscript/
│   ├── SKILL.md                   # Main skill file
│   ├── README.md                  # This file
│   ├── references/
│   │   ├── skill-reference-guide.md   # Index of all references
│   │   ├── glossary.md                # SQLScript terminology
│   │   ├── syntax-reference.md        # Complete syntax patterns
│   │   ├── built-in-functions.md      # All function categories
│   │   ├── data-types.md              # Data types and conversion
│   │   ├── exception-handling.md      # Error handling patterns
│   │   ├── amdp-integration.md        # AMDP implementation guide
│   │   ├── performance-guide.md       # Optimization techniques
│   │   ├── advanced-features.md       # Lateral joins, JSON, query hints
│   │   └── troubleshooting.md         # Common errors and solutions
│   └── templates/
│       ├── simple-procedure.sql
│       ├── procedure-with-error-handling.sql
│       ├── table-function.sql
│       ├── scalar-function.sql
│       ├── amdp-class.abap
│       ├── amdp-procedure.sql
│       ├── cursor-iteration.sql
│       └── bulk-operations.sql
├── agents/
│   ├── sqlscript-analyzer.md      # Performance analysis agent
│   ├── procedure-generator.md     # Interactive procedure generator
│   └── amdp-helper.md             # AMDP assistance agent
├── commands/
│   ├── sqlscript-validate.md      # Validation command
│   ├── sqlscript-optimize.md      # Optimization command
│   └── sqlscript-convert.md       # Conversion command
└── hooks/
    └── hooks.json                 # Validation hooks configuration
```

## Usage

This skill is automatically triggered when working with:

- SAP HANA stored procedures
- SQLScript development
- AMDP classes in ABAP
- HANA database functions
- SQL performance optimization in HANA

### Using Agents

Agents are triggered automatically based on context:

```
"Analyze my procedure for performance issues"
→ sqlscript-analyzer agent reviews your code

"Create a stored procedure to calculate order totals"
→ procedure-generator agent asks clarifying questions, then generates

"Help me create an AMDP class for customer data"
→ amdp-helper agent guides you through AMDP creation
```

### Using Commands

Commands are invoked directly:

```
/sqlscript-validate src/procedures/calc_totals.sql
/sqlscript-validate src/procedures/calc_totals.sql --fix

/sqlscript-optimize src/procedures/process_orders.sql

/sqlscript-convert src/procedures/get_data.sql --to amdp
```

### Using Templates

Templates are copied and customized:

```
"Create a new procedure using the simple-procedure template"
→ Claude copies templates/simple-procedure.sql and customizes it

"I need a bulk update operation"
→ Claude uses templates/bulk-operations.sql patterns
```

## Documentation Sources

The skill content is derived from official SAP documentation and community resources:

- **SAP HANA SQLScript Reference** (PDF)
  - URL: `https://help.sap.com/doc/6254b3bb439c4f409a979dc407b49c9b/2.0.07/en-US/SAP_HANA_SQL_Script_Reference_en.pdf`

- **SAP HANA Cloud SQLScript Reference**
  - URL: `https://help.sap.com/docs/hana-cloud-database/sap-hana-cloud-sap-hana-sqlscript-reference/`

- **SAP HANA SQL Functions**
  - URL: `https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20a61f29751910149f99f0300dd95cd9.html`

- **SAP Tutorials - SQLScript**
  - URL: `https://developers.sap.com/tutorial-navigator.html?tag=programming-tool:sqlscript`

- **AMDP Cheat Sheet** (SAP Samples)
  - URL: `https://github.com/SAP-samples/abap-cheat-sheets/blob/main/12_AMDP.md`

- **SAP Community - SQL Scripts in SAP HANA**
  - URL: `https://community.sap.com/t5/technology-blog-posts-by-members/sql-scripts-in-sap-hana/ba-p/13738376`

## Version Information

- **Skill Version**: 2.1.0
- **SAP HANA Platform**: 2.0 SPS07 (SPS08 available June 2025)
- **SAP HANA Cloud**: QRC 3/2025 (latest)
- **AMDP**: ABAP 7.40 SP05+
- **Last Updated**: 2025-12-27

## License

GPL-3.0
