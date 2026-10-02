/* 
   ПРОЄКТ №2 — VacancyCatalogDb: довідникові (seed) дані.

   ІДЕМПОТЕНТНІСТЬ: усюди INSERT ... WHERE NOT EXISTS за явним Id.
   Явні Id через SET IDENTITY_INSERT потрібні тому, що ці самі Id
   використовує локальна копія довідника в HiringDb (логічне посилання
   між базами — тільки за ідентифікатором, без FOREIGN KEY).
    */

USE VacancyCatalogDb;
GO

/* --------------------------- 1. Компанії ---------------------------------- */
SET IDENTITY_INSERT dbo.Companies ON;

INSERT dbo.Companies (Id, Name, Slug, Industry, WebsiteUrl, CreatedBy)
SELECT src.Id, src.Name, src.Slug, src.Industry, src.WebsiteUrl, N'seed'
FROM (VALUES
        (1, N'Softonix',       N'softonix',       N'IT Outsourcing', N'https://softonix.example'),
        (2, N'MedTech UA',     N'medtech-ua',     N'HealthTech',     N'https://medtech.example'),
        (3, N'GreenCity Tech', N'greencity-tech', N'GreenTech',      N'https://greencity.example')
     ) AS src (Id, Name, Slug, Industry, WebsiteUrl)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Companies c WHERE c.Id = src.Id);

SET IDENTITY_INSERT dbo.Companies OFF;
GO

/* --------------------- 2. Профілі компаній (1:1) -------------------------- */
INSERT dbo.CompanyProfiles (CompanyId, About, FoundedYear, EmployeeCount, LogoUrl)
SELECT src.CompanyId, src.About, src.FoundedYear, src.EmployeeCount, src.LogoUrl
FROM (VALUES
        (1, N'Продуктова та аутсорс-розробка на .NET і React. Офіси у Львові та Варшаві.', 2014, 180, N'/logos/softonix.svg'),
        (2, N'Інформаційні системи для клінік: EHR, лабораторні модулі, телемедицина.',      2018,  95, N'/logos/medtech.svg'),
        (3, N'Платформи моніторингу енергоспоживання для муніципалітетів.',                  2021,  40, N'/logos/greencity.svg')
     ) AS src (CompanyId, About, FoundedYear, EmployeeCount, LogoUrl)
WHERE NOT EXISTS (SELECT 1 FROM dbo.CompanyProfiles p WHERE p.CompanyId = src.CompanyId);
GO

/* ------------------------- 3. Відділи (1:N) ------------------------------- */
SET IDENTITY_INSERT dbo.Departments ON;

INSERT dbo.Departments (Id, CompanyId, Name, CostCenter)
SELECT src.Id, src.CompanyId, src.Name, src.CostCenter
FROM (VALUES
        (1, 1, N'Backend',        N'SX-BE'),
        (2, 1, N'Quality',        N'SX-QA'),
        (3, 1, N'Design',         N'SX-DS'),
        (4, 2, N'Data Platform',  N'MT-DP'),
        (5, 2, N'Implementation', N'MT-IM'),
        (6, 3, N'Web',            N'GC-WB'),
        (7, 3, N'Platform',       N'GC-PL'),
        (8, 3, N'People',         N'GC-HR')
     ) AS src (Id, CompanyId, Name, CostCenter)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Departments d WHERE d.Id = src.Id);

SET IDENTITY_INSERT dbo.Departments OFF;
GO

/* ------------------------ 4. Довідник навичок ----------------------------- */
SET IDENTITY_INSERT dbo.Skills ON;

INSERT dbo.Skills (Id, Name, Category)
SELECT src.Id, src.Name, src.Category
FROM (VALUES
        ( 1, N'C#',               N'Technical'),
        ( 2, N'ASP.NET Core',     N'Technical'),
        ( 3, N'Entity Framework', N'Technical'),
        ( 4, N'Dapper',           N'Technical'),
        ( 5, N'SQL Server',       N'Technical'),
        ( 6, N'MongoDB',          N'Technical'),
        ( 7, N'React',            N'Technical'),
        ( 8, N'TypeScript',       N'Technical'),
        ( 9, N'Python',           N'Technical'),
        (10, N'Apache Spark',     N'Technical'),
        (11, N'Docker',           N'Tool'),
        (12, N'Kubernetes',       N'Tool'),
        (13, N'Azure DevOps',     N'Tool'),
        (14, N'Figma',            N'Tool'),
        (15, N'Playwright',       N'Tool'),
        (16, N'English B2+',      N'Language'),
        (17, N'Комунікація',      N'Soft'),
        (18, N'Менторство',       N'Soft'),
        (19, N'HL7 / FHIR',       N'Domain'),
        (20, N'GDPR',             N'Domain')
     ) AS src (Id, Name, Category)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Skills s WHERE s.Id = src.Id);

SET IDENTITY_INSERT dbo.Skills OFF;
GO

/* ----------------------------- 5. Вакансії -------------------------------
   Id 1..8 збігаються з dbo.Vacancies у HiringDb (локальна копія довідника).
   -------------------------------------------------------------------------- */
SET IDENTITY_INSERT dbo.Vacancies ON;

INSERT dbo.Vacancies (Id, CompanyId, DepartmentId, Title, Slug, Description,
                      EmploymentType, WorkMode, SeniorityLevel, City,
                      SalaryMin, SalaryMax, Currency, IsOpen, PublishedAt, CreatedBy)
SELECT src.Id, src.CompanyId, src.DepartmentId, src.Title, src.Slug, src.Description,
       src.EmploymentType, src.WorkMode, src.SeniorityLevel, src.City,
       src.SalaryMin, src.SalaryMax, src.Currency, src.IsOpen, src.PublishedAt, N'seed'
FROM (VALUES
        (1, 1, 1, N'Senior .NET Developer',      N'softonix-senior-dotnet-developer',
            N'Розробка мікросервісів на ASP.NET Core, робота з SQL Server і RabbitMQ.',
            N'FullTime', N'Hybrid',  N'Senior', N'Львів',  CAST(4500 AS DECIMAL(18,2)), CAST(6000 AS DECIMAL(18,2)), 'USD', CAST(1 AS BIT), CAST('2026-08-14T09:00:00' AS DATETIME2(3))),
        (2, 1, 2, N'Junior QA Engineer',         N'softonix-junior-qa-engineer',
            N'Ручне тестування вебзастосунків, поступовий перехід до автоматизації на Playwright.',
            N'FullTime', N'Onsite',  N'Junior', N'Львів',  CAST(700 AS DECIMAL(18,2)),  CAST(1200 AS DECIMAL(18,2)), 'USD', CAST(1 AS BIT), CAST('2026-09-01T10:30:00' AS DATETIME2(3))),
        (3, 1, 3, N'Product Designer',           N'softonix-product-designer',
            N'Дизайн-системи, прототипи у Figma, тісна робота з фронтендом.',
            N'FullTime', N'Remote',  N'Middle', NULL,      CAST(2200 AS DECIMAL(18,2)), CAST(3200 AS DECIMAL(18,2)), 'USD', CAST(1 AS BIT), CAST('2026-09-05T12:00:00' AS DATETIME2(3))),
        (4, 2, 4, N'Data Engineer',              N'medtech-data-engineer',
            N'ETL-конвеєри медичних даних, Spark, Airflow, вимоги GDPR.',
            N'FullTime', N'Remote',  N'Middle', NULL,      CAST(3500 AS DECIMAL(18,2)), CAST(5000 AS DECIMAL(18,2)), 'EUR', CAST(1 AS BIT), CAST('2026-07-22T08:15:00' AS DATETIME2(3))),
        (5, 2, 5, N'Clinical Systems Analyst',   N'medtech-clinical-systems-analyst',
            N'Впровадження EHR у клініках, збір вимог, стандарти HL7/FHIR.',
            N'Contract', N'Hybrid',  N'Middle', N'Київ',   CAST(2000 AS DECIMAL(18,2)), CAST(3000 AS DECIMAL(18,2)), 'EUR', CAST(1 AS BIT), CAST('2026-08-30T11:00:00' AS DATETIME2(3))),
        (6, 3, 6, N'Frontend Developer (React)', N'greencity-frontend-react',
            N'Дашборди енергоспоживання, React + TypeScript, робота з великими графіками.',
            N'FullTime', N'Hybrid',  N'Middle', N'Одеса',  CAST(2500 AS DECIMAL(18,2)), CAST(3800 AS DECIMAL(18,2)), 'USD', CAST(1 AS BIT), CAST('2026-09-10T09:45:00' AS DATETIME2(3))),
        (7, 3, 7, N'DevOps Engineer',            N'greencity-devops-engineer',
            N'Kubernetes, GitOps, моніторинг. Є можливість менторства.',
            N'FullTime', N'Remote',  N'Senior', NULL,      CAST(4000 AS DECIMAL(18,2)), CAST(5500 AS DECIMAL(18,2)), 'USD', CAST(1 AS BIT), CAST('2026-09-12T14:20:00' AS DATETIME2(3))),
        (8, 3, 8, N'HR Generalist',              N'greencity-hr-generalist',
            N'Підбір, адаптація, внутрішні комунікації. ВАКАНСІЮ ЗАКРИТО.',
            N'PartTime', N'Onsite',  N'Middle', N'Одеса',  CAST(1200 AS DECIMAL(18,2)), CAST(1800 AS DECIMAL(18,2)), 'USD', CAST(0 AS BIT), CAST('2026-06-01T10:00:00' AS DATETIME2(3)))
     ) AS src (Id, CompanyId, DepartmentId, Title, Slug, Description, EmploymentType,
               WorkMode, SeniorityLevel, City, SalaryMin, SalaryMax, Currency, IsOpen, PublishedAt)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Vacancies v WHERE v.Id = src.Id);

SET IDENTITY_INSERT dbo.Vacancies OFF;
GO

/* --------- 6. M:N «вакансія <-> навичка» з ВЛАСНИМИ полями зв'язку -------- */
INSERT dbo.VacancySkills (VacancyId, SkillId, RequiredLevel, IsMandatory)
SELECT src.VacancyId, src.SkillId, src.RequiredLevel, src.IsMandatory
FROM (VALUES
        -- 1. Senior .NET Developer
        (1,  1, N'Expert',       CAST(1 AS BIT)),
        (1,  2, N'Advanced',     CAST(1 AS BIT)),
        (1,  5, N'Advanced',     CAST(1 AS BIT)),
        (1,  4, N'Intermediate', CAST(0 AS BIT)),
        (1, 11, N'Intermediate', CAST(0 AS BIT)),
        (1, 16, N'Advanced',     CAST(1 AS BIT)),
        (1, 18, N'Intermediate', CAST(0 AS BIT)),
        -- 2. Junior QA Engineer
        (2, 15, N'Basic',        CAST(0 AS BIT)),
        (2, 16, N'Intermediate', CAST(1 AS BIT)),
        (2, 17, N'Intermediate', CAST(1 AS BIT)),
        -- 3. Product Designer
        (3, 14, N'Expert',       CAST(1 AS BIT)),
        (3, 17, N'Advanced',     CAST(1 AS BIT)),
        (3, 16, N'Intermediate', CAST(0 AS BIT)),
        -- 4. Data Engineer
        (4,  9, N'Advanced',     CAST(1 AS BIT)),
        (4, 10, N'Advanced',     CAST(1 AS BIT)),
        (4, 20, N'Intermediate', CAST(1 AS BIT)),
        (4, 11, N'Intermediate', CAST(0 AS BIT)),
        -- 5. Clinical Systems Analyst
        (5, 19, N'Advanced',     CAST(1 AS BIT)),
        (5, 20, N'Advanced',     CAST(1 AS BIT)),
        (5, 17, N'Advanced',     CAST(1 AS BIT)),
        (5, 16, N'Advanced',     CAST(1 AS BIT)),
        -- 6. Frontend Developer (React)
        (6,  7, N'Advanced',     CAST(1 AS BIT)),
        (6,  8, N'Advanced',     CAST(1 AS BIT)),
        (6, 16, N'Intermediate', CAST(0 AS BIT)),
        -- 7. DevOps Engineer
        (7, 11, N'Expert',       CAST(1 AS BIT)),
        (7, 12, N'Expert',       CAST(1 AS BIT)),
        (7, 13, N'Advanced',     CAST(0 AS BIT)),
        (7, 18, N'Advanced',     CAST(0 AS BIT)),
        -- 8. HR Generalist (закрита)
        (8, 17, N'Expert',       CAST(1 AS BIT)),
        (8, 16, N'Intermediate', CAST(0 AS BIT))
     ) AS src (VacancyId, SkillId, RequiredLevel, IsMandatory)
WHERE NOT EXISTS (SELECT 1 FROM dbo.VacancySkills vs
                  WHERE vs.VacancyId = src.VacancyId AND vs.SkillId = src.SkillId);
GO

PRINT N'VacancyCatalogDb: seed завершено.';
GO


/* ============================================================================
   ===  ПЕРЕВІРКИ
   ========================================================================== */

-- [1] Жодного FK за межі бази (у SQL Server такий FK неможливий фізично).
SELECT fk.name AS ForeignKey,
       OBJECT_NAME(fk.parent_object_id)     AS FromTable,
       OBJECT_NAME(fk.referenced_object_id) AS ToTable,
       fk.delete_referential_action_desc    AS OnDelete
FROM   sys.foreign_keys fk ORDER BY FromTable;
GO

-- [2] M:N із власними полями — те, що вимагає умова.
SELECT v.Title, s.Name AS Skill, vs.RequiredLevel, vs.IsMandatory, vs.AddedAt
FROM   dbo.VacancySkills vs
JOIN   dbo.Vacancies v ON v.Id = vs.VacancyId
JOIN   dbo.Skills    s ON s.Id = vs.SkillId
WHERE  v.Id = 1
ORDER  BY vs.IsMandatory DESC, s.Name;
GO

-- [3] Зворотний бік M:N — під нього створено IX_VacancySkills_Skill_Level.
SELECT s.Name AS Skill, v.Title, vs.RequiredLevel
FROM   dbo.VacancySkills vs
JOIN   dbo.Skills    s ON s.Id = vs.SkillId
JOIN   dbo.Vacancies v ON v.Id = vs.VacancyId
WHERE  s.Name = N'Docker' AND vs.RequiredLevel IN (N'Advanced', N'Expert');
GO

-- [4] Стрічка відкритих вакансій — під неї створено IX_Vacancies_Feed.
SELECT TOP 10 VacancyId, Title, CompanyName, DepartmentName, SeniorityLevel,
       WorkMode, City, SalaryMin, SalaryMax, Currency, PublishedAt
FROM   dbo.vw_VacancyCard
WHERE  IsOpen = 1
ORDER  BY PublishedAt DESC;
GO

-- [5] Перевірка CHECK-обмеження: від'ємна зарплата має бути відхилена.
BEGIN TRY
    INSERT dbo.Vacancies (CompanyId, DepartmentId, Title, Slug, SalaryMin, SalaryMax)
    VALUES (1, 1, N'Broken vacancy', N'broken-vacancy', -100, 500);
    PRINT N'ПОМИЛКА ТЕСТУ: від''ємну зарплату прийнято!';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'OK, CHECK спрацював: ', ERROR_MESSAGE());
END CATCH
GO

-- [6] Перевірка CHECK-обмеження діапазону: Min > Max має бути відхилено.
BEGIN TRY
    INSERT dbo.Vacancies (CompanyId, DepartmentId, Title, Slug, SalaryMin, SalaryMax)
    VALUES (1, 1, N'Broken range', N'broken-range', 5000, 1000);
    PRINT N'ПОМИЛКА ТЕСТУ: діапазон Min > Max прийнято!';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'OK, CHECK спрацював: ', ERROR_MESSAGE());
END CATCH
GO

-- [7] Контроль: Id вакансій тут і в локальній копії HiringDb мають збігатися.
SELECT Id, Title, IsOpen FROM dbo.Vacancies ORDER BY Id;
GO
