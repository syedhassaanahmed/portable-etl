IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProcessedData]') AND type in (N'U'))
	CREATE TABLE [dbo].[ProcessedData](
		[deviceId] [nvarchar](max) NOT NULL,
		[deviceTimestamp] [datetime2] NOT NULL,
		[ingestionTimestamp] [datetime2] NOT NULL,
		[doubleValue] [float] NOT NULL,
		[roomId] [nvarchar](max) NOT NULL,
        [dbTimestamp] AS CAST(GETUTCDATE() AS datetime2)
	)
GO
