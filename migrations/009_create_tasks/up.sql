CREATE TABLE Tasks (
    TaskId INT IDENTITY(1,1) PRIMARY KEY,
    ProjectId INT NOT NULL,
    Title NVARCHAR(100) NOT NULL,
    IsCompleted BIT DEFAULT 0,
    FOREIGN KEY (ProjectId) REFERENCES Projects(ProjectId)
);
GO

