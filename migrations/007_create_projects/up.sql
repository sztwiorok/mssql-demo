CREATE TABLE Projects (
    ProjectId INT IDENTITY(1,1) PRIMARY KEY,
    ProjectName NVARCHAR(100) NOT NULL,
    StartDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    EndDate DATETIME2 NULL,
    Status NVARCHAR(20) DEFAULT 'Active'
);
GO

INSERT INTO Projects (ProjectName, Status) VALUES 
('Internal Tools', 'Active'),
('Website Redesign', 'Pending');
GO

