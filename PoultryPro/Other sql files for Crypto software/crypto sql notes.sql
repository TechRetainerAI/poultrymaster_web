USE [Crypto]
GO

/****** Object:  Table [dbo].[tblEthTransaction]    Script Date: 10/21/2023 11:54:25 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tblBnbTransaction](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[UserId] [nvarchar](max) NOT NULL,
	[Txhash] [varchar](255) NULL,
	[BlockNumber] [int] NULL,
	[UnixTimestamp] [int] NULL,
	[DateTime] [datetime] NULL,
	[FromAddress] [varchar](255) NULL,
	[ToAddress] [varchar](255) NULL,
	[ContractAddress] [varchar](255) NULL,
	[ValueInBNB] [decimal](18, 8) NULL,
	[ValueOutBNB] [decimal](18, 8) NULL,
	[CurrentValueUSD] [decimal](18, 8) NULL,
	[BnbPriceUsedForCurrValueUSD] [decimal](18, 8) NULL,
	[TxnFeeBNB] [decimal](18, 8) NULL,
	[TxnFeeUSD] [decimal](18, 8) NULL,
	[HistoricalPriceBNB] [decimal](18, 8) NULL,
	[Status] [varchar](50) NULL,
	[ErrCode] [varchar](255) NULL,
	[Method] [varchar](255) NULL,
PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO


Truncate table tblBnbTransaction
Truncate table tblEthTransaction