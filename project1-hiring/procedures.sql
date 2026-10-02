/* 
   ПРОЄКТ №1 — HiringDb: збережувані процедури (6 шт.)

   #  Процедура                      Роль
   -- ------------------------------ -------------------------------------------
   1  usp_Candidate_Upsert           CREATE/UPDATE, транзакція на агрегат 1:1
   2  usp_Application_Create         CREATE, транзакція + знімок полів Каталогу
   3  usp_Application_ChangeStatus   БІЗНЕС-ОПЕРАЦІЯ: статусна машина (ключова)
   4  usp_Offer_Create               БІЗНЕС-ОПЕРАЦІЯ: офер + перехід статусу
   5  usp_Application_GetById        READ, 3 набори результатів (Dapper QueryMultiple)
   6  usp_Application_Search         READ, фільтри + пагінація OFFSET/FETCH

   Коди помилок:
     50001 заявку не знайдено              50011 вакансії немає в локальній копії
     50002 недопустимий перехід статусу    50012 вакансію закрито
     50003 найм без прийнятого офера       50013 повторна заявка
     50004 офер не на тому етапі           50014 кандидата не знайдено
     50005 офер уже існує
    */

USE HiringDb;
GO

/* 
   1. usp_Candidate_Upsert
      Створює або оновлює кандидата РАЗОМ із профілем (зв'язок 1:1) в одній
      транзакції: не може статися, щоб кандидат з'явився без профілю.
    */
CREATE OR ALTER PROCEDURE dbo.usp_Candidate_Upsert
    @Email           NVARCHAR(256),
    @FullName        NVARCHAR(200),
    @Phone           NVARCHAR(30)  = NULL,
    @Source          NVARCHAR(30)  = N'Website',
    @Headline        NVARCHAR(200) = NULL,
    @LinkedInUrl     NVARCHAR(300) = NULL,
    @ExpectedSalary  DECIMAL(18,2) = NULL,
    @Currency        CHAR(3)       = 'USD',
    @ReadyToRelocate BIT           = 0,
    @ActorLogin      NVARCHAR(100) = N'system',
    @CandidateId     BIGINT        = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    
    SET @CandidateId = NULL;

    BEGIN TRANSACTION;

        -- UPDLOCK+HOLDLOCK: не дає двом паралельним викликам створити
        -- двох кандидатів з однаковим email між перевіркою та вставкою.
        SELECT @CandidateId = Id
        FROM   dbo.Candidates WITH (UPDLOCK, HOLDLOCK)
        WHERE  Email = @Email AND IsDeleted = 0;

        IF @CandidateId IS NULL
        BEGIN
            INSERT dbo.Candidates (Email, FullName, Phone, Source, CreatedBy)
            VALUES (@Email, @FullName, @Phone, @Source, @ActorLogin);

            SET @CandidateId = CAST(SCOPE_IDENTITY() AS BIGINT);

            INSERT dbo.CandidateProfiles
                   (CandidateId, Headline, LinkedInUrl, ExpectedSalary, Currency, ReadyToRelocate, CreatedBy)
            VALUES (@CandidateId, @Headline, @LinkedInUrl, @ExpectedSalary, @Currency, @ReadyToRelocate, @ActorLogin);
        END
        ELSE
        BEGIN
            UPDATE dbo.Candidates
            SET    FullName  = @FullName,
                   Phone     = @Phone,
                   Source    = @Source,
                   UpdatedAt = SYSUTCDATETIME(),
                   UpdatedBy = @ActorLogin
            WHERE  Id = @CandidateId;

            UPDATE dbo.CandidateProfiles
            SET    Headline        = @Headline,
                   LinkedInUrl     = @LinkedInUrl,
                   ExpectedSalary  = @ExpectedSalary,
                   Currency        = @Currency,
                   ReadyToRelocate = @ReadyToRelocate,
                   UpdatedAt       = SYSUTCDATETIME(),
                   UpdatedBy       = @ActorLogin
            WHERE  CandidateId = @CandidateId;
        END

    COMMIT TRANSACTION;

    SELECT c.Id, c.Email, c.FullName, c.Phone, c.Source,
           p.Headline, p.ExpectedSalary, p.Currency, p.ReadyToRelocate
    FROM   dbo.Candidates c
    JOIN   dbo.CandidateProfiles p ON p.CandidateId = c.Id
    WHERE  c.Id = @CandidateId;
END
GO

/* 
   2. usp_Application_Create
      Створює заявку і ПЕРШИЙ запис історії однією транзакцією.
      Тут же робиться ЗНІМОК назви вакансії та компанії з локальної копії
      довідника — далі ці поля ніколи не оновлюються.
    */
CREATE OR ALTER PROCEDURE dbo.usp_Application_Create
    @CandidateId   BIGINT,
    @VacancyId     BIGINT,
    @ActorLogin    NVARCHAR(100) = N'system',
    @ApplicationId BIGINT        = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @ApplicationId = NULL; 

    BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.Candidates WHERE Id = @CandidateId AND IsDeleted = 0)
            THROW 50014, N'Candidate not found', 1;

        DECLARE @Title   NVARCHAR(200),
                @Company NVARCHAR(200),
                @IsOpen  BIT;

        SELECT @Title   = Title,
               @Company = CompanyName,
               @IsOpen  = IsOpen
        FROM   dbo.Vacancies WITH (UPDLOCK)
        WHERE  Id = @VacancyId AND IsDeleted = 0;

        IF @Title IS NULL
            THROW 50011, N'Vacancy is missing in the local catalog replica', 1;

        IF @IsOpen = 0
            THROW 50012, N'Vacancy is closed for new applications', 1;

        IF EXISTS (SELECT 1 FROM dbo.Applications
                   WHERE CandidateId = @CandidateId AND VacancyId = @VacancyId AND IsDeleted = 0)
            THROW 50013, N'Candidate has already applied for this vacancy', 1;

        INSERT dbo.Applications (CandidateId, VacancyId, VacancyTitle, CompanyName, Status, CreatedBy)
        VALUES (@CandidateId, @VacancyId, @Title, @Company, N'Applied', @ActorLogin);

        SET @ApplicationId = CAST(SCOPE_IDENTITY() AS BIGINT);

        INSERT dbo.ApplicationStageHistory (ApplicationId, FromStatus, ToStatus, ChangedBy, Note)
        VALUES (@ApplicationId, NULL, N'Applied', @ActorLogin, N'Заявку подано');

    COMMIT TRANSACTION;

    SELECT @ApplicationId AS ApplicationId, @Title AS VacancyTitle, N'Applied' AS Status;
END
GO

/* 
   3. usp_Application_ChangeStatus   <<< НАЙВАЖЛИВІША ПРОЦЕДУРА РОБОТИ >>>

      Працює в ЯВНІЙ транзакції та ВІДМОВЛЯЄ керованою помилкою, якщо перехід
      недопустимий. Аналог правила «не можна відвантажити неоплачене
      замовлення» тут: НЕ МОЖНА НАЙНЯТИ КАНДИДАТА БЕЗ ПРИЙНЯТОГО ОФЕРА.
    */
CREATE OR ALTER PROCEDURE dbo.usp_Application_ChangeStatus
    @ApplicationId BIGINT,
    @NewStatus     NVARCHAR(20),
    @ActorLogin    NVARCHAR(100) = N'system',
    @Note          NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;        

    BEGIN TRANSACTION;

        DECLARE @Current NVARCHAR(20);

        -- UPDLOCK утримує рядок до кінця транзакції: другий рекрутер,
        -- який у цю ж мить міняє статус, зачекає і побачить уже новий стан.
        SELECT @Current = Status
        FROM   dbo.Applications WITH (UPDLOCK, ROWLOCK)
        WHERE  Id = @ApplicationId AND IsDeleted = 0;

        IF @Current IS NULL
            THROW 50001, N'Application not found', 1;

        -- Перевірка переходу за таблицею-довідником, а не за набором IF-ів
        IF NOT EXISTS (SELECT 1
                       FROM   dbo.ApplicationStatusTransitions
                       WHERE  FromStatus = @Current AND ToStatus = @NewStatus)
        BEGIN
            DECLARE @msg NVARCHAR(400) =
                CONCAT(N'Transition "', @Current, N'" -> "', @NewStatus, N'" is not allowed');
            THROW 50002, @msg, 1;
        END

        -- Додаткове бізнес-правило поверх статусної машини
        IF @NewStatus = N'Hired'
           AND NOT EXISTS (SELECT 1 FROM dbo.Offers
                           WHERE ApplicationId = @ApplicationId AND Status = N'Accepted')
            THROW 50003, N'Cannot hire: there is no accepted offer for this application', 1;

        UPDATE dbo.Applications
        SET    Status    = @NewStatus,
               ClosedAt  = CASE WHEN @NewStatus IN (N'Hired', N'Rejected', N'Withdrawn')
                                THEN SYSUTCDATETIME() ELSE ClosedAt END,
               UpdatedAt = SYSUTCDATETIME(),
               UpdatedBy = @ActorLogin
        WHERE  Id = @ApplicationId;

        INSERT dbo.ApplicationStageHistory (ApplicationId, FromStatus, ToStatus, ChangedBy, Note)
        VALUES (@ApplicationId, @Current, @NewStatus, @ActorLogin, @Note);

    COMMIT TRANSACTION;

    SELECT @ApplicationId AS ApplicationId,
           @Current       AS PreviousStatus,
           @NewStatus     AS CurrentStatus;
END
GO

/* 
   4. usp_Offer_Create
      Створює офер (1:1 до заявки) і тією ж транзакцією переводить заявку
      в статус 'Offer'. Офер можливий лише з етапу 'Interview'.
    */
CREATE OR ALTER PROCEDURE dbo.usp_Offer_Create
    @ApplicationId BIGINT,
    @Salary        DECIMAL(18,2),
    @StartDate     DATE,
    @Currency      CHAR(3)       = 'USD',
    @ActorLogin    NVARCHAR(100) = N'system'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

        DECLARE @Current NVARCHAR(20);

        SELECT @Current = Status
        FROM   dbo.Applications WITH (UPDLOCK, ROWLOCK)
        WHERE  Id = @ApplicationId AND IsDeleted = 0;

        IF @Current IS NULL
            THROW 50001, N'Application not found', 1;

        IF @Current <> N'Interview'
            THROW 50004, N'Offer can be created only for an application at the Interview stage', 1;

        IF EXISTS (SELECT 1 FROM dbo.Offers WHERE ApplicationId = @ApplicationId)
            THROW 50005, N'Offer already exists for this application', 1;

        INSERT dbo.Offers (ApplicationId, Salary, Currency, StartDate, Status, SentAt, CreatedBy)
        VALUES (@ApplicationId, @Salary, @Currency, @StartDate, N'Sent', SYSUTCDATETIME(), @ActorLogin);

        UPDATE dbo.Applications
        SET    Status = N'Offer', UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @ActorLogin
        WHERE  Id = @ApplicationId;

        INSERT dbo.ApplicationStageHistory (ApplicationId, FromStatus, ToStatus, ChangedBy, Note)
        VALUES (@ApplicationId, @Current, N'Offer', @ActorLogin, N'Офер сформовано й надіслано');

    COMMIT TRANSACTION;

    SELECT @ApplicationId AS ApplicationId, @Salary AS Salary, @Currency AS Currency, N'Sent' AS OfferStatus;
END
GO

/* 
   5. usp_Application_GetById
      Три набори результатів поспіль — під Dapper QueryMultiple у Лаб. 02:
      шапка заявки / історія етапів / офер.
    */
CREATE OR ALTER PROCEDURE dbo.usp_Application_GetById
    @ApplicationId BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Applications WHERE Id = @ApplicationId AND IsDeleted = 0)
        THROW 50001, N'Application not found', 1;

    -- (1) шапка
    SELECT * FROM dbo.vw_ApplicationBoard WHERE ApplicationId = @ApplicationId;

    -- (2) історія етапів
    SELECT Id, FromStatus, ToStatus, ChangedAt, ChangedBy, Note
    FROM   dbo.ApplicationStageHistory
    WHERE  ApplicationId = @ApplicationId
    ORDER  BY ChangedAt, Id;

    -- (3) офер (0 або 1 рядок)
    SELECT ApplicationId, Salary, Currency, StartDate, Status, SentAt, RespondedAt
    FROM   dbo.Offers
    WHERE  ApplicationId = @ApplicationId;
END
GO

/* 
   6. usp_Application_Search
      Пошук із необов'язковими фільтрами та пагінацією.
      COUNT(*) OVER() повертає загальну кількість без другого запиту.
    */
CREATE OR ALTER PROCEDURE dbo.usp_Application_Search
    @VacancyId BIGINT        = NULL,
    @Status    NVARCHAR(20)  = NULL,
    @Search    NVARCHAR(100) = NULL,  
    @Page      INT           = 1,
    @PageSize  INT           = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @Page     < 1 SET @Page = 1;
    IF @PageSize < 1 OR @PageSize > 200 SET @PageSize = 20;

    SELECT  b.ApplicationId,
            b.CandidateId,
            b.CandidateName,
            b.CandidateEmail,
            b.VacancyId,
            b.VacancyTitle,
            b.CompanyName,
            b.Status,
            b.Score,
            b.AppliedAt,
            b.OfferSalary,
            b.OfferStatus,
            COUNT(*) OVER() AS TotalCount
    FROM    dbo.vw_ApplicationBoard b
    WHERE   (@VacancyId IS NULL OR b.VacancyId = @VacancyId)
      AND   (@Status    IS NULL OR b.Status    = @Status)
      AND   (@Search    IS NULL OR b.CandidateName  LIKE N'%' + @Search + N'%'
                                OR b.CandidateEmail LIKE N'%' + @Search + N'%')
    ORDER   BY b.AppliedAt DESC, b.ApplicationId DESC
    OFFSET  (@Page - 1) * @PageSize ROWS
    FETCH   NEXT @PageSize ROWS ONLY
    OPTION  (RECOMPILE); 
END
GO

PRINT N'HiringDb: 6 збережуваних процедур створено.';
GO


