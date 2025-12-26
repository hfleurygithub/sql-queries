/*
Search across all ONLINE databases for:
- Table names
- Column names
- Stored procedures/views by name and/or by definition

SQL Server 2025 compatible.
Set the parameters below and run.
*/

DECLARE @Find               NVARCHAR(200) = N'Customer';  -- text to search
DECLARE @SearchTables       BIT = 1;                      -- table names
DECLARE @SearchColumns      BIT = 1;                      -- column names
DECLARE @SearchProcViewName BIT = 1;                      -- proc/view names
DECLARE @SearchProcViewDef  BIT = 1;                      -- proc/view definitions
DECLARE @IncludeSystemDBs   BIT = 0;                      -- include master/msdb/model/tempdb
DECLARE @DatabasesCsv       NVARCHAR(MAX) = NULL;         -- optional: 'DB1,DB2,DB3' (NULL = all)

IF OBJECT_ID('tempdb..#SearchResults') IS NOT NULL DROP TABLE #SearchResults;

CREATE TABLE #SearchResults
(
    DatabaseName SYSNAME,
    SchemaName   SYSNAME NULL,
    ObjectName   SYSNAME NULL,        -- Table / Proc / View
    ObjectType   NVARCHAR(60) NULL,   -- TABLE / SQL_STORED_PROCEDURE / VIEW
    ColumnName   SYSNAME NULL,        -- Only populated for column matches
    MatchType    NVARCHAR(40) NOT NULL
);

IF OBJECT_ID('tempdb..#DbList') IS NOT NULL DROP TABLE #DbList;
CREATE TABLE #DbList (DatabaseName SYSNAME PRIMARY KEY);

IF @DatabasesCsv IS NULL
BEGIN
    INSERT INTO #DbList(DatabaseName)
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND (
            @IncludeSystemDBs = 1
            OR name NOT IN ('master','tempdb','model','msdb')
          );
END
ELSE
BEGIN
    INSERT INTO #DbList(DatabaseName)
    SELECT LTRIM(RTRIM([value]))
    FROM string_split(@DatabasesCsv, ',')
    WHERE LTRIM(RTRIM([value])) <> '';
END

DECLARE @db SYSNAME;
DECLARE @sql NVARCHAR(MAX);
DECLARE @dbLiteral NVARCHAR(300); -- escaped db name for string literal

DECLARE db_cur CURSOR FAST_FORWARD FOR
SELECT DatabaseName FROM #DbList ORDER BY DatabaseName;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'';
    SET @dbLiteral = REPLACE(@db, N'''', N''''''); -- escape quotes for literal

    /* ---- Tables by name ---- */
    IF @SearchTables = 1
    BEGIN
        SET @sql = @sql + N'
INSERT INTO #SearchResults (DatabaseName, SchemaName, ObjectName, ObjectType, ColumnName, MatchType)
SELECT
    N''' + @dbLiteral + N''' AS DatabaseName,
    s.name    AS SchemaName,
    t.name    AS ObjectName,
    N''TABLE'' AS ObjectType,
    NULL      AS ColumnName,
    N''TableName'' AS MatchType
FROM ' + QUOTENAME(@db) + N'.sys.tables  AS t
JOIN ' + QUOTENAME(@db) + N'.sys.schemas AS s ON s.schema_id = t.schema_id
WHERE t.name LIKE @pattern;
';
    END

    /* ---- Columns by name ---- */
    IF @SearchColumns = 1
    BEGIN
        SET @sql = @sql + N'
INSERT INTO #SearchResults (DatabaseName, SchemaName, ObjectName, ObjectType, ColumnName, MatchType)
SELECT
    N''' + @dbLiteral + N''' AS DatabaseName,
    s.name    AS SchemaName,
    t.name    AS ObjectName,
    N''TABLE'' AS ObjectType,
    c.name    AS ColumnName,
    N''ColumnName'' AS MatchType
FROM ' + QUOTENAME(@db) + N'.sys.columns AS c
JOIN ' + QUOTENAME(@db) + N'.sys.tables  AS t ON t.object_id = c.object_id
JOIN ' + QUOTENAME(@db) + N'.sys.schemas AS s ON s.schema_id = t.schema_id
WHERE c.name LIKE @pattern;
';
    END

    /* ---- Procs/Views by object name ---- */
    IF @SearchProcViewName = 1
    BEGIN
        SET @sql = @sql + N'
INSERT INTO #SearchResults (DatabaseName, SchemaName, ObjectName, ObjectType, ColumnName, MatchType)
SELECT
    N''' + @dbLiteral + N''' AS DatabaseName,
    s.name    AS SchemaName,
    o.name    AS ObjectName,
    o.type_desc AS ObjectType,
    NULL      AS ColumnName,
    N''ObjectName'' AS MatchType
FROM ' + QUOTENAME(@db) + N'.sys.objects AS o
JOIN ' + QUOTENAME(@db) + N'.sys.schemas AS s ON s.schema_id = o.schema_id
WHERE o.type IN (''P'',''V'')      -- P=Stored Proc, V=View
  AND o.name LIKE @pattern;
';
    END

    /* ---- Procs/Views by definition ---- */
    IF @SearchProcViewDef = 1
    BEGIN
        SET @sql = @sql + N'
INSERT INTO #SearchResults (DatabaseName, SchemaName, ObjectName, ObjectType, ColumnName, MatchType)
SELECT
    N''' + @dbLiteral + N''' AS DatabaseName,
    s.name    AS SchemaName,
    o.name    AS ObjectName,
    o.type_desc AS ObjectType,
    NULL      AS ColumnName,
    N''Definition'' AS MatchType
FROM ' + QUOTENAME(@db) + N'.sys.sql_modules AS m
JOIN ' + QUOTENAME(@db) + N'.sys.objects     AS o ON o.object_id = m.object_id
JOIN ' + QUOTENAME(@db) + N'.sys.schemas     AS s ON s.schema_id = o.schema_id
WHERE o.type IN (''P'',''V'')
  AND m.definition LIKE @pattern;
';
    END

    IF @sql <> N''
    BEGIN
        DECLARE @pattern NVARCHAR(4000) = N'%' + @Find + N'%';

        EXEC sys.sp_executesql
            @stmt   = @sql,
            @params = N'@pattern NVARCHAR(4000)',
            @pattern = @pattern;
    END

    FETCH NEXT FROM db_cur INTO @db;
END

CLOSE db_cur;
DEALLOCATE db_cur;

SELECT
    DatabaseName,
    SchemaName,
    ObjectName,
    ObjectType,
    ColumnName,
    MatchType
FROM #SearchResults
ORDER BY DatabaseName, MatchType, ObjectType, SchemaName, ObjectName, ColumnName;
