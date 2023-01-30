IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$(DBName)')
	CREATE DATABASE [$(DBName)]
GO
