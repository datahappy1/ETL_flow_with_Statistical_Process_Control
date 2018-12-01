/* ==Scripting Parameters==

Source Server Version : SQL Server 2017 (14.0.1000)
 Source Database Engine Edition : Microsoft SQL Server Enterprise Edition
 Source Database Engine Type : Standalone SQL Server

Target Server Version : SQL Server 2017
 Target Database Engine Edition : Microsoft SQL Server Enterprise Edition
 Target Database Engine Type : Standalone SQL Server
*/

USE [master]
GO

CREATE DATABASE [Logger]
GO

USE [Logger]
GO
/****** Object: Table [dbo].[Logger_History] Script Date: 4/13/2018 5:32:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Logger_History](
 [Logger_History_ID] [int] IDENTITY(1,1) NOT NULL,
 [Execution_UTC_Datetime] [datetime] NULL,
 [Job_Name] [nvarchar](255) NULL,
 [Job_Status] [char](1) NULL,
 [Job_Last_Modified_By] [nvarchar](255) NULL,
 [Source_File_Type] [nvarchar](255) NULL,
 [Source_File_Name] [nvarchar](255) NULL,
 [Customer_Name] [nvarchar](255) NULL,
 [Data_Feed_Type] [nvarchar](255) NULL,
 [Server_Name] [nvarchar](255) NULL,
 [Stage_Name] [nvarchar](255) NULL,
 [Stage_Row_Count] [int] NULL,
 [Processing_Start_Datetime] [datetime] NULL,
 [Processing_End_Datetime] [datetime] NULL,
 [Processing_Duration] [int] NULL,
 [Moved_To_ES] [bit] NULL,
 [IsProcessed] [bit] NULL,
PRIMARY KEY CLUSTERED
(
 [Logger_History_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[Logger_History] ADD DEFAULT ((0)) FOR [Moved_To_ES]
GO
ALTER TABLE [dbo].[Logger_History] ADD DEFAULT ((0)) FOR [IsProcessed]
GO
/****** Object: StoredProcedure [dbo].[gen_3sigma_event] Script Date: 4/13/2018 5:32:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[gen_3sigma_event] AS
BEGIN

SET NOCOUNT ON;

BEGIN TRY
BEGIN TRANSACTION

--DECLARATIONS
 DECLARE @ID int, @gen_stmt nvarchar(2000);

SELECT
 Customer_Name,Data_Feed_Type,Stage_Name,
 AVG([Stage_Row_Count]) AS AVG_Stage_Row_Count,
 SQRT(VAR([Stage_Row_Count])) AS SDEV_Stage_Row_Count,
 AVG([Processing_Duration]) AS AVG_Processing_Duration,
 SQRT(VAR([Processing_Duration])) AS SDEV_Processing_Duration
 INTO #tmp_aggregations
 FROM [dbo].[Logger_History]
 GROUP BY Customer_Name,Data_Feed_Type,Stage_Name;

--CALCULATE SCP OUTLIERS
 SELECT
 i.[Logger_History_ID],i.[Execution_UTC_Datetime],
 i.[Sigma_Status_Stage_Row_Count],i.[Sigma_Status_Processing_Duration],
 i.[Stage_Row_Count],i.[Processing_Duration],
 i.[-3Sigma_Stage_Row_Count],i.[+3Sigma_Stage_Row_Count],
 i.[-3Sigma_Processing_Duration],i.[+3Sigma_Processing_Duration],
 i.Server_Name,i.Data_Feed_Type,i.Customer_Name,i.Stage_Name,i.Job_Name,i.Job_Status,
 i.Source_File_Type,i.Source_File_Name,i.[Processing_Start_Datetime],i.[Processing_End_Datetime]
 INTO #tmp_outliers
 FROM (
 SELECT
 --Row_Count Outlier calculation:
 CASE
 WHEN [Stage_Row_Count] >= ta.AVG_Stage_Row_Count-ta.SDEV_Stage_Row_Count and Stage_Row_Count <= ta.AVG_Stage_Row_Count + SDEV_Stage_Row_Count
 THEN 'Fits 1 Sigma'
 WHEN [Stage_Row_Count] >= ta.AVG_Stage_Row_Count-(2*SDEV_Stage_Row_Count) and Stage_Row_Count <= ta.AVG_Stage_Row_Count + (2*SDEV_Stage_Row_Count)
 THEN 'Fits 2 Sigma'
 WHEN [Stage_Row_Count] >= ta.AVG_Stage_Row_Count-(3*SDEV_Stage_Row_Count) and Stage_Row_Count <= ta.AVG_Stage_Row_Count + (3*SDEV_Stage_Row_Count)
 THEN 'Fits 3 Sigma'
 ELSE 'SCP Outlier'
 END AS Sigma_Status_Stage_Row_Count
 --,ta.[AVG_Stage_Row_Count] as MEAN,ta.SDEV_Stage_Row_Count as SDEV,ta.AVG_Stage_Row_Count-ta.SDEV_Stage_Row_Count AS [-1Sigma],ta.AVG_Stage_Row_Count+ta.SDEV_Stage_Row_Count AS [+1Sigma],ta.AVG_Stage_Row_Count-(2*ta.SDEV_Stage_Row_Count) AS [-2Sigma],ta.AVG_Stage_Row_Count+(2*ta.SDEV_Stage_Row_Count) AS [+2Sigma]
 ,ta.AVG_Stage_Row_Count - (3*SDEV_Stage_Row_Count) AS [-3Sigma_Stage_Row_Count]
 ,ta.AVG_Stage_Row_Count + (3*SDEV_Stage_Row_Count) AS [+3Sigma_Stage_Row_Count]

--Processing_Duration Outlier calculation:
 ,CASE
 WHEN [Processing_Duration] >= ta.AVG_Processing_Duration-ta.SDEV_Processing_Duration and Processing_Duration <= ta.AVG_Processing_Duration + SDEV_Processing_Duration
 THEN 'Fits 1 Sigma'
 WHEN [Processing_Duration] >= ta.AVG_Processing_Duration-(2*SDEV_Processing_Duration) and Processing_Duration <= ta.AVG_Processing_Duration + (2*SDEV_Processing_Duration)
 THEN 'Fits 2 Sigma'
 WHEN [Processing_Duration] >= ta.AVG_Processing_Duration-(3*SDEV_Processing_Duration) and Processing_Duration <= ta.AVG_Processing_Duration + (3*SDEV_Processing_Duration)
 THEN 'Fits 3 Sigma'
 ELSE 'SCP Outlier'
 END AS Sigma_Status_Processing_Duration
 --,ta.[AVG_Stage_Row_Count] as MEAN,ta.SDEV_Stage_Row_Count as SDEV,ta.AVG_Stage_Row_Count-ta.SDEV_Stage_Row_Count AS [-1Sigma],ta.AVG_Stage_Row_Count+ta.SDEV_Stage_Row_Count AS [+1Sigma],ta.AVG_Stage_Row_Count-(2*ta.SDEV_Stage_Row_Count) AS [-2Sigma],ta.AVG_Stage_Row_Count+(2*ta.SDEV_Stage_Row_Count) AS [+2Sigma]
 ,ta.AVG_Processing_Duration - (3*SDEV_Processing_Duration) AS [-3Sigma_Processing_Duration]
 ,ta.AVG_Processing_Duration + (3*SDEV_Processing_Duration) AS [+3Sigma_Processing_Duration]

,lm.*
 FROM [dbo].[Logger_History] lm
 INNER JOIN #tmp_aggregations ta
 ON lm.Customer_Name = ta.Customer_Name
 AND lm.Data_Feed_Type = ta.Data_Feed_Type
 AND lm.Stage_Name = ta.Stage_Name
 WHERE
 IsProcessed = 0 AND
 Moved_To_ES = 0
 ) i
 WHERE i.Sigma_Status_Stage_Row_Count = 'SCP Outlier'
 OR i.Sigma_Status_Processing_Duration = 'SCP Outlier' ;

 UPDATE [dbo].[Logger_History]
 SET [IsProcessed] = 1
 WHERE [IsProcessed] = 0;

--LOG SCP OUTLIERS TO WINDOWS EVENT LOG EVENTS
 WHILE EXISTS (SELECT * FROM #tmp_outliers)
 BEGIN

 SELECT TOP(1)
 @ID = [Logger_History_ID]
 FROM #tmp_outliers
 ORDER BY [Logger_History_ID];

SELECT @gen_stmt =
 'EXEC xp_logevent 60000,'+
 '''MESSAGE: !This is a SCP 3 Sigma Outlier based on '+
 CASE
 WHEN #tmp_outliers.[Sigma_Status_Stage_Row_Count] = 'SCP Outlier'
 THEN 'Stage Row Count'
 WHEN #tmp_outliers.[Sigma_Status_Processing_Duration] = 'SCP Outlier'
 THEN 'Processing Duration'
 WHEN #tmp_outliers.[Sigma_Status_Stage_Row_Count] = 'SCP Outlier'
 AND #tmp_outliers.[Sigma_Status_Processing_Duration] = 'SCP Outlier'
 THEN 'Stage Row Count AND Processing Duration'
 END +';'+CHAR(10)+
 'Customer: '+#tmp_outliers.[Customer_Name]+' ;'+CHAR(10)+
 'Job Name: '+#tmp_outliers.[Job_Name]+' ;'+CHAR(10)+
 'Job Status: '+#tmp_outliers.[Job_Status]+' ;'+CHAR(10)+
 'Execution UTC Datetime: '+CAST(#tmp_outliers.[Execution_UTC_Datetime] AS VARCHAR(20))+' ;'+CHAR(10)+
 'Source File Type: '+#tmp_outliers.[Source_File_Type]+' ;'+CHAR(10)+
 'Source File Name: '+#tmp_outliers.[Source_File_Name]+' ;'+CHAR(10)+
 'Data Feed Type: '+#tmp_outliers.[Data_Feed_Type]+' ;'+CHAR(10)+
 'Server Name: '+#tmp_outliers.[Server_Name]+' ;'+CHAR(10)+
 'Stage Name: '+#tmp_outliers.[Stage_Name]+' ;'+CHAR(10)+
 'Stage_Row_Count: '+CAST(#tmp_outliers.[Stage_Row_Count] AS VARCHAR(10))+' ;'+CHAR(10)+
 'Processing_Duration: '+CAST(#tmp_outliers.[Processing_Duration] AS VARCHAR(10))+' ;'+CHAR(10)+
 ''', informational;'
 FROM #tmp_outliers
 WHERE @ID = [Logger_History_ID];

EXEC (@gen_stmt);
 --PRINT @gen_stmt;

UPDATE [dbo].[Logger_History]
 SET [Moved_To_ES] = 1
 WHERE @ID = [Logger_History_ID];

DELETE FROM #tmp_outliers WHERE [Logger_History_ID] = @ID;

END

COMMIT TRANSACTION
END TRY

BEGIN CATCH

IF @@TRANCOUNT > 0
 ROLLBACK TRANSACTION;

 DECLARE @ErrorNumber INT = ERROR_NUMBER();
 DECLARE @ErrorLine INT = ERROR_LINE();
 DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
 DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
 DECLARE @ErrorState INT = ERROR_STATE();

 PRINT 'Actual error number: ' + CAST(@ErrorNumber AS VARCHAR(10));
 PRINT 'Actual line number: ' + CAST(@ErrorLine AS VARCHAR(10));

 RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);

END CATCH

END
GO
