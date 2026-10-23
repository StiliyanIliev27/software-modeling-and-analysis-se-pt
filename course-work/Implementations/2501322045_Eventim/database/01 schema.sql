/* =====================================================================
   Eventim – курсова работа по „Моделиране и анализ на софтуер“
   01_schema.sql – база данни, таблици, ограничения и индекси
   ===================================================================== */

USE master;
GO

IF DB_ID(N'EventimDB') IS NOT NULL
BEGIN
    ALTER DATABASE EventimDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE EventimDB;
END
GO

-- Кирилска колация, за да се сортират правилно имената на български
CREATE DATABASE EventimDB COLLATE Cyrillic_General_CI_AS;
GO

USE EventimDB;
GO

/* ---------------------------------------------------------------------
   Номенклатури
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Cities
(
    CityId   INT IDENTITY(1,1) NOT NULL,
    Name     NVARCHAR(100)     NOT NULL,
    Country  NVARCHAR(100)     NOT NULL,
    CONSTRAINT PK_Cities PRIMARY KEY (CityId),
    CONSTRAINT UQ_Cities_Name_Country UNIQUE (Name, Country)
);

CREATE TABLE dbo.Categories
(
    CategoryId INT IDENTITY(1,1) NOT NULL,
    Name       NVARCHAR(50)      NOT NULL,
    CONSTRAINT PK_Categories PRIMARY KEY (CategoryId),
    CONSTRAINT UQ_Categories_Name UNIQUE (Name)
);

CREATE TABLE dbo.Performers
(
    PerformerId INT IDENTITY(1,1) NOT NULL,
    Name        NVARCHAR(150)     NOT NULL,
    Genre       NVARCHAR(50)      NULL,
    Country     NVARCHAR(100)     NULL,
    CONSTRAINT PK_Performers PRIMARY KEY (PerformerId)
);

CREATE TABLE dbo.Promoters
(
    PromoterId INT IDENTITY(1,1) NOT NULL,
    Name       NVARCHAR(150)     NOT NULL,
    Email      NVARCHAR(255)     NOT NULL,
    Phone      NVARCHAR(20)      NULL,
    CONSTRAINT PK_Promoters PRIMARY KEY (PromoterId),
    CONSTRAINT UQ_Promoters_Email UNIQUE (Email)
);

/* ---------------------------------------------------------------------
   Клиенти
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Customers
(
    CustomerId   INT IDENTITY(1,1) NOT NULL,
    FirstName    NVARCHAR(50)      NOT NULL,
    LastName     NVARCHAR(50)      NOT NULL,
    Email        NVARCHAR(255)     NOT NULL,
    Phone        NVARCHAR(20)      NULL,
    BirthDate    DATE              NULL,
    CityId       INT               NOT NULL,
    RegisteredAt DATETIME2(0)      NOT NULL CONSTRAINT DF_Customers_RegisteredAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Customers PRIMARY KEY (CustomerId),
    CONSTRAINT UQ_Customers_Email UNIQUE (Email),
    CONSTRAINT CK_Customers_Email CHECK (Email LIKE N'%_@_%._%'),
    CONSTRAINT FK_Customers_Cities FOREIGN KEY (CityId) REFERENCES dbo.Cities (CityId)
);

/* ---------------------------------------------------------------------
   Зали, секции и места
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Venues
(
    VenueId INT IDENTITY(1,1) NOT NULL,
    Name    NVARCHAR(150)     NOT NULL,
    Address NVARCHAR(255)     NOT NULL,
    CityId  INT               NOT NULL,
    CONSTRAINT PK_Venues PRIMARY KEY (VenueId),
    CONSTRAINT UQ_Venues_Name_City UNIQUE (Name, CityId),
    CONSTRAINT FK_Venues_Cities FOREIGN KEY (CityId) REFERENCES dbo.Cities (CityId)
);

CREATE TABLE dbo.Sections
(
    SectionId   INT IDENTITY(1,1) NOT NULL,
    VenueId     INT               NOT NULL,
    Name        NVARCHAR(50)      NOT NULL,
    SectionType NVARCHAR(20)      NOT NULL,
    CONSTRAINT PK_Sections PRIMARY KEY (SectionId),
    CONSTRAINT UQ_Sections_Venue_Name UNIQUE (VenueId, Name),
    CONSTRAINT CK_Sections_Type CHECK (SectionType IN (N'Parterre', N'Balcony', N'VIP', N'Box')),
    CONSTRAINT FK_Sections_Venues FOREIGN KEY (VenueId) REFERENCES dbo.Venues (VenueId)
);

CREATE TABLE dbo.Seats
(
    SeatId     INT IDENTITY(1,1) NOT NULL,
    SectionId  INT               NOT NULL,
    RowNumber  INT               NOT NULL,
    SeatNumber INT               NOT NULL,
    CONSTRAINT PK_Seats PRIMARY KEY (SeatId),
    -- едно физическо място съществува само веднъж в секцията
    CONSTRAINT UQ_Seats_Section_Row_Seat UNIQUE (SectionId, RowNumber, SeatNumber),
    CONSTRAINT CK_Seats_Positive CHECK (RowNumber > 0 AND SeatNumber > 0),
    CONSTRAINT FK_Seats_Sections FOREIGN KEY (SectionId) REFERENCES dbo.Sections (SectionId)
);

/* ---------------------------------------------------------------------
   Събития
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Events
(
    EventId        INT IDENTITY(1,1) NOT NULL,
    Title          NVARCHAR(200)     NOT NULL,
    Description    NVARCHAR(MAX)     NULL,
    StartDateTime  DATETIME2(0)      NOT NULL,
    SalesStartDate DATETIME2(0)      NOT NULL,
    Status         NVARCHAR(20)      NOT NULL CONSTRAINT DF_Events_Status DEFAULT (N'Scheduled'),
    CategoryId     INT               NOT NULL,
    VenueId        INT               NOT NULL,
    PromoterId     INT               NOT NULL,
    CONSTRAINT PK_Events PRIMARY KEY (EventId),
    CONSTRAINT UQ_Events_Title_Start UNIQUE (Title, StartDateTime),
    CONSTRAINT CK_Events_Status CHECK (Status IN (N'Scheduled', N'Cancelled', N'Completed')),
    CONSTRAINT CK_Events_SalesBeforeStart CHECK (SalesStartDate < StartDateTime),
    CONSTRAINT FK_Events_Categories FOREIGN KEY (CategoryId) REFERENCES dbo.Categories (CategoryId),
    CONSTRAINT FK_Events_Venues FOREIGN KEY (VenueId) REFERENCES dbo.Venues (VenueId),
    CONSTRAINT FK_Events_Promoters FOREIGN KEY (PromoterId) REFERENCES dbo.Promoters (PromoterId)
);

-- M:N Events <-> Performers
CREATE TABLE dbo.EventPerformers
(
    EventId          INT NOT NULL,
    PerformerId      INT NOT NULL,
    IsHeadliner      BIT NOT NULL CONSTRAINT DF_EventPerformers_IsHeadliner DEFAULT (0),
    PerformanceOrder INT NOT NULL,
    CONSTRAINT PK_EventPerformers PRIMARY KEY (EventId, PerformerId),
    CONSTRAINT UQ_EventPerformers_Order UNIQUE (EventId, PerformanceOrder),
    CONSTRAINT CK_EventPerformers_Order CHECK (PerformanceOrder > 0),
    CONSTRAINT FK_EventPerformers_Events FOREIGN KEY (EventId) REFERENCES dbo.Events (EventId),
    CONSTRAINT FK_EventPerformers_Performers FOREIGN KEY (PerformerId) REFERENCES dbo.Performers (PerformerId)
);

-- M:N Events <-> Sections (цената зависи от събитието и секцията)
CREATE TABLE dbo.EventSectionPrices
(
    EventId   INT           NOT NULL,
    SectionId INT           NOT NULL,
    Price     DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_EventSectionPrices PRIMARY KEY (EventId, SectionId),
    CONSTRAINT CK_EventSectionPrices_Price CHECK (Price > 0),
    CONSTRAINT FK_EventSectionPrices_Events FOREIGN KEY (EventId) REFERENCES dbo.Events (EventId),
    CONSTRAINT FK_EventSectionPrices_Sections FOREIGN KEY (SectionId) REFERENCES dbo.Sections (SectionId)
);

/* ---------------------------------------------------------------------
   Поръчки, билети, възстановявания
   --------------------------------------------------------------------- */

CREATE TABLE dbo.Orders
(
    OrderId       INT IDENTITY(1,1) NOT NULL,
    CustomerId    INT               NOT NULL,
    OrderDate     DATETIME2(0)      NOT NULL CONSTRAINT DF_Orders_OrderDate DEFAULT (SYSDATETIME()),
    TotalAmount   DECIMAL(10,2)     NOT NULL CONSTRAINT DF_Orders_TotalAmount DEFAULT (0),
    PaymentMethod NVARCHAR(20)      NOT NULL,
    Status        NVARCHAR(20)      NOT NULL CONSTRAINT DF_Orders_Status DEFAULT (N'Paid'),
    CONSTRAINT PK_Orders PRIMARY KEY (OrderId),
    CONSTRAINT CK_Orders_TotalAmount CHECK (TotalAmount >= 0),
    CONSTRAINT CK_Orders_PaymentMethod CHECK (PaymentMethod IN (N'Card', N'PayPal', N'ApplePay', N'GooglePay', N'BankTransfer')),
    CONSTRAINT CK_Orders_Status CHECK (Status IN (N'Paid', N'PartiallyRefunded', N'Refunded', N'Cancelled')),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers (CustomerId)
);

CREATE TABLE dbo.Tickets
(
    TicketId    INT IDENTITY(1,1) NOT NULL,
    OrderId     INT               NOT NULL,
    EventId     INT               NOT NULL,
    SeatId      INT               NOT NULL,
    Price       DECIMAL(10,2)     NOT NULL,
    TicketCode  NVARCHAR(32)      NOT NULL,
    Status      NVARCHAR(20)      NOT NULL CONSTRAINT DF_Tickets_Status DEFAULT (N'Valid'),
    CheckedInAt DATETIME2(0)      NULL,
    CONSTRAINT PK_Tickets PRIMARY KEY (TicketId),
    CONSTRAINT UQ_Tickets_TicketCode UNIQUE (TicketCode),
    CONSTRAINT CK_Tickets_Price CHECK (Price > 0),
    CONSTRAINT CK_Tickets_Status CHECK (Status IN (N'Valid', N'Used', N'Refunded')),
    -- час на влизане има само използваният билет
    CONSTRAINT CK_Tickets_CheckIn CHECK (
        (Status = N'Used' AND CheckedInAt IS NOT NULL) OR
        (Status <> N'Used' AND CheckedInAt IS NULL)),
    CONSTRAINT FK_Tickets_Orders FOREIGN KEY (OrderId) REFERENCES dbo.Orders (OrderId),
    CONSTRAINT FK_Tickets_Events FOREIGN KEY (EventId) REFERENCES dbo.Events (EventId),
    CONSTRAINT FK_Tickets_Seats FOREIGN KEY (SeatId) REFERENCES dbo.Seats (SeatId)
);

CREATE TABLE dbo.Refunds
(
    RefundId   INT IDENTITY(1,1) NOT NULL,
    TicketId   INT               NOT NULL,
    Amount     DECIMAL(10,2)     NOT NULL,
    Reason     NVARCHAR(255)     NULL,
    RefundedAt DATETIME2(0)      NOT NULL CONSTRAINT DF_Refunds_RefundedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Refunds PRIMARY KEY (RefundId),
    -- билет се възстановява най-много веднъж (връзка 1 : 0..1)
    CONSTRAINT UQ_Refunds_TicketId UNIQUE (TicketId),
    CONSTRAINT CK_Refunds_Amount CHECK (Amount > 0),
    CONSTRAINT FK_Refunds_Tickets FOREIGN KEY (TicketId) REFERENCES dbo.Tickets (TicketId)
);
GO

/* ---------------------------------------------------------------------
   Индекси
   --------------------------------------------------------------------- */

-- Филтриран уникален индекс: едно място може да има само един активен
-- билет за дадено събитие. След възстановяване (Refunded) мястото
-- отново може да се продаде, защото редът излиза от филтъра.
CREATE UNIQUE NONCLUSTERED INDEX UX_Tickets_Event_Seat_Active
    ON dbo.Tickets (EventId, SeatId)
    WHERE Status IN (N'Valid', N'Used');

-- Индекси върху външните ключове, по които най-често се правят JOIN-ове
CREATE NONCLUSTERED INDEX IX_Tickets_EventId_Status ON dbo.Tickets (EventId, Status) INCLUDE (SeatId, Price);
CREATE NONCLUSTERED INDEX IX_Tickets_OrderId        ON dbo.Tickets (OrderId);
CREATE NONCLUSTERED INDEX IX_Orders_CustomerId      ON dbo.Orders (CustomerId) INCLUDE (OrderDate, Status);
CREATE NONCLUSTERED INDEX IX_Events_VenueId         ON dbo.Events (VenueId);
CREATE NONCLUSTERED INDEX IX_Events_StartDateTime   ON dbo.Events (StartDateTime) INCLUDE (Status);
CREATE NONCLUSTERED INDEX IX_Customers_CityId       ON dbo.Customers (CityId);
CREATE NONCLUSTERED INDEX IX_Venues_CityId          ON dbo.Venues (CityId);
CREATE NONCLUSTERED INDEX IX_EventPerformers_PerformerId ON dbo.EventPerformers (PerformerId);
CREATE NONCLUSTERED INDEX IX_EventSectionPrices_SectionId ON dbo.EventSectionPrices (SectionId);
GO