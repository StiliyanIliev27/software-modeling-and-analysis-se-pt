/* =====================================================================
   Eventim – 06_dw_etl.sql
   ETL: EventimDB (OLTP) -> EventimDW (звездна схема)
   Пълно презареждане: факти и измерения се изтриват и зареждат наново.
   DimDate и DimPaymentMethod са статични и не се пипат.
   Може да се пуска многократно: EXEC dbo.sp_LoadDW;
   ===================================================================== */

USE EventimDW;
GO

CREATE OR ALTER PROCEDURE dbo.sp_LoadDW
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RunId INT, @Today DATE = CAST(SYSDATETIME() AS DATE),
            @RowsSales INT, @RowsCheckIns INT, @RowsRefunds INT;

    INSERT INTO dbo.EtlLog (StartedAt, Status) VALUES (SYSDATETIME(), N'Running');
    SET @RunId = SCOPE_IDENTITY();

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- 1. Изчистване (първо фактите заради FK) ---------- */
        DELETE FROM dbo.FactCheckIns;
        DELETE FROM dbo.FactRefunds;
        DELETE FROM dbo.FactTicketSales;
        DELETE FROM dbo.DimCustomer;
        DELETE FROM dbo.DimEvent;
        DELETE FROM dbo.DimVenue;
        DELETE FROM dbo.DimSection;
        DELETE FROM dbo.DimPerformer;
        DELETE FROM dbo.DimCategory;

        /* ---------- 2. Измерения ---------- */

        INSERT INTO dbo.DimCategory (CategoryId, CategoryName)
        SELECT CategoryId, Name
        FROM EventimDB.dbo.Categories;

        INSERT INTO dbo.DimPerformer (PerformerId, PerformerName, Genre, Country)
        SELECT PerformerId, Name, ISNULL(Genre, N'Неизвестен'), ISNULL(Country, N'Неизвестна')
        FROM EventimDB.dbo.Performers;

        INSERT INTO dbo.DimCustomer (CustomerId, FullName, Email, City, AgeGroup, RegistrationYear)
        SELECT  c.CustomerId,
                c.FirstName + N' ' + c.LastName,
                c.Email,
                ci.Name,
                CASE WHEN a.Age IS NULL THEN N'Неизвестна'
                     WHEN a.Age < 18   THEN N'Под 18'
                     WHEN a.Age < 25   THEN N'18–24'
                     WHEN a.Age < 35   THEN N'25–34'
                     WHEN a.Age < 45   THEN N'35–44'
                     WHEN a.Age < 55   THEN N'45–54'
                     ELSE N'55+' END,
                YEAR(c.RegisteredAt)
        FROM EventimDB.dbo.Customers c
        JOIN EventimDB.dbo.Cities ci ON ci.CityId = c.CityId
        -- точна възраст: години разлика минус 1, ако рожденият ден още не е минал
        CROSS APPLY (SELECT DATEDIFF(YEAR, c.BirthDate, @Today)
                            - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, c.BirthDate, @Today), c.BirthDate) > @Today
                                   THEN 1 ELSE 0 END AS Age) a;

        INSERT INTO dbo.DimVenue (VenueId, VenueName, City, Country, Capacity)
        SELECT  v.VenueId, v.Name, ci.Name, ci.Country,
                (SELECT COUNT(*)
                 FROM EventimDB.dbo.Sections sec
                 JOIN EventimDB.dbo.Seats s ON s.SectionId = sec.SectionId
                 WHERE sec.VenueId = v.VenueId)
        FROM EventimDB.dbo.Venues v
        JOIN EventimDB.dbo.Cities ci ON ci.CityId = v.CityId;

        INSERT INTO dbo.DimSection (SectionId, SectionName, SectionType, VenueName, SeatsCount)
        SELECT  sec.SectionId, sec.Name, sec.SectionType, v.Name,
                (SELECT COUNT(*) FROM EventimDB.dbo.Seats s WHERE s.SectionId = sec.SectionId)
        FROM EventimDB.dbo.Sections sec
        JOIN EventimDB.dbo.Venues v ON v.VenueId = sec.VenueId;

        INSERT INTO dbo.DimEvent (EventId, Title, Promoter, EventStatus, StartDateTime, DayPart)
        SELECT  e.EventId, e.Title, p.Name, e.Status, e.StartDateTime,
                CASE WHEN DATEPART(HOUR, e.StartDateTime) < 12 THEN N'Сутрин'
                     WHEN DATEPART(HOUR, e.StartDateTime) < 18 THEN N'Следобед'
                     ELSE N'Вечер' END
        FROM EventimDB.dbo.Events e
        JOIN EventimDB.dbo.Promoters p ON p.PromoterId = e.PromoterId;

        /* ---------- 3. Общ източник за фактите ----------
           Един ред на билет с всички бизнес ключове; хедлайнерът е изпълнителят
           с IsHeadliner = 1 и най-малък PerformanceOrder. */

        SELECT  t.TicketId,
                t.OrderId,
                t.Price,
                t.Status          AS TicketStatus,
                t.CheckedInAt,
                o.OrderDate,
                o.CustomerId,
                pm.PaymentMethodKey,
                e.EventId,
                e.StartDateTime,
                e.Status          AS EventStatus,
                e.CategoryId,
                e.VenueId,
                s.SectionId,
                h.PerformerId
        INTO #TicketSource
        FROM EventimDB.dbo.Tickets t
        JOIN EventimDB.dbo.Orders o   ON o.OrderId = t.OrderId
        JOIN EventimDB.dbo.Events e   ON e.EventId = t.EventId
        JOIN EventimDB.dbo.Seats s    ON s.SeatId = t.SeatId
        JOIN dbo.DimPaymentMethod pm  ON pm.PaymentMethodCode = o.PaymentMethod
        CROSS APPLY (SELECT TOP (1) ep.PerformerId
                     FROM EventimDB.dbo.EventPerformers ep
                     WHERE ep.EventId = e.EventId
                     ORDER BY ep.IsHeadliner DESC, ep.PerformanceOrder) h;

        /* ---------- 4. FactTicketSales ---------- */

        INSERT INTO dbo.FactTicketSales
            (TicketId, OrderId, OrderDateKey, EventDateKey, CustomerKey, EventKey, VenueKey,
             SectionKey, PerformerKey, CategoryKey, PaymentMethodKey,
             SalesAmount, TicketCount, DaysBeforeEvent, IsRefunded)
        SELECT  src.TicketId,
                src.OrderId,
                CONVERT(INT, CONVERT(CHAR(8), src.OrderDate, 112)),
                CONVERT(INT, CONVERT(CHAR(8), src.StartDateTime, 112)),
                dc.CustomerKey, de.EventKey, dv.VenueKey, ds.SectionKey,
                dp.PerformerKey, dcat.CategoryKey, src.PaymentMethodKey,
                src.Price,
                1,
                DATEDIFF(DAY, src.OrderDate, src.StartDateTime),
                CASE WHEN src.TicketStatus = N'Refunded' THEN 1 ELSE 0 END
        FROM #TicketSource src
        JOIN dbo.DimCustomer dc   ON dc.CustomerId = src.CustomerId
        JOIN dbo.DimEvent de      ON de.EventId = src.EventId
        JOIN dbo.DimVenue dv      ON dv.VenueId = src.VenueId
        JOIN dbo.DimSection ds    ON ds.SectionId = src.SectionId
        JOIN dbo.DimPerformer dp  ON dp.PerformerId = src.PerformerId
        JOIN dbo.DimCategory dcat ON dcat.CategoryId = src.CategoryId;

        SET @RowsSales = @@ROWCOUNT;

        /* ---------- 5. FactCheckIns ---------- */

        INSERT INTO dbo.FactCheckIns
            (TicketId, CheckInDateKey, CustomerKey, EventKey, VenueKey, SectionKey,
             PerformerKey, CategoryKey, MinutesBeforeStart, CheckInHour, IsLate, AttendanceCount)
        SELECT  src.TicketId,
                CONVERT(INT, CONVERT(CHAR(8), src.CheckedInAt, 112)),
                dc.CustomerKey, de.EventKey, dv.VenueKey, ds.SectionKey,
                dp.PerformerKey, dcat.CategoryKey,
                DATEDIFF(MINUTE, src.CheckedInAt, src.StartDateTime),
                DATEPART(HOUR, src.CheckedInAt),
                CASE WHEN src.CheckedInAt > src.StartDateTime THEN 1 ELSE 0 END,
                1
        FROM #TicketSource src
        JOIN dbo.DimCustomer dc   ON dc.CustomerId = src.CustomerId
        JOIN dbo.DimEvent de      ON de.EventId = src.EventId
        JOIN dbo.DimVenue dv      ON dv.VenueId = src.VenueId
        JOIN dbo.DimSection ds    ON ds.SectionId = src.SectionId
        JOIN dbo.DimPerformer dp  ON dp.PerformerId = src.PerformerId
        JOIN dbo.DimCategory dcat ON dcat.CategoryId = src.CategoryId
        WHERE src.CheckedInAt IS NOT NULL;

        SET @RowsCheckIns = @@ROWCOUNT;

        /* ---------- 6. FactRefunds ---------- */

        INSERT INTO dbo.FactRefunds
            (RefundId, TicketId, RefundDateKey, CustomerKey, EventKey, VenueKey, SectionKey,
             PerformerKey, CategoryKey, PaymentMethodKey, RefundAmount, DaysBeforeEvent, IsEventCancellation)
        SELECT  r.RefundId,
                src.TicketId,
                CONVERT(INT, CONVERT(CHAR(8), r.RefundedAt, 112)),
                dc.CustomerKey, de.EventKey, dv.VenueKey, ds.SectionKey,
                dp.PerformerKey, dcat.CategoryKey, src.PaymentMethodKey,
                r.Amount,
                DATEDIFF(DAY, r.RefundedAt, src.StartDateTime),
                CASE WHEN src.EventStatus = N'Cancelled' THEN 1 ELSE 0 END
        FROM EventimDB.dbo.Refunds r
        JOIN #TicketSource src    ON src.TicketId = r.TicketId
        JOIN dbo.DimCustomer dc   ON dc.CustomerId = src.CustomerId
        JOIN dbo.DimEvent de      ON de.EventId = src.EventId
        JOIN dbo.DimVenue dv      ON dv.VenueId = src.VenueId
        JOIN dbo.DimSection ds    ON ds.SectionId = src.SectionId
        JOIN dbo.DimPerformer dp  ON dp.PerformerId = src.PerformerId
        JOIN dbo.DimCategory dcat ON dcat.CategoryId = src.CategoryId;

        SET @RowsRefunds = @@ROWCOUNT;

        COMMIT TRANSACTION;

        UPDATE dbo.EtlLog
        SET FinishedAt = SYSDATETIME(), Status = N'Succeeded',
            RowsSales = @RowsSales, RowsCheckIns = @RowsCheckIns, RowsRefunds = @RowsRefunds
        WHERE RunId = @RunId;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        UPDATE dbo.EtlLog
        SET FinishedAt = SYSDATETIME(), Status = N'Failed', ErrorMessage = ERROR_MESSAGE()
        WHERE RunId = @RunId;

        THROW;
    END CATCH
END;
GO

/* ---------- Изпълнение и проверка ---------- */

EXEC dbo.sp_LoadDW;
GO

SELECT TOP (1) * FROM dbo.EtlLog ORDER BY RunId DESC;

-- Контрола: сумите в DW трябва да съвпадат с оперативната база
SELECT  (SELECT SUM(SalesAmount)  FROM dbo.FactTicketSales)          AS DW_Sales,
        (SELECT SUM(Price)        FROM EventimDB.dbo.Tickets)        AS OLTP_Sales,
        (SELECT SUM(RefundAmount) FROM dbo.FactRefunds)              AS DW_Refunds,
        (SELECT SUM(Amount)       FROM EventimDB.dbo.Refunds)        AS OLTP_Refunds,
        (SELECT COUNT(*)          FROM dbo.FactCheckIns)             AS DW_CheckIns,
        (SELECT COUNT(*) FROM EventimDB.dbo.Tickets WHERE Status = N'Used') AS OLTP_CheckIns;

-- Пример за аналитична заявка: приходи по категория и тримесечие
SELECT  d.CalendarYear, d.CalendarQuarter, c.CategoryName,
        SUM(f.SalesAmount) AS Revenue, SUM(f.TicketCount) AS Tickets
FROM dbo.FactTicketSales f
JOIN dbo.DimDate d     ON d.DateKey = f.OrderDateKey
JOIN dbo.DimCategory c ON c.CategoryKey = f.CategoryKey
GROUP BY d.CalendarYear, d.CalendarQuarter, c.CategoryName
ORDER BY d.CalendarYear, d.CalendarQuarter, Revenue DESC;
GO