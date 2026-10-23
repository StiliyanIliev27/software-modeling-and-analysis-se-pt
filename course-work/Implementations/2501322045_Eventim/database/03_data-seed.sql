/* =====================================================================
   Eventim – 03_seed_data.sql
   Тестови данни. Номенклатурите са фиксирани, а клиентите, поръчките,
   билетите, възстановяванията и влизанията се генерират.
   Продажбите минават през sp_PurchaseTickets, така че всички правила
   и тригери се прилагат и върху тестовите данни.
   Всички цени са в евро.
   Временните таблици са с COLLATE DATABASE_DEFAULT, защото tempdb
   използва колацията на сървъра, а базата е Cyrillic_General_CI_AS.
   ===================================================================== */

USE EventimDB;
GO
SET NOCOUNT ON;
GO

-- Защита: скриптът се пуска само върху празна база (веднага след 01 и 02).
-- SET NOEXEC ON спира изпълнението на всички следващи батчове до края на файла.
IF EXISTS (SELECT 1 FROM dbo.Cities)
BEGIN
    RAISERROR(N'Базата вече съдържа данни. Пуснете отново 01_schema.sql и 02_programmability.sql, после този скрипт.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ---------------------------------------------------------------------
   Градове, категории, организатори, изпълнители
   --------------------------------------------------------------------- */

INSERT INTO dbo.Cities (Name, Country) VALUES
 (N'София',          N'България'),
 (N'Пловдив',        N'България'),
 (N'Варна',          N'България'),
 (N'Бургас',         N'България'),
 (N'Стара Загора',   N'България'),
 (N'Русе',           N'България'),
 (N'Велико Търново', N'България');

INSERT INTO dbo.Categories (Name) VALUES
 (N'Концерт'), (N'Театър'), (N'Спорт'), (N'Фестивал'), (N'Стендъп комедия'), (N'Детски');

INSERT INTO dbo.Promoters (Name, Email, Phone) VALUES
 (N'Ивент Партнърс ООД',          N'office@eventpartners.bg', N'+359888100200'),
 (N'Музикален център София ЕООД', N'info@musiccenter.bg',     N'+359878300400'),
 (N'Арт Продакшън ЕООД',          N'contact@artproduction.bg', N'+359898500600'),
 (N'Спорт Ивентс БГ ООД',         N'tickets@sportevents.bg',  N'+359887700800');

INSERT INTO dbo.Performers (Name, Genre, Country) VALUES
 (N'Остава',                                   N'Рок',              N'България'),
 (N'Сигнал',                                   N'Рок',              N'България'),
 (N'Б.Т.Р.',                                   N'Рок',              N'България'),
 (N'Д2',                                       N'Рок',              N'България'),
 (N'Михаела Филева',                           N'Поп',              N'България'),
 (N'Лили Иванова',                             N'Поп',              N'България'),
 (N'Ицо Хазарта',                              N'Хип-хоп',          N'България'),
 (N'Софийска филхармония',                     N'Класическа',       N'България'),
 (N'Apocalyptica',                             N'Метъл',            N'Финландия'),
 (N'Hooverphonic',                             N'Алтернативен поп', N'Белгия'),
 (N'Трупа на ДТ Стара Загора',                 N'Театър',           N'България'),
 (N'Национален отбор по волейбол на България', N'Волейбол',         N'България'),
 (N'Национален отбор по волейбол на Сърбия',   N'Волейбол',         N'Сърбия'),
 (N'Комеди Клуб София',                        N'Стендъп',          N'България'),
 (N'Детски театър „Слънчице“',                 N'Детски театър',    N'България');

/* ---------------------------------------------------------------------
   Зали, секции и места
   --------------------------------------------------------------------- */

INSERT INTO dbo.Venues (Name, Address, CityId)
SELECT v.Name, v.Address, c.CityId
FROM (VALUES
 (N'Арена София',                    N'бул. „Асен Йорданов“ 1',  N'София'),
 (N'Зала Универсиада',               N'ул. „Шипченски проход“ 2', N'София'),
 (N'Античен театър',                 N'ул. „Цар Ивайло“ 4',      N'Пловдив'),
 (N'Летен театър Варна',             N'Морска градина',          N'Варна'),
 (N'Летен театър Бургас',            N'Морска градина',          N'Бургас'),
 (N'Драматичен театър Стара Загора', N'бул. „Руски“ 17',         N'Стара Загора')
) v(Name, Address, City)
JOIN dbo.Cities c ON c.Name = v.City;

-- План на секциите: брой редове и места на ред
CREATE TABLE #SectionPlan
(
    Venue       NVARCHAR(150) COLLATE DATABASE_DEFAULT,
    SectionName NVARCHAR(50)  COLLATE DATABASE_DEFAULT,
    SectionType NVARCHAR(20)  COLLATE DATABASE_DEFAULT,
    RowsCount   INT,
    SeatsPerRow INT
);

INSERT INTO #SectionPlan VALUES
 (N'Арена София',                    N'Партер', N'Parterre', 10, 20),
 (N'Арена София',                    N'Балкон', N'Balcony',   8, 20),
 (N'Арена София',                    N'VIP',    N'VIP',       3, 10),
 (N'Зала Универсиада',               N'Партер', N'Parterre',  8, 15),
 (N'Зала Универсиада',               N'Балкон', N'Balcony',   6, 15),
 (N'Античен театър',                 N'Партер', N'Parterre', 12, 18),
 (N'Античен театър',                 N'VIP',    N'VIP',       2, 12),
 (N'Летен театър Варна',             N'Партер', N'Parterre', 10, 16),
 (N'Летен театър Варна',             N'Балкон', N'Balcony',   5, 16),
 (N'Летен театър Бургас',            N'Партер', N'Parterre', 10, 15),
 (N'Летен театър Бургас',            N'VIP',    N'VIP',       2, 10),
 (N'Драматичен театър Стара Загора', N'Партер', N'Parterre',  8, 14),
 (N'Драматичен театър Стара Загора', N'Ложа',   N'Box',       2,  6);

INSERT INTO dbo.Sections (VenueId, Name, SectionType)
SELECT v.VenueId, p.SectionName, p.SectionType
FROM #SectionPlan p
JOIN dbo.Venues v ON v.Name = p.Venue;

-- Помощна таблица с числа 1..50
SELECT TOP (50) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
INTO #Nums
FROM sys.all_objects;

INSERT INTO dbo.Seats (SectionId, RowNumber, SeatNumber)
SELECT sec.SectionId, r.n, s.n
FROM #SectionPlan p
JOIN dbo.Venues v     ON v.Name = p.Venue
JOIN dbo.Sections sec ON sec.VenueId = v.VenueId AND sec.Name = p.SectionName
JOIN #Nums r          ON r.n <= p.RowsCount
JOIN #Nums s          ON s.n <= p.SeatsPerRow;

/* ---------------------------------------------------------------------
   Събития, изпълнители по събития, цени по секции
   Продажбите започват 75 дни преди събитието.
   --------------------------------------------------------------------- */

CREATE TABLE #EventPlan
(
    Title       NVARCHAR(200) COLLATE DATABASE_DEFAULT,
    Description NVARCHAR(500) COLLATE DATABASE_DEFAULT,
    StartAt     DATETIME2(0),
    Category    NVARCHAR(50)  COLLATE DATABASE_DEFAULT,
    Venue       NVARCHAR(150) COLLATE DATABASE_DEFAULT,
    Promoter    NVARCHAR(150) COLLATE DATABASE_DEFAULT,
    BasePrice   DECIMAL(10,2)
);

INSERT INTO #EventPlan VALUES
 (N'Остава – 25 години на сцена',          N'Юбилеен концерт с най-големите хитове на групата.',      '2025-03-15 20:00', N'Концерт',         N'Арена София',                    N'Музикален център София ЕООД', 35),
 (N'Хамлет',                               N'Класическата трагедия на Шекспир в нова постановка.',    '2025-04-10 19:00', N'Театър',          N'Драматичен театър Стара Загора', N'Арт Продакшън ЕООД',          18),
 (N'Сигнал – Акустично лято',              N'Акустичен концерт под звездите.',                        '2025-06-21 21:00', N'Концерт',         N'Античен театър',                 N'Ивент Партнърс ООД',          30),
 (N'Рок вечер: Б.Т.Р. и Д2',               N'Две от най-обичаните български рок групи на една сцена.', '2025-07-19 20:30', N'Концерт',         N'Летен театър Варна',             N'Ивент Партнърс ООД',          28),
 (N'Varna Summer Fest 2025',               N'Летен фестивал с поп и хип-хоп изпълнители.',            '2025-08-09 19:00', N'Фестивал',        N'Летен театър Варна',             N'Музикален център София ЕООД', 25),
 (N'Apocalyptica – Plays Metallica',       N'Финландската формация с програма по песни на Metallica.', '2025-09-27 20:00', N'Концерт',         N'Арена София',                    N'Музикален център София ЕООД', 55),
 (N'Стендъп вечер – Есен 2025',            N'Вечер на българската стендъп комедия.',                  '2025-10-18 20:00', N'Стендъп комедия', N'Зала Универсиада',               N'Арт Продакшън ЕООД',          20),
 (N'Лили Иванова – Коледен концерт 2025',  N'Традиционният коледен концерт на Лили Иванова.',         '2025-12-20 19:30', N'Концерт',         N'Арена София',                    N'Музикален център София ЕООД', 45),
 (N'Волейбол: България – Сърбия',          N'Приятелска среща на националните отбори.',               '2026-02-14 18:00', N'Спорт',           N'Зала Универсиада',               N'Спорт Ивентс БГ ООД',         15),
 (N'Класика под звездите',                 N'Софийска филхармония на открито.',                       '2026-06-13 21:00', N'Концерт',         N'Античен театър',                 N'Ивент Партнърс ООД',          25),
 (N'Hooverphonic – Live in Plovdiv',       N'Белгийската група за първи път в Пловдив.',              '2026-07-11 21:00', N'Концерт',         N'Античен театър',                 N'Ивент Партнърс ООД',          40),
 (N'Летни вечери Бургас 2026',             N'Тридневно настроение в една вечер.',                     '2026-08-15 20:00', N'Фестивал',        N'Летен театър Бургас',            N'Музикален център София ЕООД', 30),
 (N'Приказки за малки и големи',           N'Музикален спектакъл за деца.',                           '2026-09-20 11:00', N'Детски',          N'Драматичен театър Стара Загора', N'Арт Продакшън ЕООД',          10),
 (N'Остава – Есенно турне 2026',           N'Нов албум, нови песни и старите хитове.',                '2026-10-10 20:00', N'Концерт',         N'Зала Универсиада',               N'Музикален център София ЕООД', 32),
 (N'Чайка',                                N'Пиесата на Чехов в постановка на ДТ Стара Загора.',      '2026-11-06 19:00', N'Театър',          N'Драматичен театър Стара Загора', N'Арт Продакшън ЕООД',          20),
 (N'Стендъп вечер – Коледно издание 2026', N'Коледна стендъп вечер.',                                 '2026-11-20 20:00', N'Стендъп комедия', N'Зала Универсиада',               N'Арт Продакшън ЕООД',          22),
 (N'Лили Иванова – Коледен концерт 2026',  N'Традиционният коледен концерт на Лили Иванова.',         '2026-12-19 19:30', N'Концерт',         N'Арена София',                    N'Музикален център София ЕООД', 48),
 (N'Б.Т.Р. – Зимно турне 2027',            N'Зимно турне из големите градове.',                       '2027-02-13 20:00', N'Концерт',         N'Арена София',                    N'Ивент Партнърс ООД',          30);

INSERT INTO dbo.Events (Title, Description, StartDateTime, SalesStartDate, Status, CategoryId, VenueId, PromoterId)
SELECT p.Title, p.Description, p.StartAt, DATEADD(DAY, -75, p.StartAt), N'Scheduled',
       c.CategoryId, v.VenueId, pr.PromoterId
FROM #EventPlan p
JOIN dbo.Categories c ON c.Name = p.Category
JOIN dbo.Venues v     ON v.Name = p.Venue
JOIN dbo.Promoters pr ON pr.Name = p.Promoter;

INSERT INTO dbo.EventPerformers (EventId, PerformerId, IsHeadliner, PerformanceOrder)
SELECT e.EventId, pf.PerformerId, x.IsHeadliner, x.PerformanceOrder
FROM (VALUES
 (N'Остава – 25 години на сцена',          N'Остава',                                   1, 1),
 (N'Хамлет',                               N'Трупа на ДТ Стара Загора',                 1, 1),
 (N'Сигнал – Акустично лято',              N'Сигнал',                                   1, 1),
 (N'Рок вечер: Б.Т.Р. и Д2',               N'Д2',                                       0, 1),
 (N'Рок вечер: Б.Т.Р. и Д2',               N'Б.Т.Р.',                                   1, 2),
 (N'Varna Summer Fest 2025',               N'Ицо Хазарта',                              0, 1),
 (N'Varna Summer Fest 2025',               N'Д2',                                       0, 2),
 (N'Varna Summer Fest 2025',               N'Михаела Филева',                           1, 3),
 (N'Apocalyptica – Plays Metallica',       N'Apocalyptica',                             1, 1),
 (N'Стендъп вечер – Есен 2025',            N'Комеди Клуб София',                        1, 1),
 (N'Лили Иванова – Коледен концерт 2025',  N'Лили Иванова',                             1, 1),
 (N'Волейбол: България – Сърбия',          N'Национален отбор по волейбол на България', 1, 1),
 (N'Волейбол: България – Сърбия',          N'Национален отбор по волейбол на Сърбия',   1, 2),
 (N'Класика под звездите',                 N'Софийска филхармония',                     1, 1),
 (N'Hooverphonic – Live in Plovdiv',       N'Hooverphonic',                             1, 1),
 (N'Летни вечери Бургас 2026',             N'Ицо Хазарта',                              0, 1),
 (N'Летни вечери Бургас 2026',             N'Сигнал',                                   0, 2),
 (N'Летни вечери Бургас 2026',             N'Михаела Филева',                           1, 3),
 (N'Приказки за малки и големи',           N'Детски театър „Слънчице“',                 1, 1),
 (N'Остава – Есенно турне 2026',           N'Остава',                                   1, 1),
 (N'Чайка',                                N'Трупа на ДТ Стара Загора',                 1, 1),
 (N'Стендъп вечер – Коледно издание 2026', N'Комеди Клуб София',                        1, 1),
 (N'Лили Иванова – Коледен концерт 2026',  N'Лили Иванова',                             1, 1),
 (N'Б.Т.Р. – Зимно турне 2027',            N'Б.Т.Р.',                                   1, 1)
) x(Title, Performer, IsHeadliner, PerformanceOrder)
JOIN dbo.Events e      ON e.Title = x.Title
JOIN dbo.Performers pf ON pf.Name = x.Performer;

-- Цена = базова цена × коефициент на типа секция, закръглена до x.90
INSERT INTO dbo.EventSectionPrices (EventId, SectionId, Price)
SELECT e.EventId, sec.SectionId,
       CAST(ROUND(p.BasePrice * m.Multiplier, 0) - 0.10 AS DECIMAL(10,2))
FROM #EventPlan p
JOIN dbo.Events e     ON e.Title = p.Title
JOIN dbo.Sections sec ON sec.VenueId = e.VenueId
JOIN (VALUES (N'Parterre', 1.00), (N'Balcony', 0.75), (N'VIP', 2.20), (N'Box', 1.60)) m(SectionType, Multiplier)
     ON m.SectionType = sec.SectionType;

/* ---------------------------------------------------------------------
   Клиенти: 10 мъжки × 10 мъжки фамилии + 10 женски × 10 женски = 200
   Случайните стойности се записват първо във временна таблица, за да не
   се преизчислява NEWID() в CASE изразите.
   --------------------------------------------------------------------- */

CREATE TABLE #FirstNames (Name NVARCHAR(50) COLLATE DATABASE_DEFAULT, Latin VARCHAR(50) COLLATE DATABASE_DEFAULT, Gender CHAR(1) COLLATE DATABASE_DEFAULT);
INSERT INTO #FirstNames VALUES
 (N'Георги','georgi','M'), (N'Иван','ivan','M'), (N'Димитър','dimitar','M'), (N'Николай','nikolay','M'),
 (N'Петър','petar','M'), (N'Александър','aleksandar','M'), (N'Мартин','martin','M'), (N'Христо','hristo','M'),
 (N'Калоян','kaloyan','M'), (N'Виктор','viktor','M'),
 (N'Мария','maria','F'), (N'Елена','elena','F'), (N'Десислава','desislava','F'), (N'Йоана','yoana','F'),
 (N'Николета','nikoleta','F'), (N'Виктория','viktoria','F'), (N'Габриела','gabriela','F'), (N'Цветелина','tsvetelina','F'),
 (N'Ивана','ivana','F'), (N'Симона','simona','F');

CREATE TABLE #LastNames (Name NVARCHAR(50) COLLATE DATABASE_DEFAULT, Latin VARCHAR(50) COLLATE DATABASE_DEFAULT);
INSERT INTO #LastNames VALUES
 (N'Иванов','ivanov'), (N'Петров','petrov'), (N'Георгиев','georgiev'), (N'Димитров','dimitrov'),
 (N'Николов','nikolov'), (N'Стоянов','stoyanov'), (N'Христов','hristov'), (N'Колев','kolev'),
 (N'Тодоров','todorov'), (N'Ангелов','angelov');

SELECT  f.Name AS FirstName,
        CASE WHEN f.Gender = 'F' THEN l.Name + N'а' ELSE l.Name END AS LastName,
        f.Latin + '.' + l.Latin + CASE WHEN f.Gender = 'F' THEN 'a' ELSE '' END AS EmailLocal,
        ROW_NUMBER() OVER (ORDER BY f.Latin, l.Latin) AS rn,
        ABS(CHECKSUM(NEWID()) % 100)                  AS CityRoll,
        ABS(CHECKSUM(NEWID()) % 16425)                AS BirthOffsetDays,     -- ~45 години
        ABS(CHECKSUM(NEWID()) % 1546560)              AS RegisteredOffsetMin, -- 2022-01-01 .. 2024-12-01
        ABS(CHECKSUM(NEWID()) % 10000000)             AS PhoneDigits
INTO #CustomerSeed
FROM #FirstNames f
CROSS JOIN #LastNames l;

INSERT INTO dbo.Customers (FirstName, LastName, Email, Phone, BirthDate, CityId, RegisteredAt)
SELECT  s.FirstName,
        s.LastName,
        s.EmailLocal + '@' + CHOOSE(s.rn % 4 + 1, 'gmail.com', 'abv.bg', 'yahoo.com', 'mail.bg'),
        '+3598' + CHOOSE(s.rn % 3 + 1, '7', '8', '9') + RIGHT('0000000' + CAST(s.PhoneDigits AS VARCHAR(7)), 7),
        DATEADD(DAY, s.BirthOffsetDays, CAST('1962-01-01' AS DATE)),
        c.CityId,
        DATEADD(MINUTE, s.RegisteredOffsetMin, CAST('2022-01-01' AS DATETIME2(0)))
FROM #CustomerSeed s
JOIN dbo.Cities c ON c.Name = CASE
        WHEN s.CityRoll < 35 THEN N'София'
        WHEN s.CityRoll < 55 THEN N'Пловдив'
        WHEN s.CityRoll < 68 THEN N'Варна'
        WHEN s.CityRoll < 78 THEN N'Бургас'
        WHEN s.CityRoll < 86 THEN N'Стара Загора'
        WHEN s.CityRoll < 93 THEN N'Русе'
        ELSE N'Велико Търново' END;
GO

/* ---------------------------------------------------------------------
   Продажби: за всяко събитие с започнала продажба се правят поръчки
   през sp_PurchaseTickets до случайна целева заетост 55–95 %.
   За предстоящите събития целта се намалява пропорционално на
   изминалата част от периода на продажба.
   Една поръчка е 1–4 съседни места на един ред.
   --------------------------------------------------------------------- */

DECLARE @Now DATETIME2(0) = SYSDATETIME();
DECLARE @EventId INT, @SalesStart DATETIME2(0), @Start DATETIME2(0), @WindowEnd DATETIME2(0),
        @WindowMin INT, @Capacity INT, @Target INT, @Sold INT, @Guard INT,
        @Qty INT, @AnchorSection INT, @AnchorRow INT, @AnchorNo INT,
        @CustomerId INT, @OrderDate DATETIME2(0), @PayRoll INT, @Payment NVARCHAR(20), @OrderId INT;
DECLARE @Seats dbo.SeatIdList;

DECLARE event_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT EventId, SalesStartDate, StartDateTime
    FROM dbo.Events
    WHERE SalesStartDate < @Now
    ORDER BY StartDateTime;

OPEN event_cursor;
FETCH NEXT FROM event_cursor INTO @EventId, @SalesStart, @Start;

WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @Capacity = COUNT(*) FROM dbo.fn_GetAvailableSeats(@EventId);

    SET @WindowEnd = CASE WHEN @Start < @Now THEN DATEADD(MINUTE, -30, @Start) ELSE @Now END;
    SET @WindowMin = DATEDIFF(MINUTE, @SalesStart, @WindowEnd);
    SET @Target    = @Capacity * (55 + ABS(CHECKSUM(NEWID()) % 41)) / 100;

    IF @Start > @Now
        SET @Target = @Target * DATEDIFF(DAY, @SalesStart, @Now) / NULLIF(DATEDIFF(DAY, @SalesStart, @Start), 0);

    SELECT @Sold = 0, @Guard = 0;

    WHILE @Sold < @Target AND @Guard < 5000
    BEGIN
        SET @Guard += 1;
        SET @Qty = 1 + ABS(CHECKSUM(NEWID()) % 4);

        -- случайно свободно място, около което да се вземат съседните
        SELECT TOP (1) @AnchorSection = SectionId, @AnchorRow = RowNumber, @AnchorNo = SeatNumber
        FROM dbo.fn_GetAvailableSeats(@EventId)
        ORDER BY NEWID();

        DELETE FROM @Seats;
        INSERT INTO @Seats (SeatId)
        SELECT TOP (@Qty) SeatId
        FROM dbo.fn_GetAvailableSeats(@EventId)
        WHERE SectionId = @AnchorSection AND RowNumber = @AnchorRow
        ORDER BY ABS(SeatNumber - @AnchorNo);

        SELECT TOP (1) @CustomerId = CustomerId FROM dbo.Customers ORDER BY NEWID();

        -- SQRT изкривява разпределението към датата на събитието:
        -- повечето билети се купуват в последните седмици
        SET @OrderDate = DATEADD(MINUTE,
                                 CAST(@WindowMin * SQRT(ABS(CHECKSUM(NEWID()) % 10000) / 10000.0) AS INT),
                                 @SalesStart);

        SET @PayRoll = 1 + ABS(CHECKSUM(NEWID()) % 10);
        SET @Payment = CHOOSE(@PayRoll, N'Card', N'Card', N'Card', N'Card', N'GooglePay',
                                        N'ApplePay', N'ApplePay', N'PayPal', N'PayPal', N'BankTransfer');

        EXEC dbo.sp_PurchaseTickets
             @CustomerId    = @CustomerId,
             @EventId       = @EventId,
             @SeatIds       = @Seats,
             @PaymentMethod = @Payment,
             @OrderDate     = @OrderDate,
             @OrderId       = @OrderId OUTPUT;

        SET @Sold += (SELECT COUNT(*) FROM @Seats);
    END;

    FETCH NEXT FROM event_cursor INTO @EventId, @SalesStart, @Start;
END;

CLOSE event_cursor;
DEALLOCATE event_cursor;
GO

/* ---------------------------------------------------------------------
   Индивидуални възстановявания (~3 % от билетите) през sp_RefundTicket
   --------------------------------------------------------------------- */

DECLARE @Now DATETIME2(0) = SYSDATETIME();
DECLARE @TicketId INT, @OrderDate DATETIME2(0), @Start DATETIME2(0), @RefundAt DATETIME2(0),
        @ReasonRoll INT, @Reason NVARCHAR(255);

DECLARE refund_cursor CURSOR LOCAL STATIC FORWARD_ONLY FOR
    SELECT t.TicketId, o.OrderDate, e.StartDateTime
    FROM dbo.Tickets t
    JOIN dbo.Orders o ON o.OrderId = t.OrderId
    JOIN dbo.Events e ON e.EventId = t.EventId
    WHERE t.Status = N'Valid'
      AND ABS(CHECKSUM(NEWID()) % 100) < 3;

OPEN refund_cursor;
FETCH NEXT FROM refund_cursor INTO @TicketId, @OrderDate, @Start;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @RefundAt = DATEADD(MINUTE,
                            ABS(CHECKSUM(NEWID()) % (DATEDIFF(MINUTE, @OrderDate,
                                CASE WHEN @Start < @Now THEN @Start ELSE @Now END) + 1)),
                            @OrderDate);

    SET @ReasonRoll = 1 + ABS(CHECKSUM(NEWID()) % 4);
    SET @Reason = CHOOSE(@ReasonRoll, N'Клиентът не може да присъства.', N'Грешно избрана дата.',
                                      N'Болест.', N'Двойна покупка.');

    EXEC dbo.sp_RefundTicket @TicketId = @TicketId, @Reason = @Reason, @RefundedAt = @RefundAt;

    FETCH NEXT FROM refund_cursor INTO @TicketId, @OrderDate, @Start;
END;

CLOSE refund_cursor;
DEALLOCATE refund_cursor;
GO

/* ---------------------------------------------------------------------
   Отменено събитие – всички билети се възстановяват автоматично
   --------------------------------------------------------------------- */

DECLARE @CancelledEventId INT =
    (SELECT EventId FROM dbo.Events WHERE Title = N'Стендъп вечер – Коледно издание 2026');

EXEC dbo.sp_CancelEvent
     @EventId = @CancelledEventId,
     @Reason  = N'Отменено поради заболяване на участник.';
GO

/* ---------------------------------------------------------------------
   Влизания за минали събития: ~93 % от валидните билети са сканирани
   между 2 часа преди и 20 минути след началото.
   --------------------------------------------------------------------- */

UPDATE t
SET t.Status      = N'Used',
    t.CheckedInAt = DATEADD(MINUTE, ABS(CHECKSUM(NEWID()) % 140) - 120, e.StartDateTime)
FROM dbo.Tickets t
JOIN dbo.Events e ON e.EventId = t.EventId
WHERE t.Status = N'Valid'
  AND e.StartDateTime < SYSDATETIME()
  AND ABS(CHECKSUM(NEWID()) % 100) < 93;

UPDATE dbo.Events
SET Status = N'Completed'
WHERE Status = N'Scheduled'
  AND StartDateTime < SYSDATETIME();
GO

DROP TABLE IF EXISTS #SectionPlan, #Nums, #EventPlan, #FirstNames, #LastNames, #CustomerSeed;
GO

/* ---------------------------------------------------------------------
   Обобщение
   --------------------------------------------------------------------- */

SELECT 'Cities' AS TableName, COUNT(*) AS RowCnt FROM dbo.Cities
UNION ALL SELECT 'Customers',          COUNT(*) FROM dbo.Customers
UNION ALL SELECT 'Venues',             COUNT(*) FROM dbo.Venues
UNION ALL SELECT 'Sections',           COUNT(*) FROM dbo.Sections
UNION ALL SELECT 'Seats',              COUNT(*) FROM dbo.Seats
UNION ALL SELECT 'Categories',         COUNT(*) FROM dbo.Categories
UNION ALL SELECT 'Performers',         COUNT(*) FROM dbo.Performers
UNION ALL SELECT 'Promoters',          COUNT(*) FROM dbo.Promoters
UNION ALL SELECT 'Events',             COUNT(*) FROM dbo.Events
UNION ALL SELECT 'EventPerformers',    COUNT(*) FROM dbo.EventPerformers
UNION ALL SELECT 'EventSectionPrices', COUNT(*) FROM dbo.EventSectionPrices
UNION ALL SELECT 'Orders',             COUNT(*) FROM dbo.Orders
UNION ALL SELECT 'Tickets',            COUNT(*) FROM dbo.Tickets
UNION ALL SELECT 'Refunds',            COUNT(*) FROM dbo.Refunds;

SELECT * FROM dbo.vw_EventSalesSummary ORDER BY StartDateTime;
GO

SET NOEXEC OFF;
GO