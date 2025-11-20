CREATE TABLE Groups (
    GroupId INT IDENTITY(1,1) PRIMARY KEY,
    GroupName NVARCHAR(100) NOT NULL UNIQUE,
    CreatedBy INT NULL,
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

INSERT INTO Groups (GroupName) VALUES ('Engineering'), ('HR'), ('Sales');
GO

