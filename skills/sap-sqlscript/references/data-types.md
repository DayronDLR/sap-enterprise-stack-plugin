# SQLScript Data Types Reference

## Numeric Types

| Type | Description | Range |
|------|-------------|-------|
| `TINYINT` | 8-bit integer | 0 to 255 |
| `SMALLINT` | 16-bit integer | -32,768 to 32,767 |
| `INTEGER` / `INT` | 32-bit integer | -2,147,483,648 to 2,147,483,647 |
| `BIGINT` | 64-bit integer | -9,223,372,036,854,775,808 to 9,223,372,036,854,775,807 |
| `DECIMAL(p,s)` | Fixed-point decimal | p = precision (1-34), s = scale (0-p) |
| `DOUBLE` | 64-bit floating point | 15-digit precision |
| `REAL` | 32-bit floating point | 7-digit precision |

### Usage Examples

```sql
-- Decimal with precision and scale
DECLARE lv_price DECIMAL(15,2) := 12345.67;

-- Integer types
DECLARE lv_count INTEGER := 0;
DECLARE lv_id BIGINT;

-- Floating point
DECLARE lv_percentage REAL := 0.95;
DECLARE lv_measurement DOUBLE := 123.456789;
```

## Character Types

| Type | Description | Max Length |
|------|-------------|------------|
| `VARCHAR(n)` | Variable-length ASCII string | 5,000 bytes |
| `NVARCHAR(n)` | Variable-length Unicode string | 5,000 characters |
| `ALPHANUM(n)` | Alphanumeric string | 127 characters |
| `CLOB` | Character large object | 2 GB |
| `NCLOB` | Unicode character large object | 2 GB |
| `NLOB` | National character large object | 2 GB |

### Usage Examples

```sql
-- String variables
DECLARE lv_name NVARCHAR(100) := 'John Doe';
DECLARE lv_description VARCHAR(500);
DECLARE lv_code ALPHANUM(10) := 'ABC123';

-- Large objects
DECLARE lt_document CLOB;
```

### String Operations

```sql
-- Concatenation
lv_full_name = lv_first_name || ' ' || lv_last_name;

-- Common string functions
lv_upper = UPPER(:lv_string);
lv_length = LENGTH(:lv_string);
lv_trimmed = TRIM(:lv_string);
lv_substring = SUBSTRING(:lv_string, 1, 10);
```

## Date/Time Types

| Type | Format | Range |
|------|--------|-------|
| `DATE` | 'YYYY-MM-DD' | 0001-01-01 to 9999-12-31 |
| `TIME` | 'HH:MI:SS' | 00:00:00 to 23:59:59 |
| `TIMESTAMP` | 'YYYY-MM-DD HH:MI:SS.FF' | Up to 7 fractional digits |
| `SECONDDATE` | 'YYYY-MM-DD HH:MI:SS' | Same as TIMESTAMP without fractions |

### Usage Examples

```sql
-- Date/time declarations
DECLARE lv_order_date DATE := CURRENT_DATE;
DECLARE lv_created_time TIMESTAMP := CURRENT_TIMESTAMP;
DECLARE lv_start_time TIME;

-- Date literals
lv_date = DATE '2025-11-26';
lv_time = TIME '14:30:00';
lv_timestamp = TIMESTAMP '2025-11-26 14:30:00.123';

-- Date operations
lv_future_date = ADD_DAYS(:lv_date, 30);
lv_days_between = DAYS_BETWEEN(:lv_date1, :lv_date2);
```

## Binary Types

| Type | Description | Max Length |
|------|-------------|------------|
| `VARBINARY(n)` | Variable-length binary | 5,000 bytes |
| `BLOB` | Binary large object | 2 GB |

### Usage Examples

```sql
-- Binary data
DECLARE lv_image VARBINARY(1000);
DECLARE lb_file BLOB;

-- Hexadecimal literals
lv_binary = X'48656C6C6F'; -- 'Hello' in hex
```

## Type Conversion

### CAST Function

```sql
-- Explicit type conversion
lv_string = CAST(:lv_number AS VARCHAR(20));
lv_date = CAST(:lv_string AS DATE);
lv_decimal = CAST(:lv_number AS DECIMAL(10,2));
```

### TO_ Functions

```sql
-- String to number
lv_integer = TO_INTEGER(:lv_string);
lv_decimal = TO_DECIMAL(:lv_string, '999999.99');

-- String to date/time
lv_date = TO_DATE(:lv_string, 'YYYY-MM-DD');
lv_timestamp = TO_TIMESTAMP(:lv_string, 'YYYY-MM-DD HH24:MI:SS');

-- Number/date to string
lv_string = TO_VARCHAR(:lv_number);
lv_string_date = TO_VARCHAR(:lv_date, 'YYYY-MM-DD');

-- ABAP date/time conversion
lv_abap_date = TO_DATS(:lv_date);
lv_abap_time = TO_TIMS(:lv_time);
```

## NULL Handling

### Functions for NULL Values

```sql
-- COALESCE: Return first non-NULL value
lv_result = COALESCE(:lv_value1, :lv_value2, 'DEFAULT');

-- IFNULL: Return default if NULL
lv_result = IFNULL(:lv_value, 'DEFAULT');

-- NULLIF: Return NULL if values equal
lv_null_result = NULLIF(:lv_value1, :lv_value2);
```

### NULL Comparisons

```sql
-- Check for NULL
IF :lv_value IS NULL THEN
  -- Handle NULL
END IF;

-- Cannot use = NULL, must use IS NULL
-- Wrong: WHERE column = NULL
-- Right: WHERE column IS NULL
```

## Special Considerations

### Character Set Considerations

- `VARCHAR` stores ASCII (1 byte per character)
- `NVARCHAR` stores Unicode (UTF-8, variable bytes per character)
- Use `NVARCHAR` for multilingual data
- `ALPHANUM` removes leading/trailing spaces automatically

### Performance Considerations

- Use smallest appropriate data type for better performance
- `DECIMAL` is preferred over `FLOAT` for precise calculations
- `VARCHAR`/`NVARCHAR` with defined length performs better than CLOB
- Date types store more efficiently than string representations

### Storage Engine Differences

- Column Store: Optimized for analytical queries, compression
- Row Store: Optimized for transactional queries
- Choose appropriate storage type based on usage pattern

## Best Practices

1. **Use appropriate data types** - Choose the smallest type that fits your needs
2. **Prefer specific over generic** - Use `DECIMAL` instead of `DOUBLE` for money
3. **Consider Unicode** - Use `NVARCHAR` for any text that might contain non-ASCII
4. **Handle NULLs explicitly** - Don't assume values are non-NULL
5. **Use functions for conversion** - Prefer `TO_` functions over `CAST` for dates/times
6. **Document assumptions** - Comment on data type choices and constraints
