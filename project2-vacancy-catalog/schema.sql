/* 
   ПРОЄКТ №2 — VacancyCatalogDb  (SQL Server + EF Core Code First)
   Контекст (Bounded Context): Vacancy Catalog — довідник компаній, відділів,
   навичок і вакансій. Це ЄДИНИЙ ВЛАСНИК даних про вакансію.

   На цьому етапі схема проєктується скриптом; у Лаб. 03 ті самі таблиці
   буде описано сутностями C# + Fluent API і згенеровано міграціями EF Core.
   Відповідність «таблиця -> сутність EF» наведено в коментарях.

   Скрипт ідемпотентний. Порядок: schema.sql -> seed.sql
    */

IF DB_ID(N'VacancyCatalogDb') IS NULL
    CREATE DATABASE VacancyCatalogDb;
GO

USE VacancyCatalogDb;
GO

/* 
   1. Companies  (EF: Company)
      PK: BIGINT IDENTITY. Обґрунтування вибору типу ключа див. у README.
    */
IF OBJECT_ID(N'dbo.Companies', N'U') IS NULL
CREATE TABLE dbo.Companies
(
    Id          BIGINT IDENTITY(1,1) CONSTRAINT PK_Companies PRIMARY KEY,
    Name        NVARCHAR(200) NOT NULL,
    Slug        NVARCHAR(100) NOT NULL,             
    Industry    NVARCHAR(100) NOT NULL
                CONSTRAINT DF_Companies_Industry DEFAULT N'IT',
    WebsiteUrl  NVARCHAR(300) NULL,
    CreatedAt   DATETIME2(3)  NOT NULL CONSTRAINT DF_Companies_CreatedAt DEFAULT SYSUTCDATETIME(),
    CreatedBy   NVARCHAR(100) NULL,
    UpdatedAt   DATETIME2(3)  NULL,
    UpdatedBy   NVARCHAR(100) NULL,
    IsDeleted   BIT NOT NULL CONSTRAINT DF_Companies_IsDeleted DEFAULT 0,
    [RowVersion] ROWVERSION,                          -- EF Core: [Timestamp] / IsRowVersion()
    CONSTRAINT CK_Companies_Slug CHECK (Slug NOT LIKE N'% %')
);
GO

/* 
   2. CompanyProfiles  (EF: CompanyProfile)  — ЗВ'ЯЗОК 1:1
      PK залежної таблиці = FK на Companies. Саме це й робить зв'язок 1:1.
      EF Core: HasOne(c => c.Profile).WithOne(p => p.Company)
                 .HasForeignKey<CompanyProfile>(p => p.CompanyId);
    */
IF OBJECT_ID(N'dbo.CompanyProfiles', N'U') IS NULL
CREATE TABLE dbo.CompanyProfiles
(
    CompanyId     BIGINT NOT NULL
                  CONSTRAINT PK_CompanyProfiles PRIMARY KEY
                  CONSTRAINT FK_CompanyProfiles_Companies
                      FOREIGN KEY REFERENCES dbo.Companies(Id) ON DELETE CASCADE,
    About         NVARCHAR(2000) NULL,
    FoundedYear   SMALLINT NULL
                  CONSTRAINT CK_CompanyProfiles_Founded CHECK (FoundedYear IS NULL OR FoundedYear BETWEEN 1800 AND 2100),
    EmployeeCount INT NULL
                  CONSTRAINT CK_CompanyProfiles_Employees CHECK (EmployeeCount IS NULL OR EmployeeCount > 0),
    LogoUrl       NVARCHAR(300) NULL,
    CreatedAt     DATETIME2(3) NOT NULL CONSTRAINT DF_CompanyProfiles_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt     DATETIME2(3) NULL,
    [RowVersion]  ROWVERSION
);
GO

/* 
   3. Departments  (EF: Department)  — ЗВ'ЯЗОК 1:N (Company -> Departments)
      FK стоїть у таблиці на боці «багатьох».
    */
IF OBJECT_ID(N'dbo.Departments', N'U') IS NULL
CREATE TABLE dbo.Departments
(
    Id         BIGINT IDENTITY(1,1) CONSTRAINT PK_Departments PRIMARY KEY,
    CompanyId  BIGINT NOT NULL
               CONSTRAINT FK_Departments_Companies
                   FOREIGN KEY REFERENCES dbo.Companies(Id) ON DELETE CASCADE,
    Name       NVARCHAR(100) NOT NULL,
    CostCenter NVARCHAR(20) NULL,
    CreatedAt  DATETIME2(3) NOT NULL CONSTRAINT DF_Departments_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt  DATETIME2(3) NULL,
    IsDeleted  BIT NOT NULL CONSTRAINT DF_Departments_IsDeleted DEFAULT 0,
    [RowVersion] ROWVERSION
);
GO

/* 
   4. Skills  (EF: Skill) — довідник навичок.
    */
IF OBJECT_ID(N'dbo.Skills', N'U') IS NULL
CREATE TABLE dbo.Skills
(
    Id       BIGINT IDENTITY(1,1) CONSTRAINT PK_Skills PRIMARY KEY,
    Name     NVARCHAR(80) NOT NULL,
    Category NVARCHAR(40) NOT NULL
             CONSTRAINT DF_Skills_Category DEFAULT N'Technical'
             CONSTRAINT CK_Skills_Category CHECK
                 (Category IN (N'Technical', N'Tool', N'Language', N'Soft', N'Domain')),
    CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_Skills_CreatedAt DEFAULT SYSUTCDATETIME()
);
GO

/* 
   5. Vacancies  (EF: Vacancy) — ВЛАСНИК даних про вакансію.
      Два зв'язки 1:N: Company -> Vacancies та Department -> Vacancies.
      ON DELETE NO ACTION навмисно: видалення компанії не повинно тихо
      знести всі її вакансії, на які вже подалися кандидати
      (і це ж уникає помилки «multiple cascade paths»).
    */
IF OBJECT_ID(N'dbo.Vacancies', N'U') IS NULL
CREATE TABLE dbo.Vacancies
(
    Id             BIGINT IDENTITY(1,1) CONSTRAINT PK_Vacancies PRIMARY KEY,
    CompanyId      BIGINT NOT NULL
                   CONSTRAINT FK_Vacancies_Companies
                       FOREIGN KEY REFERENCES dbo.Companies(Id),
    DepartmentId   BIGINT NULL
                   CONSTRAINT FK_Vacancies_Departments
                       FOREIGN KEY REFERENCES dbo.Departments(Id),
    Title          NVARCHAR(200) NOT NULL,
    Slug           NVARCHAR(150) NOT NULL,
    Description    NVARCHAR(MAX) NULL,
    EmploymentType NVARCHAR(20) NOT NULL
                   CONSTRAINT DF_Vacancies_EmpType DEFAULT N'FullTime'
                   CONSTRAINT CK_Vacancies_EmpType CHECK
                       (EmploymentType IN (N'FullTime', N'PartTime', N'Contract', N'Internship')),
    WorkMode       NVARCHAR(20) NOT NULL
                   CONSTRAINT DF_Vacancies_WorkMode DEFAULT N'Hybrid'
                   CONSTRAINT CK_Vacancies_WorkMode CHECK
                       (WorkMode IN (N'Onsite', N'Hybrid', N'Remote')),
    SeniorityLevel NVARCHAR(20) NOT NULL
                   CONSTRAINT DF_Vacancies_Seniority DEFAULT N'Middle'
                   CONSTRAINT CK_Vacancies_Seniority CHECK
                       (SeniorityLevel IN (N'Intern', N'Junior', N'Middle', N'Senior', N'Lead')),
    City           NVARCHAR(100) NULL,
    SalaryMin      DECIMAL(18,2) NULL,
    SalaryMax      DECIMAL(18,2) NULL,
    Currency       CHAR(3) NOT NULL
                   CONSTRAINT DF_Vacancies_Currency DEFAULT 'USD'
                   CONSTRAINT CK_Vacancies_Currency CHECK (Currency IN ('USD', 'EUR', 'UAH')),
    IsOpen         BIT NOT NULL CONSTRAINT DF_Vacancies_IsOpen DEFAULT 1,
    PublishedAt    DATETIME2(3) NULL,
    CreatedAt      DATETIME2(3) NOT NULL CONSTRAINT DF_Vacancies_CreatedAt DEFAULT SYSUTCDATETIME(),
    CreatedBy      NVARCHAR(100) NULL,
    UpdatedAt      DATETIME2(3) NULL,
    UpdatedBy      NVARCHAR(100) NULL,
    IsDeleted      BIT NOT NULL CONSTRAINT DF_Vacancies_IsDeleted DEFAULT 0,
    [RowVersion]   ROWVERSION,
    -- перевірка позитивних значень зарплат і коректного діапазону
    CONSTRAINT CK_Vacancies_SalaryPositive CHECK
        ((SalaryMin IS NULL OR SalaryMin > 0) AND (SalaryMax IS NULL OR SalaryMax > 0)),
    CONSTRAINT CK_Vacancies_SalaryRange CHECK
        (SalaryMin IS NULL OR SalaryMax IS NULL OR SalaryMin <= SalaryMax)
);
GO

/* 
   6. VacancySkills  (EF: VacancySkill) — ЗВ'ЯЗОК M:N (Vacancies <-> Skills)
      ПРОМІЖНА СУТНІСТЬ З ВЛАСНИМИ ПОЛЯМИ (вимога умови):
      RequiredLevel, IsMandatory, AddedAt. Саме через власні поля цю таблицю
      в EF Core описують окремим класом, а не skip-навігацією.
    */
IF OBJECT_ID(N'dbo.VacancySkills', N'U') IS NULL
CREATE TABLE dbo.VacancySkills
(
    VacancyId     BIGINT NOT NULL
                  CONSTRAINT FK_VacancySkills_Vacancies
                      FOREIGN KEY REFERENCES dbo.Vacancies(Id) ON DELETE CASCADE,
    SkillId       BIGINT NOT NULL
                  CONSTRAINT FK_VacancySkills_Skills
                      FOREIGN KEY REFERENCES dbo.Skills(Id),
    RequiredLevel NVARCHAR(20) NOT NULL                         -- власне поле зв'язку
                  CONSTRAINT DF_VacancySkills_Level DEFAULT N'Intermediate'
                  CONSTRAINT CK_VacancySkills_Level CHECK
                      (RequiredLevel IN (N'Basic', N'Intermediate', N'Advanced', N'Expert')),
    IsMandatory   BIT NOT NULL                                   -- власне поле зв'язку
                  CONSTRAINT DF_VacancySkills_Mandatory DEFAULT 1,
    AddedAt       DATETIME2(3) NOT NULL                          -- власне поле зв'язку
                  CONSTRAINT DF_VacancySkills_AddedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_VacancySkills PRIMARY KEY (VacancyId, SkillId)
);
GO

/* 
   ІНДЕКСИ. Для кожного вказано, ПІД ЯКИЙ ЗАПИТ він створений.
    */

-- Запит: «відкрити сторінку компанії за slug» (/companies/softonix).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Companies_Slug' AND object_id = OBJECT_ID(N'dbo.Companies'))
    CREATE UNIQUE INDEX UX_Companies_Slug ON dbo.Companies (Slug) WHERE IsDeleted = 0;
GO

-- Запит: «відкрити сторінку вакансії за slug».
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Vacancies_Slug' AND object_id = OBJECT_ID(N'dbo.Vacancies'))
    CREATE UNIQUE INDEX UX_Vacancies_Slug ON dbo.Vacancies (Slug) WHERE IsDeleted = 0;
GO

-- Правило довідника: назва навички унікальна (щоб не з'явились "C#" і "c#").
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Skills_Name' AND object_id = OBJECT_ID(N'dbo.Skills'))
    CREATE UNIQUE INDEX UX_Skills_Name ON dbo.Skills (Name);
GO

-- Запит: головна сторінка — «стрічка відкритих вакансій, найновіші згори».
-- Фільтрований індекс: закриті та видалені вакансії в індекс не потрапляють.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Vacancies_Feed' AND object_id = OBJECT_ID(N'dbo.Vacancies'))
    CREATE INDEX IX_Vacancies_Feed
        ON dbo.Vacancies (PublishedAt DESC)
        INCLUDE (Title, CompanyId, City, WorkMode, SeniorityLevel, SalaryMin, SalaryMax, Currency)
        WHERE IsOpen = 1 AND IsDeleted = 0;
GO

-- Запит: «усі вакансії компанії, згруповані по відділах» (кабінет роботодавця).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Vacancies_Company_Department' AND object_id = OBJECT_ID(N'dbo.Vacancies'))
    CREATE INDEX IX_Vacancies_Company_Department
        ON dbo.Vacancies (CompanyId, DepartmentId)
        INCLUDE (Title, IsOpen)
        WHERE IsDeleted = 0;
GO

-- Запит: «фільтр вакансій за рівнем і форматом роботи» — найчастіший фасетний пошук.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Vacancies_Seniority_WorkMode' AND object_id = OBJECT_ID(N'dbo.Vacancies'))
    CREATE INDEX IX_Vacancies_Seniority_WorkMode
        ON dbo.Vacancies (SeniorityLevel, WorkMode, City)
        WHERE IsOpen = 1 AND IsDeleted = 0;
GO

-- Запит: ЗВОРОТНИЙ бік M:N — «які вакансії вимагають навичку X рівня Advanced».
-- Кластеризований PK (VacancyId, SkillId) цьому запиту не допомагає.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_VacancySkills_Skill_Level' AND object_id = OBJECT_ID(N'dbo.VacancySkills'))
    CREATE INDEX IX_VacancySkills_Skill_Level
        ON dbo.VacancySkills (SkillId, RequiredLevel)
        INCLUDE (VacancyId, IsMandatory);
GO

-- Запит: «відділи компанії» — список у формі створення вакансії.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Departments_CompanyId' AND object_id = OBJECT_ID(N'dbo.Departments'))
    CREATE INDEX IX_Departments_CompanyId ON dbo.Departments (CompanyId) WHERE IsDeleted = 0;
GO

/* 
   ПРЕДСТАВЛЕННЯ для читання: картка вакансії з назвами компанії та відділу.
   Саме ці поля сервіс Каталогу публікує в події VacancyPublished/Updated,
   і саме вони лягають у локальну копію довідника в HiringDb.
    */
CREATE OR ALTER VIEW dbo.vw_VacancyCard
AS
SELECT  v.Id            AS VacancyId,
        v.Title,
        v.Slug,
        c.Name          AS CompanyName,
        d.Name          AS DepartmentName,
        v.SeniorityLevel,
        v.EmploymentType,
        v.WorkMode,
        v.City,
        v.SalaryMin, v.SalaryMax, v.Currency,
        v.IsOpen,
        v.PublishedAt
FROM    dbo.Vacancies v
JOIN    dbo.Companies c ON c.Id = v.CompanyId
LEFT JOIN dbo.Departments d ON d.Id = v.DepartmentId
WHERE   v.IsDeleted = 0 AND c.IsDeleted = 0;
GO

 
-- БЕЗПЕКА: окремий логін лише для цієї бази.

USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'catalog_app')
    CREATE LOGIN catalog_app WITH PASSWORD = N'Catalog_App!2024', CHECK_POLICY = ON;
GO

USE VacancyCatalogDb;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'catalog_app')
BEGIN
    CREATE USER catalog_app FOR LOGIN catalog_app;
    ALTER ROLE db_datareader ADD MEMBER catalog_app;
    ALTER ROLE db_datawriter ADD MEMBER catalog_app;
END
GO

PRINT N'VacancyCatalogDb: схему створено.';
GO
