/* =====================================================================
   Eventim – 05_dw_schema.sql
   Data Warehouse (fact constellation): 3 таблици факти, 8 измерения.
   Таблиците факти споделят общи (conformed) измерения.
   ===================================================================== */

USE master;
GO

IF DB_ID(N'EventimDW') IS NOT NULL
BEGIN
    ALTER DATABASE EventimDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE EventimDW;
END
GO

-- Същата колация като EventimDB, за да няма конфликти при ETL
CREATE DATABASE EventimDW COLLATE Cyrillic_General_CI_AS;
GO

USE EventimDW;
GO

/* =====================================================================
   ИЗМЕРЕНИЯ
   Всяко измерение има сурогатен ключ (…Key) и бизнес ключ от
   оперативната база (…Id). SCD тип 1 – при всяко зареждане се
   презаписват.
   ===================================================================== */

CREATE TABLE dbo.DimDate
(
    DateKey           INT           NOT NULL,  -- yyyymmdd
    FullDate          DATE          NOT NULL,
    DayOfMonth        TINYINT       NOT NULL,
    DayOfWeekNumber   TINYINT       NOT NULL,  -- 1 = понеделник
    DayName           NVARCHAR(20)  NOT NULL,
    IsWeekend         BIT           NOT NULL,
    MonthNumber       TINYINT       NOT NULL,
    MonthName         NVARCHAR(20)  NOT NULL,
    YearMonth         CHAR(7)       NOT NULL,  -- 2026-10
    CalendarQuarter   TINYINT       NOT NULL,
    CalendarYear      SMALLINT      NOT NULL,
    Season            NVARCHAR(10)  NOT NULL,
    CONSTRAINT PK_DimDate PRIMARY KEY (DateKey)
);

CREATE TABLE dbo.DimCustomer
(
    CustomerKey      INT IDENTITY(1,1) NOT NULL,
    CustomerId       INT               NOT NULL,
    FullName         NVARCHAR(101)     NOT NULL,
    Email            NVARCHAR(255)     NOT NULL,
    City             NVARCHAR(100)     NOT NULL,
    AgeGroup         NVARCHAR(20)      NOT NULL,
    RegistrationYear SMALLINT          NOT NULL,
    CONSTRAINT PK_DimCustomer PRIMARY KEY (CustomerKey),
    CONSTRAINT UQ_DimCustomer_CustomerId UNIQUE (CustomerId)
);

CREATE TABLE dbo.DimEvent
(
    EventKey      INT IDENTITY(1,1) NOT NULL,
    EventId       INT               NOT NULL,
    Title         NVARCHAR(200)     NOT NULL,
    Promoter      NVARCHAR(150)     NOT NULL,
    EventStatus   NVARCHAR(20)      NOT NULL,
    StartDateTime DATETIME2(0)      NOT NULL,
    DayPart       NVARCHAR(20)      NOT NULL,  -- Сутрин / Следобед / Вечер
    CONSTRAINT PK_DimEvent PRIMARY KEY (EventKey),
    CONSTRAINT UQ_DimEvent_EventId UNIQUE (EventId)
);

CREATE TABLE dbo.DimVenue
(
    VenueKey  INT IDENTITY(1,1) NOT NULL,
    VenueId   INT               NOT NULL,
    VenueName NVARCHAR(150)     NOT NULL,
    City      NVARCHAR(100)     NOT NULL,
    Country   NVARCHAR(100)     NOT NULL,
    Capacity  INT               NOT NULL,  -- изчислява се от броя места
    CONSTRAINT PK_DimVenue PRIMARY KEY (VenueKey),
    CONSTRAINT UQ_DimVenue_VenueId UNIQUE (VenueId)
);

CREATE TABLE dbo.DimSection
(
    SectionKey  INT IDENTITY(1,1) NOT NULL,
    SectionId   INT               NOT NULL,
    SectionName NVARCHAR(50)      NOT NULL,
    SectionType NVARCHAR(20)      NOT NULL,
    VenueName   NVARCHAR(150)     NOT NULL,
    SeatsCount  INT               NOT NULL,
    CONSTRAINT PK_DimSection PRIMARY KEY (SectionKey),
    CONSTRAINT UQ_DimSection_SectionId UNIQUE (SectionId)
);

-- Изпълнителят в таблиците факти е хедлайнерът на събитието
CREATE TABLE dbo.DimPerformer
(
    PerformerKey  INT IDENTITY(1,1) NOT NULL,
    PerformerId   INT               NOT NULL,
    PerformerName NVARCHAR(150)     NOT NULL,
    Genre         NVARCHAR(50)      NOT NULL,
    Country       NVARCHAR(100)     NOT NULL,
    CONSTRAINT PK_DimPerformer PRIMARY KEY (PerformerKey),
    CONSTRAINT UQ_DimPerformer_PerformerId UNIQUE (PerformerId)
);

CREATE TABLE dbo.DimCategory
(
    CategoryKey  INT IDENTITY(1,1) NOT NULL,
    CategoryId   INT               NOT NULL,
    CategoryName NVARCHAR(50)      NOT NULL,
    CONSTRAINT PK_DimCategory PRIMARY KEY (CategoryKey),
    CONSTRAINT UQ_DimCategory_CategoryId UNIQUE (CategoryId)
);

CREATE TABLE dbo.DimPaymentMethod
(
    PaymentMethodKey  INT IDENTITY(1,1) NOT NULL,
    PaymentMethodCode NVARCHAR(20)      NOT NULL,
    PaymentMethodName NVARCHAR(50)      NOT NULL,
    PaymentGroup      NVARCHAR(30)      NOT NULL,
    CONSTRAINT PK_DimPaymentMethod PRIMARY KEY (PaymentMethodKey),
    CONSTRAINT UQ_DimPaymentMethod_Code UNIQUE (PaymentMethodCode)
);

/* =====================================================================
   ТАБЛИЦИ ФАКТИ
   TicketId / OrderId / RefundId са degenerate измерения – идентификатори
   от оперативната база без собствена таблица измерение.
   ===================================================================== */

-- Грануларност: един ред = един продаден билет
CREATE TABLE dbo.FactTicketSales
(
    TicketSalesKey   INT IDENTITY(1,1) NOT NULL,
    TicketId         INT           NOT NULL,
    OrderId          INT           NOT NULL,
    OrderDateKey     INT           NOT NULL,  -- role-playing: дата на покупката
    EventDateKey     INT           NOT NULL,  -- role-playing: дата на събитието
    CustomerKey      INT           NOT NULL,
    EventKey         INT           NOT NULL,
    VenueKey         INT           NOT NULL,
    SectionKey       INT           NOT NULL,
    PerformerKey     INT           NOT NULL,
    CategoryKey      INT           NOT NULL,
    PaymentMethodKey INT           NOT NULL,
    SalesAmount      DECIMAL(10,2) NOT NULL,
    TicketCount      INT           NOT NULL,
    DaysBeforeEvent  INT           NOT NULL,
    IsRefunded       BIT           NOT NULL,
    CONSTRAINT PK_FactTicketSales PRIMARY KEY (TicketSalesKey),
    CONSTRAINT UQ_FactTicketSales_TicketId UNIQUE (TicketId),
    CONSTRAINT FK_FactTicketSales_OrderDate FOREIGN KEY (OrderDateKey)     REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactTicketSales_EventDate FOREIGN KEY (EventDateKey)     REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactTicketSales_Customer  FOREIGN KEY (CustomerKey)      REFERENCES dbo.DimCustomer (CustomerKey),
    CONSTRAINT FK_FactTicketSales_Event     FOREIGN KEY (EventKey)         REFERENCES dbo.DimEvent (EventKey),
    CONSTRAINT FK_FactTicketSales_Venue     FOREIGN KEY (VenueKey)         REFERENCES dbo.DimVenue (VenueKey),
    CONSTRAINT FK_FactTicketSales_Section   FOREIGN KEY (SectionKey)       REFERENCES dbo.DimSection (SectionKey),
    CONSTRAINT FK_FactTicketSales_Performer FOREIGN KEY (PerformerKey)     REFERENCES dbo.DimPerformer (PerformerKey),
    CONSTRAINT FK_FactTicketSales_Category  FOREIGN KEY (CategoryKey)      REFERENCES dbo.DimCategory (CategoryKey),
    CONSTRAINT FK_FactTicketSales_Payment   FOREIGN KEY (PaymentMethodKey) REFERENCES dbo.DimPaymentMethod (PaymentMethodKey)
);

-- Грануларност: един ред = едно влизане (сканиран билет)
CREATE TABLE dbo.FactCheckIns
(
    CheckInKey         INT IDENTITY(1,1) NOT NULL,
    TicketId           INT     NOT NULL,
    CheckInDateKey     INT     NOT NULL,
    CustomerKey        INT     NOT NULL,
    EventKey           INT     NOT NULL,
    VenueKey           INT     NOT NULL,
    SectionKey         INT     NOT NULL,
    PerformerKey       INT     NOT NULL,
    CategoryKey        INT     NOT NULL,
    MinutesBeforeStart INT     NOT NULL,  -- отрицателно = закъснение
    CheckInHour        TINYINT NOT NULL,
    IsLate             BIT     NOT NULL,
    AttendanceCount    INT     NOT NULL,
    CONSTRAINT PK_FactCheckIns PRIMARY KEY (CheckInKey),
    CONSTRAINT UQ_FactCheckIns_TicketId UNIQUE (TicketId),
    CONSTRAINT FK_FactCheckIns_Date      FOREIGN KEY (CheckInDateKey) REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactCheckIns_Customer  FOREIGN KEY (CustomerKey)    REFERENCES dbo.DimCustomer (CustomerKey),
    CONSTRAINT FK_FactCheckIns_Event     FOREIGN KEY (EventKey)       REFERENCES dbo.DimEvent (EventKey),
    CONSTRAINT FK_FactCheckIns_Venue     FOREIGN KEY (VenueKey)       REFERENCES dbo.DimVenue (VenueKey),
    CONSTRAINT FK_FactCheckIns_Section   FOREIGN KEY (SectionKey)     REFERENCES dbo.DimSection (SectionKey),
    CONSTRAINT FK_FactCheckIns_Performer FOREIGN KEY (PerformerKey)   REFERENCES dbo.DimPerformer (PerformerKey),
    CONSTRAINT FK_FactCheckIns_Category  FOREIGN KEY (CategoryKey)    REFERENCES dbo.DimCategory (CategoryKey)
);

-- Грануларност: един ред = едно възстановяване
CREATE TABLE dbo.FactRefunds
(
    RefundKey           INT IDENTITY(1,1) NOT NULL,
    RefundId            INT           NOT NULL,
    TicketId            INT           NOT NULL,
    RefundDateKey       INT           NOT NULL,
    CustomerKey         INT           NOT NULL,
    EventKey            INT           NOT NULL,
    VenueKey            INT           NOT NULL,
    SectionKey          INT           NOT NULL,
    PerformerKey        INT           NOT NULL,
    CategoryKey         INT           NOT NULL,
    PaymentMethodKey    INT           NOT NULL,
    RefundAmount        DECIMAL(10,2) NOT NULL,
    DaysBeforeEvent     INT           NOT NULL,
    IsEventCancellation BIT           NOT NULL,
    CONSTRAINT PK_FactRefunds PRIMARY KEY (RefundKey),
    CONSTRAINT UQ_FactRefunds_RefundId UNIQUE (RefundId),
    CONSTRAINT FK_FactRefunds_Date      FOREIGN KEY (RefundDateKey)    REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactRefunds_Customer  FOREIGN KEY (CustomerKey)      REFERENCES dbo.DimCustomer (CustomerKey),
    CONSTRAINT FK_FactRefunds_Event     FOREIGN KEY (EventKey)         REFERENCES dbo.DimEvent (EventKey),
    CONSTRAINT FK_FactRefunds_Venue     FOREIGN KEY (VenueKey)         REFERENCES dbo.DimVenue (VenueKey),
    CONSTRAINT FK_FactRefunds_Section   FOREIGN KEY (SectionKey)       REFERENCES dbo.DimSection (SectionKey),
    CONSTRAINT FK_FactRefunds_Performer FOREIGN KEY (PerformerKey)     REFERENCES dbo.DimPerformer (PerformerKey),
    CONSTRAINT FK_FactRefunds_Category  FOREIGN KEY (CategoryKey)      REFERENCES dbo.DimCategory (CategoryKey),
    CONSTRAINT FK_FactRefunds_Payment   FOREIGN KEY (PaymentMethodKey) REFERENCES dbo.DimPaymentMethod (PaymentMethodKey)
);

-- Лог на ETL изпълненията (допълнение)
CREATE TABLE dbo.EtlLog
(
    RunId          INT IDENTITY(1,1) NOT NULL,
    StartedAt      DATETIME2(0)      NOT NULL,
    FinishedAt     DATETIME2(0)      NULL,
    RowsSales      INT               NULL,
    RowsCheckIns   INT               NULL,
    RowsRefunds    INT               NULL,
    Status         NVARCHAR(20)      NOT NULL,
    ErrorMessage   NVARCHAR(4000)    NULL,
    CONSTRAINT PK_EtlLog PRIMARY KEY (RunId)
);
GO

/* =====================================================================
   DimDate се генерира веднъж: 2022-01-01 .. 2027-12-31
   ===================================================================== */

WITH Numbers AS
(
    SELECT TOP (DATEDIFF(DAY, '2022-01-01', '2027-12-31') + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
),
Dates AS
(
    SELECT DATEADD(DAY, i, CAST('2022-01-01' AS DATE)) AS dt
    FROM Numbers
)
INSERT INTO dbo.DimDate
    (DateKey, FullDate, DayOfMonth, DayOfWeekNumber, DayName, IsWeekend,
     MonthNumber, MonthName, YearMonth, CalendarQuarter, CalendarYear, Season)
SELECT  CONVERT(INT, CONVERT(CHAR(8), d.dt, 112)),
        d.dt,
        DAY(d.dt),
        w.dow,
        CHOOSE(w.dow, N'Понеделник', N'Вторник', N'Сряда', N'Четвъртък', N'Петък', N'Събота', N'Неделя'),
        CASE WHEN w.dow IN (6, 7) THEN 1 ELSE 0 END,
        MONTH(d.dt),
        CHOOSE(MONTH(d.dt), N'Януари', N'Февруари', N'Март', N'Април', N'Май', N'Юни',
                            N'Юли', N'Август', N'Септември', N'Октомври', N'Ноември', N'Декември'),
        CONVERT(CHAR(7), d.dt, 120),
        DATEPART(QUARTER, d.dt),
        YEAR(d.dt),
        CASE WHEN MONTH(d.dt) IN (12, 1, 2) THEN N'Зима'
             WHEN MONTH(d.dt) IN (3, 4, 5)  THEN N'Пролет'
             WHEN MONTH(d.dt) IN (6, 7, 8)  THEN N'Лято'
             ELSE N'Есен' END
FROM Dates d
-- ден от седмицата, независим от настройката DATEFIRST
CROSS APPLY (SELECT ((DATEPART(WEEKDAY, d.dt) + @@DATEFIRST - 2) % 7) + 1 AS dow) w;
GO

-- Начините на плащане нямат таблица в EventimDB (там са CHECK списък),
-- затова измерението се попълва тук
INSERT INTO dbo.DimPaymentMethod (PaymentMethodCode, PaymentMethodName, PaymentGroup) VALUES
 (N'Card',         N'Банкова карта',  N'Карта'),
 (N'GooglePay',    N'Google Pay',     N'Дигитален портфейл'),
 (N'ApplePay',     N'Apple Pay',      N'Дигитален портфейл'),
 (N'PayPal',       N'PayPal',         N'Дигитален портфейл'),
 (N'BankTransfer', N'Банков превод',  N'Банков превод');
GO