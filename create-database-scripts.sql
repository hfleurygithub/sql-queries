SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#ScriptOut') IS NOT NULL
    DROP TABLE #ScriptOut;

CREATE TABLE #ScriptOut
(
    RowNum INT IDENTITY(1,1) PRIMARY KEY,
    ScriptLine NVARCHAR(MAX)
);

DECLARE @CRLF NVARCHAR(2) = CHAR(13) + CHAR(10);

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- =====================================================');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- GENERATED DATABASE SCRIPT - VERSION 2');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- Database: ' + QUOTENAME(DB_NAME()));
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- Generated on: ' + CONVERT(NVARCHAR(30), GETDATE(), 121));
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- =====================================================');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'SET ANSI_NULLS ON;');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'SET QUOTED_IDENTIFIER ON;');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 1) SCHEMAS
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- SCHEMAS');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N''' + s.name + N''') EXEC(''CREATE SCHEMA ' + QUOTENAME(s.name) + N''');'
FROM sys.schemas s
WHERE s.name NOT IN ('dbo', 'guest', 'sys', 'INFORMATION_SCHEMA')
ORDER BY s.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 2) Alias User-Defined Data Types
------------------------------------------------------------

SET NOCOUNT ON;

DECLARE @CRLF nvarchar(2) = CHAR(13) + CHAR(10);

SELECT N'-- USER-DEFINED ALIAS TYPES' + @CRLF + N'GO' AS ScriptLine
UNION ALL
SELECT
    N'IF TYPE_ID(N''' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N''') IS NULL' + @CRLF +
    N'    EXEC(''CREATE TYPE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N' FROM ' +
    CASE
        WHEN bt.name IN ('varchar','char','varbinary','binary')
            THEN bt.name + N'(' + CASE WHEN t.max_length = -1 THEN N'MAX' ELSE CAST(t.max_length AS nvarchar(10)) END + N')'
        WHEN bt.name IN ('nvarchar','nchar')
            THEN bt.name + N'(' + CASE WHEN t.max_length = -1 THEN N'MAX' ELSE CAST(t.max_length / 2 AS nvarchar(10)) END + N')'
        WHEN bt.name IN ('decimal','numeric')
            THEN bt.name + N'(' + CAST(t.precision AS nvarchar(10)) + N',' + CAST(t.scale AS nvarchar(10)) + N')'
        WHEN bt.name IN ('datetime2','time','datetimeoffset')
            THEN bt.name + N'(' + CAST(t.scale AS nvarchar(10)) + N')'
        ELSE bt.name
    END +
    CASE
        WHEN t.collation_name IS NOT NULL AND bt.name IN ('varchar','char','nvarchar','nchar','text','ntext')
            THEN N' COLLATE ' + t.collation_name
        ELSE N''
    END +
    CASE WHEN t.is_nullable = 1 THEN N' NULL' ELSE N' NOT NULL' END +
    N''');' + @CRLF + N'GO'
FROM sys.types t
JOIN sys.schemas s
    ON s.schema_id = t.schema_id
JOIN sys.types bt
    ON bt.user_type_id = t.system_type_id
   AND bt.user_type_id = bt.system_type_id
WHERE t.is_user_defined = 1
  AND t.is_table_type = 0
  AND bt.name IS NOT NULL;

------------------------------------------------------------
-- 2) PARTITION FUNCTIONS
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- PARTITION FUNCTIONS');

;WITH pf AS
(
    SELECT
        pf.function_id,
        pf.name,
        pf.boundary_value_on_right,
        t.name AS TypeName
    FROM sys.partition_functions pf
    JOIN sys.partition_parameters pp
      ON pp.function_id = pf.function_id
    JOIN sys.types t
      ON t.user_type_id = pp.user_type_id
)
INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'CREATE PARTITION FUNCTION ' + QUOTENAME(pf.name)
    + N' (' + pf.TypeName + N') AS RANGE '
    + CASE WHEN pf.boundary_value_on_right = 1 THEN N'RIGHT' ELSE N'LEFT' END
    + N' FOR VALUES ('
    + STUFF((
        SELECT
            N', ' +
            CASE
                WHEN prv.value IS NULL THEN N'NULL'
                WHEN SQL_VARIANT_PROPERTY(prv.value, 'BaseType') IN ('char','varchar','nchar','nvarchar')
                    THEN N'''' + REPLACE(CONVERT(NVARCHAR(MAX), prv.value), '''', '''''') + N''''
                WHEN SQL_VARIANT_PROPERTY(prv.value, 'BaseType') IN ('date','datetime','datetime2','smalldatetime','datetimeoffset','time')
                    THEN N'''' + CONVERT(NVARCHAR(50), CONVERT(DATETIME2, prv.value), 126) + N''''
                ELSE CONVERT(NVARCHAR(MAX), prv.value)
            END
        FROM sys.partition_range_values prv
        WHERE prv.function_id = pf.function_id
        ORDER BY prv.boundary_id
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 2, N'')
    + N');'
FROM pf
ORDER BY pf.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 3) PARTITION SCHEMES
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- PARTITION SCHEMES');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'CREATE PARTITION SCHEME ' + QUOTENAME(ps.name)
    + N' AS PARTITION ' + QUOTENAME(pf.name)
    + N' TO (' +
    STUFF((
        SELECT N', ' + QUOTENAME(ds.name)
        FROM sys.destination_data_spaces dds
        JOIN sys.data_spaces ds
          ON ds.data_space_id = dds.data_space_id
        WHERE dds.partition_scheme_id = ps.data_space_id
        ORDER BY dds.destination_id
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 2, N'')
    + N');'
FROM sys.partition_schemes ps
JOIN sys.partition_functions pf
  ON pf.function_id = ps.function_id
ORDER BY ps.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 4) USER-DEFINED TABLE TYPES
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- USER-DEFINED TABLE TYPES');

DECLARE
    @TypeSchema SYSNAME,
    @TypeName SYSNAME,
    @TypeTableObjectId INT,
    @TypeSql NVARCHAR(MAX);

DECLARE type_cursor CURSOR FAST_FORWARD FOR
SELECT
    s.name,
    tt.name,
    tt.type_table_object_id
FROM sys.table_types tt
JOIN sys.schemas s
  ON s.schema_id = tt.schema_id
WHERE tt.is_user_defined = 1
ORDER BY s.name, tt.name;

OPEN type_cursor;
FETCH NEXT FROM type_cursor INTO @TypeSchema, @TypeName, @TypeTableObjectId;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @TypeSql = N'CREATE TYPE ' + QUOTENAME(@TypeSchema) + N'.' + QUOTENAME(@TypeName) + N' AS TABLE (' + @CRLF;

    ;WITH cols AS
    (
        SELECT
            c.column_id,
            c.name AS ColumnName,
            ty.name AS TypeName,
            c.max_length,
            c.precision,
            c.scale,
            c.is_nullable,
            c.collation_name,
            c.is_computed
        FROM sys.columns c
        JOIN sys.types ty
          ON ty.user_type_id = c.user_type_id
        WHERE c.object_id = @TypeTableObjectId
    )
    SELECT @TypeSql = @TypeSql +
        STUFF((
            SELECT
                N',' + @CRLF + N'    ' + QUOTENAME(ColumnName) + N' ' +
                CASE
                    WHEN TypeName IN ('varchar','char','varbinary','binary')
                        THEN TypeName + N'(' + CASE WHEN max_length = -1 THEN N'MAX' ELSE CAST(max_length AS NVARCHAR(10)) END + N')'
                    WHEN TypeName IN ('nvarchar','nchar')
                        THEN TypeName + N'(' + CASE WHEN max_length = -1 THEN N'MAX' ELSE CAST(max_length / 2 AS NVARCHAR(10)) END + N')'
                    WHEN TypeName IN ('decimal','numeric')
                        THEN TypeName + N'(' + CAST(precision AS NVARCHAR(10)) + N',' + CAST(scale AS NVARCHAR(10)) + N')'
                    WHEN TypeName IN ('datetime2','time','datetimeoffset')
                        THEN TypeName + N'(' + CAST(scale AS NVARCHAR(10)) + N')'
                    ELSE TypeName
                END
                + CASE
                    WHEN collation_name IS NOT NULL AND TypeName IN ('varchar','char','nvarchar','nchar','text','ntext')
                        THEN N' COLLATE ' + collation_name
                    ELSE N''
                  END
                + CASE WHEN is_nullable = 1 THEN N' NULL' ELSE N' NOT NULL' END
            FROM cols
            ORDER BY column_id
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 3, N'    ')
        + @CRLF + N');' + @CRLF + N'GO';

    INSERT INTO #ScriptOut (ScriptLine) VALUES (@TypeSql);

    FETCH NEXT FROM type_cursor INTO @TypeSchema, @TypeName, @TypeTableObjectId;
END

CLOSE type_cursor;
DEALLOCATE type_cursor;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 5) SEQUENCES
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- SEQUENCES');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'CREATE SEQUENCE ' + QUOTENAME(sc.name) + N'.' + QUOTENAME(seq.name)
    + N' AS ' + bt.name
    + N' START WITH ' + CAST(seq.start_value AS NVARCHAR(50))
    + N' INCREMENT BY ' + CAST(seq.increment AS NVARCHAR(50))
    + CASE WHEN seq.minimum_value IS NOT NULL THEN N' MINVALUE ' + CAST(seq.minimum_value AS NVARCHAR(50)) ELSE N'' END
    + CASE WHEN seq.maximum_value IS NOT NULL THEN N' MAXVALUE ' + CAST(seq.maximum_value AS NVARCHAR(50)) ELSE N'' END
    + CASE WHEN seq.is_cycling = 1 THEN N' CYCLE' ELSE N' NO CYCLE' END
    + CASE WHEN seq.is_cached = 1 THEN N' CACHE ' + CAST(seq.cache_size AS NVARCHAR(50)) ELSE N' NO CACHE' END
    + N';'
FROM sys.sequences seq
JOIN sys.schemas sc
  ON sc.schema_id = seq.schema_id
JOIN sys.types bt
  ON bt.user_type_id = seq.system_type_id
ORDER BY sc.name, seq.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 6) TABLES
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- TABLES');

DECLARE
    @SchemaName SYSNAME,
    @TableName SYSNAME,
    @ObjectId INT,
    @TableSql NVARCHAR(MAX),
    @DataSpaceClause NVARCHAR(MAX);

DECLARE table_cursor CURSOR FAST_FORWARD FOR
SELECT
    s.name,
    t.name,
    t.object_id
FROM sys.tables t
JOIN sys.schemas s
  ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName, @ObjectId;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @TableSql = N'CREATE TABLE ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName) + N' (' + @CRLF;

    ;WITH cols AS
    (
        SELECT
            c.column_id,
            c.name AS ColumnName,
            ty.name AS TypeName,
            c.max_length,
            c.precision,
            c.scale,
            c.is_nullable,
            c.is_identity,
            c.collation_name,
            c.is_computed,
            cc.definition AS ComputedDefinition,
            cc.is_persisted,
            ic.seed_value,
            ic.increment_value
        FROM sys.columns c
        JOIN sys.types ty
          ON c.user_type_id = ty.user_type_id
        LEFT JOIN sys.computed_columns cc
          ON cc.object_id = c.object_id
         AND cc.column_id = c.column_id
        LEFT JOIN sys.identity_columns ic
          ON ic.object_id = c.object_id
         AND ic.column_id = c.column_id
        WHERE c.object_id = @ObjectId
    )
    SELECT @TableSql = @TableSql +
        STUFF((
            SELECT
                N',' + @CRLF + N'    ' + QUOTENAME(ColumnName) + N' ' +
                CASE
                    WHEN is_computed = 1
                        THEN N'AS ' + ComputedDefinition + CASE WHEN is_persisted = 1 THEN N' PERSISTED' ELSE N'' END
                    ELSE
                        CASE
                            WHEN TypeName IN ('varchar','char','varbinary','binary')
                                THEN TypeName + N'(' + CASE WHEN max_length = -1 THEN N'MAX' ELSE CAST(max_length AS NVARCHAR(10)) END + N')'
                            WHEN TypeName IN ('nvarchar','nchar')
                                THEN TypeName + N'(' + CASE WHEN max_length = -1 THEN N'MAX' ELSE CAST(max_length / 2 AS NVARCHAR(10)) END + N')'
                            WHEN TypeName IN ('decimal','numeric')
                                THEN TypeName + N'(' + CAST(precision AS NVARCHAR(10)) + N',' + CAST(scale AS NVARCHAR(10)) + N')'
                            WHEN TypeName IN ('datetime2','time','datetimeoffset')
                                THEN TypeName + N'(' + CAST(scale AS NVARCHAR(10)) + N')'
                            ELSE TypeName
                        END
                        + CASE
                            WHEN collation_name IS NOT NULL AND TypeName IN ('varchar','char','nvarchar','nchar','text','ntext')
                                THEN N' COLLATE ' + collation_name
                            ELSE N''
                          END
                        + CASE
                            WHEN is_identity = 1
                                THEN N' IDENTITY(' + CAST(seed_value AS NVARCHAR(30)) + N',' + CAST(increment_value AS NVARCHAR(30)) + N')'
                            ELSE N''
                          END
                        + CASE WHEN is_nullable = 1 THEN N' NULL' ELSE N' NOT NULL' END
                END
            FROM cols
            ORDER BY column_id
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 3, N'    ')
        + @CRLF + N')';

    SELECT TOP (1)
        @DataSpaceClause =
            CASE
                WHEN ps.name IS NOT NULL THEN N' ON ' + QUOTENAME(ps.name) + N'(' + QUOTENAME(c.name) + N')'
                WHEN ds.name IS NOT NULL AND ds.type = 'FG' THEN N' ON ' + QUOTENAME(ds.name)
                ELSE N''
            END
    FROM sys.indexes i
    LEFT JOIN sys.data_spaces ds
      ON ds.data_space_id = i.data_space_id
    LEFT JOIN sys.partition_schemes ps
      ON ps.data_space_id = i.data_space_id
    LEFT JOIN sys.index_columns ic
      ON ic.object_id = i.object_id
     AND ic.index_id = i.index_id
     AND ic.partition_ordinal = 1
    LEFT JOIN sys.columns c
      ON c.object_id = ic.object_id
     AND c.column_id = ic.column_id
    WHERE i.object_id = @ObjectId
      AND i.index_id IN (0,1)
    ORDER BY i.index_id DESC;

    SET @TableSql = @TableSql + ISNULL(@DataSpaceClause, N'') + N';' + @CRLF + N'GO';

    INSERT INTO #ScriptOut (ScriptLine) VALUES (@TableSql);

    FETCH NEXT FROM table_cursor INTO @SchemaName, @TableName, @ObjectId;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 7) DEFAULT CONSTRAINTS
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- DEFAULT CONSTRAINTS');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'ALTER TABLE ' + QUOTENAME(sc.name) + N'.' + QUOTENAME(t.name)
    + N' ADD CONSTRAINT ' + QUOTENAME(dc.name)
    + N' DEFAULT ' + dc.definition
    + N' FOR ' + QUOTENAME(c.name) + N';'
FROM sys.default_constraints dc
JOIN sys.tables t
  ON t.object_id = dc.parent_object_id
JOIN sys.schemas sc
  ON sc.schema_id = t.schema_id
JOIN sys.columns c
  ON c.object_id = dc.parent_object_id
 AND c.column_id = dc.parent_column_id
WHERE t.is_ms_shipped = 0
ORDER BY sc.name, t.name, dc.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 8) CHECK CONSTRAINTS
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- CHECK CONSTRAINTS');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'ALTER TABLE ' + QUOTENAME(sc.name) + N'.' + QUOTENAME(t.name)
    + N' WITH ' + CASE WHEN cc.is_not_trusted = 1 THEN N'NOCHECK' ELSE N'CHECK' END
    + N' ADD CONSTRAINT ' + QUOTENAME(cc.name)
    + N' CHECK ' + CASE WHEN cc.is_not_for_replication = 1 THEN N'NOT FOR REPLICATION ' ELSE N'' END
    + cc.definition + N';'
FROM sys.check_constraints cc
JOIN sys.tables t
  ON t.object_id = cc.parent_object_id
JOIN sys.schemas sc
  ON sc.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
ORDER BY sc.name, t.name, cc.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'ALTER TABLE ' + QUOTENAME(sc.name) + N'.' + QUOTENAME(t.name)
    + N' ' + CASE WHEN cc.is_disabled = 1 THEN N'NOCHECK' ELSE N'CHECK' END
    + N' CONSTRAINT ' + QUOTENAME(cc.name) + N';'
FROM sys.check_constraints cc
JOIN sys.tables t
  ON t.object_id = cc.parent_object_id
JOIN sys.schemas sc
  ON sc.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
ORDER BY sc.name, t.name, cc.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 9) PRIMARY KEYS / UNIQUE CONSTRAINTS
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- PRIMARY KEYS / UNIQUE CONSTRAINTS');

;WITH kc AS
(
    SELECT
        kc.name AS ConstraintName,
        kc.type_desc,
        s.name AS SchemaName,
        t.name AS TableName,
        kc.parent_object_id,
        kc.unique_index_id
    FROM sys.key_constraints kc
    JOIN sys.tables t
      ON t.object_id = kc.parent_object_id
    JOIN sys.schemas s
      ON s.schema_id = t.schema_id
    WHERE t.is_ms_shipped = 0
)
INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'ALTER TABLE ' + QUOTENAME(k.SchemaName) + N'.' + QUOTENAME(k.TableName)
    + N' ADD CONSTRAINT ' + QUOTENAME(k.ConstraintName)
    + N' ' + CASE WHEN k.type_desc = 'PRIMARY_KEY_CONSTRAINT' THEN N'PRIMARY KEY ' ELSE N'UNIQUE ' END
    + CASE WHEN i.type_desc LIKE '%CLUSTERED%' THEN N'CLUSTERED' ELSE N'NONCLUSTERED' END
    + N' (' +
    STUFF((
        SELECT
            N', ' + QUOTENAME(c.name) + CASE WHEN ic.is_descending_key = 1 THEN N' DESC' ELSE N' ASC' END
        FROM sys.index_columns ic
        JOIN sys.columns c
          ON c.object_id = ic.object_id
         AND c.column_id = ic.column_id
        WHERE ic.object_id = k.parent_object_id
          AND ic.index_id = k.unique_index_id
          AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 2, N'')
    + N')'
    + CASE
        WHEN ds.name IS NOT NULL AND ds.type = 'FG' THEN N' ON ' + QUOTENAME(ds.name)
        WHEN ps.name IS NOT NULL THEN
            N' ON ' + QUOTENAME(ps.name) + N'(' +
            ISNULL((
                SELECT TOP (1) QUOTENAME(c2.name)
                FROM sys.index_columns ic2
                JOIN sys.columns c2
                  ON c2.object_id = ic2.object_id
                 AND c2.column_id = ic2.column_id
                WHERE ic2.object_id = i.object_id
                  AND ic2.index_id = i.index_id
                  AND ic2.partition_ordinal = 1
            ), N'')
            + N')'
        ELSE N''
      END
    + N';'
FROM kc k
JOIN sys.indexes i
  ON i.object_id = k.parent_object_id
 AND i.index_id = k.unique_index_id
LEFT JOIN sys.data_spaces ds
  ON ds.data_space_id = i.data_space_id
LEFT JOIN sys.partition_schemes ps
  ON ps.data_space_id = i.data_space_id
ORDER BY k.SchemaName, k.TableName, k.ConstraintName;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 10) INDEXES (excluding PK/unique constraint backing indexes)
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- INDEXES');

;WITH idx AS
(
    SELECT
        s.name AS SchemaName,
        t.name AS TableName,
        i.name AS IndexName,
        i.object_id,
        i.index_id,
        i.type_desc,
        i.is_unique,
        i.has_filter,
        i.filter_definition,
        i.fill_factor,
        i.is_padded,
        i.ignore_dup_key,
        i.allow_row_locks,
        i.allow_page_locks,
        i.data_space_id
    FROM sys.indexes i
    JOIN sys.tables t
      ON t.object_id = i.object_id
    JOIN sys.schemas s
      ON s.schema_id = t.schema_id
    WHERE t.is_ms_shipped = 0
      AND i.index_id > 0
      AND i.is_hypothetical = 0
      AND i.name IS NOT NULL
      AND NOT EXISTS
      (
          SELECT 1
          FROM sys.key_constraints kc
          WHERE kc.parent_object_id = i.object_id
            AND kc.unique_index_id = i.index_id
      )
)
INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'CREATE '
    + CASE WHEN i.is_unique = 1 THEN N'UNIQUE ' ELSE N'' END
    + CASE
        WHEN i.type_desc = 'CLUSTERED' THEN N'CLUSTERED '
        WHEN i.type_desc = 'NONCLUSTERED' THEN N'NONCLUSTERED '
        WHEN i.type_desc = 'XML' THEN N'XML '
        ELSE N''
      END
    + N'INDEX ' + QUOTENAME(i.IndexName)
    + N' ON ' + QUOTENAME(i.SchemaName) + N'.' + QUOTENAME(i.TableName)
    + N' (' +
    STUFF((
        SELECT
            N', ' + QUOTENAME(c.name) + CASE WHEN ic.is_descending_key = 1 THEN N' DESC' ELSE N' ASC' END
        FROM sys.index_columns ic
        JOIN sys.columns c
          ON c.object_id = ic.object_id
         AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.key_ordinal > 0
          AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 2, N'')
    + N')'
    + CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM sys.index_columns ic
            WHERE ic.object_id = i.object_id
              AND ic.index_id = i.index_id
              AND ic.is_included_column = 1
        )
        THEN
            N' INCLUDE (' +
            STUFF((
                SELECT
                    N', ' + QUOTENAME(c.name)
                FROM sys.index_columns ic
                JOIN sys.columns c
                  ON c.object_id = ic.object_id
                 AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 1
                ORDER BY c.column_id
                FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(max)'), 1, 2, N'')
            + N')'
        ELSE N''
      END
    + CASE WHEN i.has_filter = 1 THEN N' WHERE ' + i.filter_definition ELSE N'' END
    + CASE
        WHEN ds.name IS NOT NULL AND ds.type = 'FG' THEN N' ON ' + QUOTENAME(ds.name)
        WHEN ps.name IS NOT NULL THEN
            N' ON ' + QUOTENAME(ps.name) + N'(' +
            ISNULL((
                SELECT TOP (1) QUOTENAME(c2.name)
                FROM sys.index_columns ic2
                JOIN sys.columns c2
                  ON c2.object_id = ic2.object_id
                 AND c2.column_id = ic2.column_id
                WHERE ic2.object_id = i.object_id
                  AND ic2.index_id = i.index_id
                  AND ic2.partition_ordinal = 1
            ), N'')
            + N')'
        ELSE N''
      END
    + CASE
        WHEN i.type_desc IN ('CLUSTERED','NONCLUSTERED') THEN
            N' WITH ('
            + N'PAD_INDEX = ' + CASE WHEN i.is_padded = 1 THEN N'ON' ELSE N'OFF' END
            + N', FILLFACTOR = ' + CAST(i.fill_factor AS NVARCHAR(10))
            + N', IGNORE_DUP_KEY = ' + CASE WHEN i.ignore_dup_key = 1 THEN N'ON' ELSE N'OFF' END
            + N', ALLOW_ROW_LOCKS = ' + CASE WHEN i.allow_row_locks = 1 THEN N'ON' ELSE N'OFF' END
            + N', ALLOW_PAGE_LOCKS = ' + CASE WHEN i.allow_page_locks = 1 THEN N'ON' ELSE N'OFF' END
            + N')'
        ELSE N''
      END
    + N';'
FROM idx i
LEFT JOIN sys.data_spaces ds
  ON ds.data_space_id = i.data_space_id
LEFT JOIN sys.partition_schemes ps
  ON ps.data_space_id = i.data_space_id
ORDER BY i.SchemaName, i.TableName, i.IndexName;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 11) FOREIGN KEYS
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- FOREIGN KEYS');

;WITH fkdata AS
(
    SELECT
        fk.object_id AS FkObjectId,
        fk.name AS FkName,
        sp.name AS ParentSchema,
        tp.name AS ParentTable,
        sr.name AS RefSchema,
        tr.name AS RefTable,
        fk.delete_referential_action_desc AS DeleteAction,
        fk.update_referential_action_desc AS UpdateAction,
        fk.is_not_trusted,
        fk.is_disabled,
        fk.is_not_for_replication
    FROM sys.foreign_keys fk
    JOIN sys.tables tp
      ON tp.object_id = fk.parent_object_id
    JOIN sys.schemas sp
      ON sp.schema_id = tp.schema_id
    JOIN sys.tables tr
      ON tr.object_id = fk.referenced_object_id
    JOIN sys.schemas sr
      ON sr.schema_id = tr.schema_id
)
INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'ALTER TABLE ' + QUOTENAME(f.ParentSchema) + N'.' + QUOTENAME(f.ParentTable)
    + N' WITH ' + CASE WHEN f.is_not_trusted = 1 THEN N'NOCHECK' ELSE N'CHECK' END
    + N' ADD CONSTRAINT ' + QUOTENAME(f.FkName)
    + N' FOREIGN KEY (' +
    STUFF((
        SELECT N', ' + QUOTENAME(cp.name)
        FROM sys.foreign_key_columns fkc
        JOIN sys.columns cp
          ON cp.object_id = fkc.parent_object_id
         AND cp.column_id = fkc.parent_column_id
        WHERE fkc.constraint_object_id = f.FkObjectId
        ORDER BY fkc.constraint_column_id
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 2, N'')
    + N') REFERENCES ' + QUOTENAME(f.RefSchema) + N'.' + QUOTENAME(f.RefTable)
    + N' (' +
    STUFF((
        SELECT N', ' + QUOTENAME(cr.name)
        FROM sys.foreign_key_columns fkc
        JOIN sys.columns cr
          ON cr.object_id = fkc.referenced_object_id
         AND cr.column_id = fkc.referenced_column_id
        WHERE fkc.constraint_object_id = f.FkObjectId
        ORDER BY fkc.constraint_column_id
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 2, N'')
    + N')'
    + CASE WHEN f.DeleteAction <> 'NO_ACTION' THEN N' ON DELETE ' + REPLACE(f.DeleteAction, '_', ' ') ELSE N'' END
    + CASE WHEN f.UpdateAction <> 'NO_ACTION' THEN N' ON UPDATE ' + REPLACE(f.UpdateAction, '_', ' ') ELSE N'' END
    + CASE WHEN f.is_not_for_replication = 1 THEN N' NOT FOR REPLICATION' ELSE N'' END
    + N';'
FROM fkdata f
ORDER BY f.ParentSchema, f.ParentTable, f.FkName;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'ALTER TABLE ' + QUOTENAME(f.ParentSchema) + N'.' + QUOTENAME(f.ParentTable)
    + N' ' + CASE WHEN f.is_disabled = 1 THEN N'NOCHECK' ELSE N'CHECK' END
    + N' CONSTRAINT ' + QUOTENAME(f.FkName) + N';'
FROM
(
    SELECT
        fk.name AS FkName,
        sp.name AS ParentSchema,
        tp.name AS ParentTable,
        fk.is_disabled
    FROM sys.foreign_keys fk
    JOIN sys.tables tp
      ON tp.object_id = fk.parent_object_id
    JOIN sys.schemas sp
      ON sp.schema_id = tp.schema_id
) f
ORDER BY f.ParentSchema, f.ParentTable, f.FkName;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 12) VIEWS
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- VIEWS');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    OBJECT_DEFINITION(v.object_id) + @CRLF + N'GO'
FROM sys.views v
JOIN sys.schemas s
  ON s.schema_id = v.schema_id
WHERE OBJECT_DEFINITION(v.object_id) IS NOT NULL
ORDER BY s.name, v.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 13) FUNCTIONS
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- FUNCTIONS');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    OBJECT_DEFINITION(o.object_id) + @CRLF + N'GO'
FROM sys.objects o
JOIN sys.schemas s
  ON s.schema_id = o.schema_id
WHERE o.type IN ('FN','IF','TF')
  AND OBJECT_DEFINITION(o.object_id) IS NOT NULL
ORDER BY s.name, o.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 14) STORED PROCEDURES
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- STORED PROCEDURES');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    OBJECT_DEFINITION(p.object_id) + @CRLF + N'GO'
FROM sys.procedures p
JOIN sys.schemas s
  ON s.schema_id = p.schema_id
WHERE OBJECT_DEFINITION(p.object_id) IS NOT NULL
ORDER BY s.name, p.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 15) TRIGGERS
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- TRIGGERS');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    OBJECT_DEFINITION(t.object_id) + @CRLF + N'GO'
FROM sys.triggers t
WHERE t.parent_class_desc = 'OBJECT_OR_COLUMN'
  AND OBJECT_DEFINITION(t.object_id) IS NOT NULL
ORDER BY t.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- 16) SYNONYMS
------------------------------------------------------------
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'-- SYNONYMS');

INSERT INTO #ScriptOut (ScriptLine)
SELECT
    N'CREATE SYNONYM ' + QUOTENAME(s.name) + N'.' + QUOTENAME(sn.name)
    + N' FOR ' + sn.base_object_name + N';'
FROM sys.synonyms sn
JOIN sys.schemas s
  ON s.schema_id = sn.schema_id
ORDER BY s.name, sn.name;

INSERT INTO #ScriptOut (ScriptLine) VALUES (N'GO');
INSERT INTO #ScriptOut (ScriptLine) VALUES (N'');

------------------------------------------------------------
-- OUTPUT
------------------------------------------------------------
SELECT ScriptLine
FROM #ScriptOut
ORDER BY RowNum;