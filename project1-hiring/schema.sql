/* ПРОЄКТ №1 — HiringDb  (SQL Server + ADO.NET & Dapper)
   Контекст (Bounded Context): Hiring — процес розгляду заявок кандидатів.
   Власник даних: Candidate, Application, ApplicationStageHistory, Offer.
   Чужі дані: Vacancy (власник — VacancyCatalogDb) зберігається як ЛОКАЛЬНА
              КОПІЯ ДОВІДНИКА, без жодного FOREIGN KEY на іншу базу.

   Скрипт ідемпотентний: повторний запуск нічого не ламає і не дублює. */

IF DB_ID(N'HiringDb') IS NULL
    CREATE DATABASE HiringDb;
GO

USE HiringDb;
GO

# 1. Candidates — кандидат. Коренева сутність агрегату «Кандидат».
IF OBJECT_ID(N'dbo.Candidates', N'U') IS NULL
CREATE TABLE dbo.Candidates
(
    Id          BIGINT IDENTITY(1,1)
                CONSTRAINT PK_Candidates PRIMARY KEY,
    Email       NVARCHAR(256) NOT NULL
                CONSTRAINT CK_Candidates_Email CHECK (Email LIKE N'%_@_%.__%'),
    FullName    NVARCHAR(200) NOT NULL,
    Phone       NVARCHAR(30)  NULL,
    Source      NVARCHAR(30)  NOT NULL
                CONSTRAINT DF_Candidates_Source DEFAULT N'Website'
                CONSTRAINT CK_Candidates_Source CHECK
                    (Source IN (N'Website', N'Referral', N'LinkedIn', N'JobBoard', N'Event')),
    /* --- службові (аудитні) колонки --- */
    CreatedAt   DATETIME2(3)  NOT NULL CONSTRAINT DF_Candidates_CreatedAt DEFAULT SYSUTCDATETIME(),
    CreatedBy   NVARCHAR(100) NULL,
    UpdatedAt   DATETIME2(3)  NULL,
    UpdatedBy   NVARCHAR(100) NULL,
    IsDeleted   BIT           NOT NULL CONSTRAINT DF_Candidates_IsDeleted DEFAULT 0, 
    [RowVersion] ROWVERSION                                                         
);
GO

/* 
   2. CandidateProfiles — зв'язок 1:1 з Candidates.
      Первинний ключ залежної таблиці ВОДНОЧАС є зовнішнім ключем — це і є 1:1.
      ON DELETE CASCADE доречний: профіль не існує без кандидата.
    */
IF OBJECT_ID(N'dbo.CandidateProfiles', N'U') IS NULL
CREATE TABLE dbo.CandidateProfiles
(
    CandidateId      BIGINT NOT NULL
                     CONSTRAINT PK_CandidateProfiles PRIMARY KEY
                     CONSTRAINT FK_CandidateProfiles_Candidates
                         FOREIGN KEY REFERENCES dbo.Candidates(Id) ON DELETE CASCADE,
    Headline         NVARCHAR(200) NULL,
    LinkedInUrl      NVARCHAR(300) NULL,
    ExpectedSalary   DECIMAL(18,2) NULL
                     CONSTRAINT CK_CandidateProfiles_Salary CHECK (ExpectedSalary IS NULL OR ExpectedSalary > 0),
    Currency         CHAR(3) NOT NULL
                     CONSTRAINT DF_CandidateProfiles_Currency DEFAULT 'USD'
                     CONSTRAINT CK_CandidateProfiles_Currency CHECK (Currency IN ('USD', 'EUR', 'UAH')),
    ReadyToRelocate  BIT NOT NULL CONSTRAINT DF_CandidateProfiles_Relocate DEFAULT 0,
    NoticePeriodDays INT NOT NULL
                     CONSTRAINT DF_CandidateProfiles_Notice DEFAULT 14
                     CONSTRAINT CK_CandidateProfiles_Notice CHECK (NoticePeriodDays BETWEEN 0 AND 180),
    CreatedAt        DATETIME2(3)  NOT NULL CONSTRAINT DF_CandidateProfiles_CreatedAt DEFAULT SYSUTCDATETIME(),
    CreatedBy        NVARCHAR(100) NULL,
    UpdatedAt        DATETIME2(3)  NULL,
    UpdatedBy        NVARCHAR(100) NULL,
    [RowVersion]     ROWVERSION
);
GO

/* 
   3. Vacancies — ЛОКАЛЬНА КОПІЯ ДОВІДНИКА з VacancyCatalogDb.
      * Id БЕЗ IDENTITY: ідентифікатор приходить ззовні, з бази Каталогу.
      * Жодного FOREIGN KEY на іншу базу — лише логічне посилання за Id.
      * Оновлюється подіями VacancyPublished / VacancyUpdated / VacancyClosed
        (механізм — Лаб. 08). До того часу наповнюється seed-скриптом.
    */
IF OBJECT_ID(N'dbo.Vacancies', N'U') IS NULL
CREATE TABLE dbo.Vacancies
(
    Id             BIGINT NOT NULL
                   CONSTRAINT PK_Vacancies PRIMARY KEY,   -- той самий Id, що й у VacancyCatalogDb.dbo.Vacancies
    Title          NVARCHAR(200) NOT NULL,
    CompanyName    NVARCHAR(200) NOT NULL,
    DepartmentName NVARCHAR(100) NULL,
    IsOpen         BIT NOT NULL CONSTRAINT DF_Vacancies_IsOpen DEFAULT 1,
    SyncedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_Vacancies_SyncedAt DEFAULT SYSUTCDATETIME(),
    IsDeleted      BIT NOT NULL CONSTRAINT DF_Vacancies_IsDeleted DEFAULT 0,
    [RowVersion]   ROWVERSION
);
GO

/* 
   4. ApplicationStatusTransitions — таблиця ДОПУСТИМИХ ПЕРЕХОДІВ статусів.
      Статусна машина винесена в дані, а не зашита в IF-и процедури:
      щоб додати новий перехід, достатньо вставити рядок.
    */
IF OBJECT_ID(N'dbo.ApplicationStatusTransitions', N'U') IS NULL
CREATE TABLE dbo.ApplicationStatusTransitions
(
    FromStatus NVARCHAR(20) NOT NULL,
    ToStatus   NVARCHAR(20) NOT NULL,
    CONSTRAINT PK_ApplicationStatusTransitions PRIMARY KEY (FromStatus, ToStatus),
    CONSTRAINT CK_ApplicationStatusTransitions_NotSelf CHECK (FromStatus <> ToStatus)
);
GO

/* 
   5. Applications — зв'язок M:N між Candidates і Vacancies.
      Проміжна таблиця з двома зовнішніми ключами ТА ВЛАСНИМИ ПОЛЯМИ
      (Status, Score, AppliedAt, знімки назви вакансії й компанії).

      ДУБЛЮВАННЯ ДАНИХ, випадок (1) — ЗНІМОК:
        VacancyTitle, CompanyName фіксуються на момент подання заявки
        і НІКОЛИ не оновлюються. Якщо через рік вакансію перейменують,
        історія найму має показувати назву, на яку людина реально подавалась.
        (Той самий підхід, що й OrderItem.ProductName/UnitPrice у Microsoft eShop.)
    */
IF OBJECT_ID(N'dbo.Applications', N'U') IS NULL
CREATE TABLE dbo.Applications
(
    Id           BIGINT IDENTITY(1,1)
                 CONSTRAINT PK_Applications PRIMARY KEY,
    CandidateId  BIGINT NOT NULL
                 CONSTRAINT FK_Applications_Candidates
                     FOREIGN KEY REFERENCES dbo.Candidates(Id),   
    VacancyId    BIGINT NOT NULL
                 CONSTRAINT FK_Applications_Vacancies
                     FOREIGN KEY REFERENCES dbo.Vacancies(Id),   
    VacancyTitle NVARCHAR(200) NOT NULL,                         
    CompanyName  NVARCHAR(200) NOT NULL,                       
    Status       NVARCHAR(20) NOT NULL
                 CONSTRAINT DF_Applications_Status DEFAULT N'Applied'
                 CONSTRAINT CK_Applications_Status CHECK
                     (Status IN (N'Applied', N'Screening', N'Interview', N'Offer',
                                 N'Hired', N'Rejected', N'Withdrawn')),
    Score        TINYINT NULL
                 CONSTRAINT CK_Applications_Score CHECK (Score IS NULL OR Score BETWEEN 1 AND 10),
    AppliedAt    DATETIME2(3) NOT NULL CONSTRAINT DF_Applications_AppliedAt DEFAULT SYSUTCDATETIME(),
    ClosedAt     DATETIME2(3) NULL,
    CreatedAt    DATETIME2(3)  NOT NULL CONSTRAINT DF_Applications_CreatedAt DEFAULT SYSUTCDATETIME(),
    CreatedBy    NVARCHAR(100) NULL,
    UpdatedAt    DATETIME2(3)  NULL,
    UpdatedBy    NVARCHAR(100) NULL,
    IsDeleted    BIT NOT NULL CONSTRAINT DF_Applications_IsDeleted DEFAULT 0,
    [RowVersion] ROWVERSION,
    CONSTRAINT CK_Applications_ClosedAt CHECK (ClosedAt IS NULL OR ClosedAt >= AppliedAt)
);
GO

/* 
   6. ApplicationStageHistory — зв'язок 1:N (Applications -> History).
      Зовнішній ключ розміщено на боці «багатьох».
      ON DELETE CASCADE: історія не має сенсу без заявки.
    */
IF OBJECT_ID(N'dbo.ApplicationStageHistory', N'U') IS NULL
CREATE TABLE dbo.ApplicationStageHistory
(
    Id            BIGINT IDENTITY(1,1)
                  CONSTRAINT PK_ApplicationStageHistory PRIMARY KEY,
    ApplicationId BIGINT NOT NULL
                  CONSTRAINT FK_StageHistory_Applications
                      FOREIGN KEY REFERENCES dbo.Applications(Id) ON DELETE CASCADE,
    FromStatus    NVARCHAR(20) NULL,          -- NULL для першого запису (створення заявки)
    ToStatus      NVARCHAR(20) NOT NULL,
    ChangedAt     DATETIME2(3) NOT NULL CONSTRAINT DF_StageHistory_ChangedAt DEFAULT SYSUTCDATETIME(),
    ChangedBy     NVARCHAR(100) NULL,
    Note          NVARCHAR(500) NULL
);
GO

/* 
   7. Offers — ще один зв'язок 1:1 (Applications <-> Offers).
      PK = FK, тому на одну заявку може існувати максимум один офер.
    */
IF OBJECT_ID(N'dbo.Offers', N'U') IS NULL
CREATE TABLE dbo.Offers
(
    ApplicationId BIGINT NOT NULL
                  CONSTRAINT PK_Offers PRIMARY KEY
                  CONSTRAINT FK_Offers_Applications
                      FOREIGN KEY REFERENCES dbo.Applications(Id) ON DELETE CASCADE,
    Salary        DECIMAL(18,2) NOT NULL
                  CONSTRAINT CK_Offers_Salary CHECK (Salary > 0),
    Currency      CHAR(3) NOT NULL
                  CONSTRAINT DF_Offers_Currency DEFAULT 'USD'
                  CONSTRAINT CK_Offers_Currency CHECK (Currency IN ('USD', 'EUR', 'UAH')),
    StartDate     DATE NOT NULL,
    Status        NVARCHAR(20) NOT NULL
                  CONSTRAINT DF_Offers_Status DEFAULT N'Draft'
                  CONSTRAINT CK_Offers_Status CHECK
                      (Status IN (N'Draft', N'Sent', N'Accepted', N'Declined', N'Expired')),
    SentAt        DATETIME2(3) NULL,
    RespondedAt   DATETIME2(3) NULL,
    CreatedAt     DATETIME2(3)  NOT NULL CONSTRAINT DF_Offers_CreatedAt DEFAULT SYSUTCDATETIME(),
    CreatedBy     NVARCHAR(100) NULL,
    UpdatedAt     DATETIME2(3)  NULL,
    UpdatedBy     NVARCHAR(100) NULL,
    [RowVersion]  ROWVERSION
);
GO

/* 
   ІНДЕКСИ. Для кожного вказано, ПІД ЯКИЙ ЗАПИТ він створений.
    */

-- Запит: «перевірити/знайти кандидата за email» + бізнес-правило «один email = один кандидат».
-- Фільтрований UNIQUE: м'яко видалений кандидат не блокує повторну реєстрацію.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Candidates_Email' AND object_id = OBJECT_ID(N'dbo.Candidates'))
    CREATE UNIQUE INDEX UX_Candidates_Email
        ON dbo.Candidates (Email)
        WHERE IsDeleted = 0;
GO

-- Запит: «воронка найму по вакансії» — SELECT ... WHERE VacancyId = @v AND Status = @s.
-- INCLUDE робить індекс покриваючим для списку заявок на дошці рекрутера.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Applications_VacancyId_Status' AND object_id = OBJECT_ID(N'dbo.Applications'))
    CREATE INDEX IX_Applications_VacancyId_Status
        ON dbo.Applications (VacancyId, Status)
        INCLUDE (CandidateId, AppliedAt, Score)
        WHERE IsDeleted = 0;
GO

-- Запит: «усі заявки кандидата, найсвіжіші згори» — картка кандидата.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Applications_CandidateId_AppliedAt' AND object_id = OBJECT_ID(N'dbo.Applications'))
    CREATE INDEX IX_Applications_CandidateId_AppliedAt
        ON dbo.Applications (CandidateId, AppliedAt DESC)
        INCLUDE (VacancyId, Status)
        WHERE IsDeleted = 0;
GO

-- Правило цілісності: кандидат не може двічі податися на ту саму вакансію.
-- Реалізовано індексом, бо звичайний UNIQUE конфліктував би з soft delete.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Applications_Candidate_Vacancy' AND object_id = OBJECT_ID(N'dbo.Applications'))
    CREATE UNIQUE INDEX UX_Applications_Candidate_Vacancy
        ON dbo.Applications (CandidateId, VacancyId)
        WHERE IsDeleted = 0;
GO

-- Запит: «таймлайн заявки» — SELECT ... WHERE ApplicationId = @id ORDER BY ChangedAt.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_StageHistory_ApplicationId_ChangedAt' AND object_id = OBJECT_ID(N'dbo.ApplicationStageHistory'))
    CREATE INDEX IX_StageHistory_ApplicationId_ChangedAt
        ON dbo.ApplicationStageHistory (ApplicationId, ChangedAt)
        INCLUDE (FromStatus, ToStatus, ChangedBy);
GO

-- Запит: «надіслані офери без відповіді» — щоденний нагадувач рекрутеру.
-- Фільтрований індекс: рядків зі статусом 'Sent' завжди небагато.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Offers_Sent' AND object_id = OBJECT_ID(N'dbo.Offers'))
    CREATE INDEX IX_Offers_Sent
        ON dbo.Offers (SentAt)
        INCLUDE (Salary, Currency, StartDate)
        WHERE Status = N'Sent';
GO

-- Запит: «список відкритих вакансій у локальній копії довідника».
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Vacancies_Open' AND object_id = OBJECT_ID(N'dbo.Vacancies'))
    CREATE INDEX IX_Vacancies_Open
        ON dbo.Vacancies (Title)
        WHERE IsOpen = 1 AND IsDeleted = 0;
GO

/* 
   ПРЕДСТАВЛЕННЯ для читання (денормалізоване): картка заявки «все в одному».
    */
CREATE OR ALTER VIEW dbo.vw_ApplicationBoard
AS
SELECT  a.Id              AS ApplicationId,
        a.Status,
        a.Score,
        a.AppliedAt,
        a.VacancyId,
        a.VacancyTitle,                   
        a.CompanyName,                   
        c.Id              AS CandidateId,
        c.FullName        AS CandidateName,
        c.Email           AS CandidateEmail,
        p.Headline,
        p.ExpectedSalary,
        o.Salary          AS OfferSalary,
        o.Status          AS OfferStatus
FROM    dbo.Applications      a
JOIN    dbo.Candidates        c ON c.Id = a.CandidateId
LEFT JOIN dbo.CandidateProfiles p ON p.CandidateId = c.Id
LEFT JOIN dbo.Offers          o ON o.ApplicationId = a.Id
WHERE   a.IsDeleted = 0 AND c.IsDeleted = 0;
GO

/* 
   БЕЗПЕКА: окремий логін застосунку з доступом ЛИШЕ до своєї бази
   (принцип найменших привілеїв). Саме його рядок підключення піде в Лаб. 02.
    */
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'hiring_app')
    CREATE LOGIN hiring_app WITH PASSWORD = N'Hiring_App!2024', CHECK_POLICY = ON;
GO

USE HiringDb;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'hiring_app')
BEGIN
    CREATE USER hiring_app FOR LOGIN hiring_app;
    ALTER ROLE db_datareader ADD MEMBER hiring_app;
    ALTER ROLE db_datawriter ADD MEMBER hiring_app;
    GRANT EXECUTE ON SCHEMA::dbo TO hiring_app; 
END
GO

PRINT N'HiringDb: схему створено.';
GO
