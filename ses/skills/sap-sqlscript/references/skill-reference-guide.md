# SQLScript Skill Reference Guide

This guide provides quick navigation to all reference documentation in the sap-sqlscript skill.

## Reference Files Overview

| File | Description | Lines | Use When |
|------|-------------|-------|----------|
| [syntax-reference.md](syntax-reference.md) | Complete SQLScript syntax patterns | ~564 | Looking up CREATE PROCEDURE, function syntax, control flow |
| [built-in-functions.md](built-in-functions.md) | All built-in function categories | ~518 | Finding string, date, numeric, aggregate, window functions |
| [data-types.md](data-types.md) | Data type documentation | ~187 | Choosing correct data types, type conversion |
| [exception-handling.md](exception-handling.md) | Error handling patterns | ~491 | Implementing EXIT HANDLER, SIGNAL, RESIGNAL |
| [amdp-integration.md](amdp-integration.md) | AMDP implementation guide | ~527 | Creating AMDP classes, method types, ABAP integration |
| [performance-guide.md](performance-guide.md) | Optimization techniques | ~406 | Optimizing procedures, avoiding anti-patterns |
| [advanced-features.md](advanced-features.md) | Advanced SQLScript features | ~846 | Lateral joins, JSON, query hints, CE functions |
| [troubleshooting.md](troubleshooting.md) | Common errors and solutions | ~540 | Debugging errors, resolving common issues |

---

## Quick Navigation by Topic

### Getting Started

- **Syntax basics**: [syntax-reference.md](syntax-reference.md) - Procedure, function, anonymous block syntax
- **Data types**: [data-types.md](data-types.md) - All supported types and conversion functions
- **Built-in functions**: [built-in-functions.md](built-in-functions.md) - String, date, numeric functions

### Core Development

- **Stored Procedures**: [syntax-reference.md](syntax-reference.md) - CREATE PROCEDURE patterns
- **User-Defined Functions**: [syntax-reference.md](syntax-reference.md) - Scalar and table UDFs
- **Variables & Table Types**: [syntax-reference.md](syntax-reference.md) - Declaration patterns
- **Control Structures**: [syntax-reference.md](syntax-reference.md) - IF, WHILE, FOR, LOOP
- **Cursors**: [syntax-reference.md](syntax-reference.md) - DECLARE, OPEN, FETCH, CLOSE

### Error Handling

- **EXIT HANDLER**: [exception-handling.md](exception-handling.md) - Basic and advanced patterns
- **CONDITION**: [exception-handling.md](exception-handling.md) - Named conditions
- **SIGNAL/RESIGNAL**: [exception-handling.md](exception-handling.md) - User-defined exceptions
- **Error codes**: [exception-handling.md](exception-handling.md) - Common SQL error codes
- **Error logging**: [exception-handling.md](exception-handling.md) - Logging patterns

### ABAP Integration

- **AMDP Classes**: [amdp-integration.md](amdp-integration.md) - Class structure and interface
- **AMDP Methods**: [amdp-integration.md](amdp-integration.md) - Procedures, functions, CDS
- **Data Type Mapping**: [amdp-integration.md](amdp-integration.md) - ABAP to SQLScript types
- **AMDP Restrictions**: [amdp-integration.md](amdp-integration.md) - Limitations and workarounds
- **Debugging AMDP**: [amdp-integration.md](amdp-integration.md) - Eclipse ADT debugging

### Performance Optimization

- **Code-to-Data**: [performance-guide.md](performance-guide.md) - Fundamental paradigm
- **Declarative vs Imperative**: [performance-guide.md](performance-guide.md) - When to use each
- **Engine Mixing**: [performance-guide.md](performance-guide.md) - Avoiding Row/Column store issues
- **Cursor Performance**: [performance-guide.md](performance-guide.md) - When cursors are acceptable
- **Memory Management**: [performance-guide.md](performance-guide.md) - Large result sets
- **Index Strategies**: [performance-guide.md](performance-guide.md) - Index usage in SQLScript

### Functions Reference

- **String Functions**: [built-in-functions.md](built-in-functions.md) - SUBSTRING, CONCAT, TRIM, etc.
- **Numeric Functions**: [built-in-functions.md](built-in-functions.md) - ROUND, ABS, MOD, etc.
- **Date/Time Functions**: [built-in-functions.md](built-in-functions.md) - ADD_DAYS, EXTRACT, etc.
- **Conversion Functions**: [built-in-functions.md](built-in-functions.md) - CAST, TO_VARCHAR, etc.
- **Aggregate Functions**: [built-in-functions.md](built-in-functions.md) - SUM, COUNT, AVG, etc.
- **Window Functions**: [built-in-functions.md](built-in-functions.md) - ROW_NUMBER, RANK, LAG, LEAD
- **NULL Handling**: [built-in-functions.md](built-in-functions.md) - COALESCE, IFNULL, NULLIF

### Advanced Features

- **Lateral Joins**: [advanced-features.md](advanced-features.md) - CROSS APPLY, OUTER APPLY
- **JSON Support**: [advanced-features.md](advanced-features.md) - JSON_VALUE, JSON_TABLE
- **Query Hints**: [advanced-features.md](advanced-features.md) - INDEX, LOOKUPS, NO_ROW_LOCK
- **Currency Conversion**: [advanced-features.md](advanced-features.md) - CONVERT_CURRENCY
- **Unit Conversion**: [advanced-features.md](advanced-features.md) - CONVERT_UNIT
- **CE Functions**: [advanced-features.md](advanced-features.md) - Calculation Engine functions
- **Array Functions**: [advanced-features.md](advanced-features.md) - Array aggregation
- **Pragmas**: [advanced-features.md](advanced-features.md) - Compiler directives

### Troubleshooting

- **Common Errors**: [troubleshooting.md](troubleshooting.md) - Error messages and solutions
- **Invalid Column/Table**: [troubleshooting.md](troubleshooting.md) - Name resolution issues
- **Type Conversion**: [troubleshooting.md](troubleshooting.md) - Implicit/explicit conversion
- **Performance Issues**: [troubleshooting.md](troubleshooting.md) - Memory and timeout errors
- **Security Errors**: [troubleshooting.md](troubleshooting.md) - Privilege and authorization
- **AMDP Errors**: [troubleshooting.md](troubleshooting.md) - AMDP-specific issues
- **Debugging Strategies**: [troubleshooting.md](troubleshooting.md) - Step-by-step debugging

---

## Common Use Case Mapping

| I want to... | Reference File |
|--------------|----------------|
| Create a stored procedure | [syntax-reference.md](syntax-reference.md) |
| Create a table function | [syntax-reference.md](syntax-reference.md) |
| Handle errors in my procedure | [exception-handling.md](exception-handling.md) |
| Create an AMDP class | [amdp-integration.md](amdp-integration.md) |
| Optimize slow procedure | [performance-guide.md](performance-guide.md) |
| Work with JSON data | [advanced-features.md](advanced-features.md) |
| Convert currency values | [advanced-features.md](advanced-features.md) |
| Fix a specific error | [troubleshooting.md](troubleshooting.md) |
| Find a specific function | [built-in-functions.md](built-in-functions.md) |
| Choose the right data type | [data-types.md](data-types.md) |

---

## Search Patterns

Use these patterns to search within reference files:

```
# Find all function signatures
grep -E "^[A-Z_]+\(" references/*.md

# Find all error codes
grep -E "SQL_ERROR_CODE|error code" references/*.md

# Find all examples
grep -A5 "Example:" references/*.md

# Find AMDP patterns
grep -E "BY DATABASE|AMDP" references/*.md
```

---

## Version Information

- **SAP HANA Platform**: 2.0 SPS07
- **SAP HANA Cloud**: QRC 3/2025
- **AMDP Support**: NetWeaver 7.40 SP05+
- **Last Updated**: 2025-12-27

---

## Related Skills

For comprehensive SAP development, combine this skill with:

- **sap-abap** - ABAP programming patterns for AMDP context
- **sap-cap-capire** - CAP framework database procedures integration
- **sap-hana-cli** - HANA CLI for procedure deployment and testing
- **sap-abap-cds** - CDS views that consume SQLScript procedures
- **sap-btp-cloud-platform** - BTP deployment of HANA artifacts
