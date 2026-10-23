/* =====================================================================
   Eventim – 04_demo.sql
   Демонстрация на функциите, процедурите и тригерите (за защитата).
   Изпълнявайте секциите една по една (маркирате и F5).
   Внимание: скриптът прави реална покупка и възстановяване.
   ===================================================================== */

USE EventimDB;
GO

/* ---------- Функции ---------- */

-- Свободни места за коледния концерт 2026
DECLARE @EventId INT = (SELECT EventId FROM dbo.Events WHERE Title = N'Лили Иванова – Коледен концерт 2026');

SELECT TOP (20) * FROM dbo.fn_GetAvailableSeats(@EventId)
ORDER BY SectionId, RowNumber, SeatNumber;

-- Заетост на всяко събитие
SELECT EventId, Title, Status, dbo.fn_EventOccupancy(EventId) AS OccupancyPercent
FROM dbo.Events
ORDER BY StartDateTime;

-- Топ 10 клиенти по реално похарчена сума
SELECT TOP (10) CustomerId, FirstName, LastName, dbo.fn_CustomerTotalSpent(CustomerId) AS TotalSpent
FROM dbo.Customers
ORDER BY TotalSpent DESC;
GO

/* ---------- sp_PurchaseTickets + тригер за сумата на поръчката ---------- */

DECLARE @EventId INT = (SELECT EventId FROM dbo.Events WHERE Title = N'Лили Иванова – Коледен концерт 2026');
DECLARE @Seats dbo.SeatIdList, @OrderId INT;

INSERT INTO @Seats (SeatId)
SELECT TOP (2) SeatId FROM dbo.fn_GetAvailableSeats(@EventId)
WHERE SectionType = N'VIP'
ORDER BY RowNumber, SeatNumber;

EXEC dbo.sp_PurchaseTickets @CustomerId = 1, @EventId = @EventId, @SeatIds = @Seats,
                            @PaymentMethod = N'Card', @OrderId = @OrderId OUTPUT;

-- TotalAmount е попълнен от trg_Tickets_RecalculateOrderTotal
SELECT * FROM dbo.Orders  WHERE OrderId = @OrderId;
SELECT * FROM dbo.Tickets WHERE OrderId = @OrderId;

/* ---------- Негативни тестове ---------- */

-- 1) Същите места втори път -> 50004 от процедурата
BEGIN TRY
    EXEC dbo.sp_PurchaseTickets @CustomerId = 2, @EventId = @EventId, @SeatIds = @Seats;
END TRY
BEGIN CATCH
    SELECT N'Двойна продажба през процедурата' AS Test, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- 2) Директен INSERT на заето място -> филтрираният уникален индекс (грешка 2601)
BEGIN TRY
    INSERT INTO dbo.Tickets (OrderId, EventId, SeatId, Price, TicketCode)
    SELECT TOP (1) OrderId, EventId, SeatId, Price, N'TEST-DUPLICATE'
    FROM dbo.Tickets WHERE OrderId = @OrderId;
END TRY
BEGIN CATCH
    SELECT N'Двойна продажба директно в таблицата' AS Test, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- 3) Място от друга зала -> trg_Tickets_ValidateSale (50010)
BEGIN TRY
    INSERT INTO dbo.Tickets (OrderId, EventId, SeatId, Price, TicketCode)
    SELECT TOP (1) @OrderId, @EventId, s.SeatId, 10, N'TEST-WRONG-VENUE'
    FROM dbo.Seats s
    JOIN dbo.Sections sec ON sec.SectionId = s.SectionId
    JOIN dbo.Venues v     ON v.VenueId = sec.VenueId
    WHERE v.Name = N'Античен театър';
END TRY
BEGIN CATCH
    SELECT N'Място от друга зала' AS Test, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- 4) Покупка преди началото на продажбата -> trg_Tickets_ValidateSale (50012)
DECLARE @FutureEvent INT = (SELECT EventId FROM dbo.Events WHERE Title = N'Б.Т.Р. – Зимно турне 2027');
DECLARE @FutureSeats dbo.SeatIdList;
INSERT INTO @FutureSeats (SeatId) SELECT TOP (1) SeatId FROM dbo.fn_GetAvailableSeats(@FutureEvent);

BEGIN TRY
    EXEC dbo.sp_PurchaseTickets @CustomerId = 3, @EventId = @FutureEvent, @SeatIds = @FutureSeats,
                                @OrderDate = '2026-11-01';
END TRY
BEGIN CATCH
    SELECT N'Продажба преди старта' AS Test, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

/* ---------- sp_RefundTicket + trg_Refunds_ProcessRefund ---------- */

DECLARE @RefundTicket INT = (SELECT MIN(TicketId) FROM dbo.Tickets WHERE OrderId = @OrderId);
EXEC dbo.sp_RefundTicket @TicketId = @RefundTicket, @Reason = N'Демонстрация';

-- Билетът е Refunded, поръчката е PartiallyRefunded, мястото е отново свободно
SELECT TicketId, Status FROM dbo.Tickets WHERE OrderId = @OrderId;
SELECT OrderId, TotalAmount, Status FROM dbo.Orders WHERE OrderId = @OrderId;
SELECT * FROM dbo.fn_GetAvailableSeats(@EventId)
WHERE SeatId = (SELECT SeatId FROM dbo.Tickets WHERE TicketId = @RefundTicket);

-- Повторно възстановяване -> 50020
BEGIN TRY
    EXEC dbo.sp_RefundTicket @TicketId = @RefundTicket;
END TRY
BEGIN CATCH
    SELECT N'Двойно възстановяване' AS Test, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

/* ---------- sp_CheckInTicket ---------- */

DECLARE @Code NVARCHAR(32), @Start DATETIME2(0);
SELECT TOP (1) @Code = t.TicketCode, @Start = e.StartDateTime
FROM dbo.Tickets t JOIN dbo.Events e ON e.EventId = t.EventId
WHERE t.OrderId = @OrderId AND t.Status = N'Valid';

-- Твърде рано -> 50054
BEGIN TRY
    EXEC dbo.sp_CheckInTicket @TicketCode = @Code, @CheckedInAt = '2026-12-01 10:00';
END TRY
BEGIN CATCH
    SELECT N'Вход в грешен ден' AS Test, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- Половин час преди началото -> успешно
DECLARE @CheckIn DATETIME2(0) = DATEADD(MINUTE, -30, @Start);
EXEC dbo.sp_CheckInTicket @TicketCode = @Code, @CheckedInAt = @CheckIn;
SELECT TicketCode, Status, CheckedInAt FROM dbo.Tickets WHERE TicketCode = @Code;
GO

/* ---------- Изглед ---------- */

SELECT * FROM dbo.vw_EventSalesSummary ORDER BY NetRevenue DESC;
GO