USE [master]
GO
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'MigrationUser')
BEGIN
    CREATE LOGIN [MigrationUser] WITH PASSWORD=N'StrongPassword123!', DEFAULT_DATABASE=[MigrationTestDB], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
    PRINT 'Login [MigrationUser] created.'
END
ELSE
BEGIN
    PRINT 'Login [MigrationUser] already exists.'
END
GO

USE [MigrationTestDB]
GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'MigrationUser')
BEGIN
    CREATE USER [MigrationUser] FOR LOGIN [MigrationUser]
    PRINT 'User [MigrationUser] created in database.'
END
ELSE
BEGIN
    PRINT 'User [MigrationUser] already exists in database.'
END
GO

ALTER ROLE [db_owner] ADD MEMBER [MigrationUser]
GO
PRINT 'User [MigrationUser] added to db_owner role.'
GO

