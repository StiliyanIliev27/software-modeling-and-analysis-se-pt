/* =====================================================================
   Eventim – 02_programmability.sql
   Функции, съхранени процедури, тригери и изглед
   Кодове на грешките: 500xx – процедури, 500(1-3)x – тригери
   ===================================================================== */

USE EventimDB;
GO

-- Табличен тип за подаване на списък с места към sp_PurchaseTickets
CREATE TYPE dbo.SeatIdList AS TABLE
(
    SeatId INT NOT NULL PRIMARY KEY
);
GO

/* =====================================================================
   ФУНКЦИИ
   ===================================================================== */

-- 1) Таблична функция: свободните места за събитие с цената им.
--    Място е свободно, ако е в залата на събитието, има цена за секцията
--    и няма активен (Valid/Used) билет за него.
CREATE FUNCTION dbo.fn_GetAvailableSeats (@EventId INT)
RETURNS TABLE
AS
RETURN
(
    SELECT  s.SeatId,
            sec.SectionId,
            sec.Name        AS SectionName,
            sec.SectionType,
            s.RowNumber,
            s.SeatNumber,
            p.Price
    FROM dbo.Events e
    JOIN dbo.Sections sec           ON sec.VenueId = e.VenueId
    JOIN dbo.EventSectionPrices p   ON p.EventId = e.EventId AND p.SectionId = sec.SectionId
    JOIN dbo.Seats s                ON s.SectionId = sec.SectionId
    WHERE e.EventId = @EventId
      AND NOT EXISTS (SELECT 1
                      FROM dbo.Tickets t
                      WHERE t.EventId = e.EventId
                        AND t.SeatId = s.SeatId
                        AND t.Status IN (N'Valid', N'Used'))
);
GO

-- 2) Скаларна функция: заетост на събитие в проценти
CREATE FUNCTION dbo.fn_EventOccupancy (@EventId INT)
RETURNS DECIMAL(5,2)
AS
BEGIN
    DECLARE @TotalSeats INT, @SoldSeats INT;

    SELECT @TotalSeats = COUNT(*)
    FROM dbo.EventSectionPrices p
    JOIN dbo.Seats s ON s.SectionId = p.SectionId
    WHERE p.EventId = @EventId;

    SELECT @SoldSeats = COUNT(*)
    FROM dbo.Tickets
    WHERE EventId = @EventId
      AND Status IN (N'Valid', N'Used');

    RETURN CASE WHEN @TotalSeats = 0 THEN 0
                ELSE CAST(@SoldSeats * 100.0 / @TotalSeats AS DECIMAL(5,2)) END;
END;
GO

-- 3) Скаларна функция: колко реално е похарчил клиент (покупки минус възстановени суми)
CREATE FUNCTION dbo.fn_CustomerTotalSpent (@CustomerId INT)
RETURNS DECIMAL(12,2)
AS
BEGIN
    DECLARE @Spent DECIMAL(12,2), @Refunded DECIMAL(12,2);

    SELECT @Spent = ISNULL(SUM(t.Price), 0)
    FROM dbo.Orders o
    JOIN dbo.Tickets t ON t.OrderId = o.OrderId
    WHERE o.CustomerId = @CustomerId;

    SELECT @Refunded = ISNULL(SUM(r.Amount), 0)
    FROM dbo.Orders o
    JOIN dbo.Tickets t ON t.OrderId = o.OrderId
    JOIN dbo.Refunds r ON r.TicketId = t.TicketId
    WHERE o.CustomerId = @CustomerId;

    RETURN @Spent - @Refunded;
END;
GO

/* =====================================================================
   СЪХРАНЕНИ ПРОЦЕДУРИ
   ===================================================================== */

-- 1) Покупка на билети: поръчка + билети в една транзакция.
--    @OrderDate е по избор (използва се при пълнене с исторически данни).
CREATE PROCEDURE dbo.sp_PurchaseTickets
    @CustomerId    INT,
    @EventId       INT,
    @SeatIds       dbo.SeatIdList READONLY,
    @PaymentMethod NVARCHAR(20) = N'Card',
    @OrderDate     DATETIME2(0) = NULL,
    @OrderId       INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @OrderDate = ISNULL(@OrderDate, SYSDATETIME());

    IF NOT EXISTS (SELECT 1 FROM @SeatIds)
        THROW 50001, N'Не са избрани места.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerId = @CustomerId)
        THROW 50002, N'Клиентът не съществува.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Events WHERE EventId = @EventId AND Status = N'Scheduled')
        THROW 50003, N'Събитието не съществува или не е активно.', 1;

    IF EXISTS (SELECT 1
               FROM @SeatIds s
               WHERE NOT EXISTS (SELECT 1 FROM dbo.fn_GetAvailableSeats(@EventId) a
                                 WHERE a.SeatId = s.SeatId))
        THROW 50004, N'Едно или повече от избраните места не са свободни за това събитие.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.Orders (CustomerId, OrderDate, TotalAmount, PaymentMethod, Status)
        VALUES (@CustomerId, @OrderDate, 0, @PaymentMethod, N'Paid');

        SET @OrderId = SCOPE_IDENTITY();

        -- Цената се взима от EventSectionPrices, не се подава отвън.
        -- TotalAmount на поръчката се изчислява от тригер.
        INSERT INTO dbo.Tickets (OrderId, EventId, SeatId, Price, TicketCode, Status)
        SELECT  @OrderId,
                @EventId,
                a.SeatId,
                a.Price,
                CONCAT(N'EV', @EventId, N'-',
                       LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12)),
                N'Valid'
        FROM dbo.fn_GetAvailableSeats(@EventId) a
        JOIN @SeatIds s ON s.SeatId = a.SeatId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 2) Възстановяване на сума за един билет.
--    Самата промяна на статусите прави тригерът trg_Refunds_ProcessRefund.
CREATE PROCEDURE dbo.sp_RefundTicket
    @TicketId   INT,
    @Reason     NVARCHAR(255) = NULL,
    @RefundedAt DATETIME2(0)  = NULL,
    @RefundId   INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Tickets WHERE TicketId = @TicketId AND Status = N'Valid')
        THROW 50020, N'Билетът не съществува, вече е използван или вече е възстановен.', 1;

    INSERT INTO dbo.Refunds (TicketId, Amount, Reason, RefundedAt)
    SELECT TicketId, Price, @Reason, ISNULL(@RefundedAt, SYSDATETIME())
    FROM dbo.Tickets
    WHERE TicketId = @TicketId;

    SET @RefundId = SCOPE_IDENTITY();
END;
GO

-- 3) Отменяне на събитие с автоматично възстановяване на всички валидни билети
CREATE PROCEDURE dbo.sp_CancelEvent
    @EventId         INT,
    @Reason          NVARCHAR(255) = N'Събитието е отменено от организатора.',
    @CancelledAt     DATETIME2(0)  = NULL,
    @RefundedTickets INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @CancelledAt = ISNULL(@CancelledAt, SYSDATETIME());

    IF NOT EXISTS (SELECT 1 FROM dbo.Events WHERE EventId = @EventId AND Status = N'Scheduled')
        THROW 50040, N'Може да се отмени само предстоящо събитие (Status = Scheduled).', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Events
        SET Status = N'Cancelled'
        WHERE EventId = @EventId;

        SELECT @RefundedTickets = COUNT(*)
        FROM dbo.Tickets
        WHERE EventId = @EventId AND Status = N'Valid';

        INSERT INTO dbo.Refunds (TicketId, Amount, Reason, RefundedAt)
        SELECT TicketId, Price, @Reason, @CancelledAt
        FROM dbo.Tickets
        WHERE EventId = @EventId AND Status = N'Valid';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 4) Сканиране на билет на входа
CREATE PROCEDURE dbo.sp_CheckInTicket
    @TicketCode  NVARCHAR(32),
    @CheckedInAt DATETIME2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @CheckedInAt = ISNULL(@CheckedInAt, SYSDATETIME());

    DECLARE @TicketId INT, @TicketStatus NVARCHAR(20),
            @EventStart DATETIME2(0), @EventStatus NVARCHAR(20);

    SELECT  @TicketId     = t.TicketId,
            @TicketStatus = t.Status,
            @EventStart   = e.StartDateTime,
            @EventStatus  = e.Status
    FROM dbo.Tickets t
    JOIN dbo.Events e ON e.EventId = t.EventId
    WHERE t.TicketCode = @TicketCode;

    IF @TicketId IS NULL
        THROW 50050, N'Невалиден код на билет.', 1;
    IF @TicketStatus = N'Used'
        THROW 50051, N'Билетът вече е използван.', 1;
    IF @TicketStatus = N'Refunded'
        THROW 50052, N'Билетът е възстановен и не е валиден.', 1;
    IF @EventStatus = N'Cancelled'
        THROW 50053, N'Събитието е отменено.', 1;
    IF @CheckedInAt < DATEADD(HOUR, -3, @EventStart) OR @CheckedInAt > DATEADD(HOUR, 3, @EventStart)
        THROW 50054, N'Вход се допуска от 3 часа преди до 3 часа след началото на събитието.', 1;

    UPDATE dbo.Tickets
    SET Status = N'Used', CheckedInAt = @CheckedInAt
    WHERE TicketId = @TicketId AND Status = N'Valid';
END;
GO

/* =====================================================================
   ТРИГЕРИ (написани за многоредови операции – работят с inserted/deleted)
   ===================================================================== */

-- 1) Проверки при продажба, които обикновен CHECK/FK не може да направи,
--    защото засягат няколко таблици.
CREATE TRIGGER dbo.trg_Tickets_ValidateSale
ON dbo.Tickets
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- мястото трябва да е в залата, в която се провежда събитието
    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN dbo.Events e     ON e.EventId = i.EventId
               JOIN dbo.Seats s      ON s.SeatId = i.SeatId
               JOIN dbo.Sections sec ON sec.SectionId = s.SectionId
               WHERE sec.VenueId <> e.VenueId)
        THROW 50010, N'Мястото не принадлежи на залата, в която се провежда събитието.', 1;

    -- не се продават билети за отменено събитие
    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN dbo.Events e ON e.EventId = i.EventId
               WHERE e.Status = N'Cancelled')
        THROW 50011, N'Събитието е отменено – продажбата е спряна.', 1;

    -- поръчката трябва да е в периода на продажба
    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN dbo.Orders o ON o.OrderId = i.OrderId
               JOIN dbo.Events e ON e.EventId = i.EventId
               WHERE o.OrderDate < e.SalesStartDate
                  OR o.OrderDate >= e.StartDateTime)
        THROW 50012, N'Продажбата за събитието не е започнала или събитието вече е започнало.', 1;

    -- секцията трябва да има цена за това събитие
    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN dbo.Seats s ON s.SeatId = i.SeatId
               WHERE NOT EXISTS (SELECT 1 FROM dbo.EventSectionPrices p
                                 WHERE p.EventId = i.EventId AND p.SectionId = s.SectionId))
        THROW 50013, N'Няма определена цена за тази секция на събитието.', 1;
END;
GO

-- 2) Поддържа Orders.TotalAmount = сумата от цените на билетите в поръчката
CREATE TRIGGER dbo.trg_Tickets_RecalculateOrderTotal
ON dbo.Tickets
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- при UPDATE преизчисляваме само ако е сменена цената или поръчката
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
       AND NOT (UPDATE(Price) OR UPDATE(OrderId))
        RETURN;

    UPDATE o
    SET TotalAmount = ISNULL((SELECT SUM(t.Price)
                              FROM dbo.Tickets t
                              WHERE t.OrderId = o.OrderId), 0)
    FROM dbo.Orders o
    WHERE o.OrderId IN (SELECT OrderId FROM inserted
                        UNION
                        SELECT OrderId FROM deleted);
END;
GO

-- 3) Обработка на възстановяване: валидира сумата, маркира билета като
--    Refunded (мястото се освобождава) и обновява статуса на поръчката.
CREATE TRIGGER dbo.trg_Refunds_ProcessRefund
ON dbo.Refunds
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN dbo.Tickets t ON t.TicketId = i.TicketId
               WHERE t.Status <> N'Valid')
        THROW 50030, N'Може да се възстанови само валиден (неизползван) билет.', 1;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN dbo.Tickets t ON t.TicketId = i.TicketId
               WHERE i.Amount > t.Price)
        THROW 50031, N'Сумата за възстановяване не може да надвишава цената на билета.', 1;

    UPDATE t
    SET Status = N'Refunded'
    FROM dbo.Tickets t
    JOIN inserted i ON i.TicketId = t.TicketId;

    UPDATE o
    SET Status = CASE WHEN EXISTS (SELECT 1 FROM dbo.Tickets t
                                   WHERE t.OrderId = o.OrderId AND t.Status <> N'Refunded')
                      THEN N'PartiallyRefunded'
                      ELSE N'Refunded' END
    FROM dbo.Orders o
    WHERE o.OrderId IN (SELECT t.OrderId
                        FROM dbo.Tickets t
                        JOIN inserted i ON i.TicketId = t.TicketId);
END;
GO

/* =====================================================================
   ИЗГЛЕД (допълнение) – обобщение на продажбите по събитие
   ===================================================================== */

CREATE VIEW dbo.vw_EventSalesSummary
AS
SELECT  e.EventId,
        e.Title,
        c.Name  AS Category,
        v.Name  AS Venue,
        ci.Name AS City,
        e.StartDateTime,
        e.Status,
        COUNT(CASE WHEN t.Status IN (N'Valid', N'Used') THEN 1 END)                  AS TicketsSold,
        COUNT(CASE WHEN t.Status = N'Refunded' THEN 1 END)                           AS TicketsRefunded,
        ISNULL(SUM(CASE WHEN t.Status IN (N'Valid', N'Used') THEN t.Price END), 0)   AS NetRevenue,
        dbo.fn_EventOccupancy(e.EventId)                                             AS OccupancyPercent
FROM dbo.Events e
JOIN dbo.Categories c ON c.CategoryId = e.CategoryId
JOIN dbo.Venues v     ON v.VenueId = e.VenueId
JOIN dbo.Cities ci    ON ci.CityId = v.CityId
LEFT JOIN dbo.Tickets t ON t.EventId = e.EventId
GROUP BY e.EventId, e.Title, c.Name, v.Name, ci.Name, e.StartDateTime, e.Status;
GO