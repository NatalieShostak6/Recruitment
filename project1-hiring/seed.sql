/* ПРОЄКТ №1 — HiringDb: тестові дані.

   ІДЕМПОТЕНТНІСТЬ: скрипт можна запускати скільки завгодно разів —
   дублікатів не з'явиться. Досягається трьома прийомами:
     * довідники   -> INSERT ... WHERE NOT EXISTS
     * кандидати   -> usp_Candidate_Upsert (пошук за Email перед вставкою)
     * воронка     -> блок виконується лише якщо таблиця Applications порожня */

USE HiringDb;
GO

/* 1. Статусна машина: допустимі переходи заявки.
      Applied -> Screening -> Interview -> Offer -> Hired
      Відмова/відкликання можливі з будь-якого НЕтермінального стану.
      Hired / Rejected / Withdrawn — термінальні (вихідних переходів немає). */
INSERT dbo.ApplicationStatusTransitions (FromStatus, ToStatus)
SELECT src.FromStatus, src.ToStatus
FROM (VALUES
        (N'Applied',   N'Screening'),
        (N'Applied',   N'Rejected'),
        (N'Applied',   N'Withdrawn'),
        (N'Screening', N'Interview'),
        (N'Screening', N'Rejected'),
        (N'Screening', N'Withdrawn'),
        (N'Interview', N'Offer'),
        (N'Interview', N'Rejected'),
        (N'Interview', N'Withdrawn'),
        (N'Offer',     N'Hired'),
        (N'Offer',     N'Rejected'),
        (N'Offer',     N'Withdrawn')
     ) AS src (FromStatus, ToStatus)
WHERE NOT EXISTS (SELECT 1 FROM dbo.ApplicationStatusTransitions t
                  WHERE t.FromStatus = src.FromStatus AND t.ToStatus = src.ToStatus);
GO

/* 2. Локальна копія довідника вакансій.
      Id-и ТІ САМІ, що у VacancyCatalogDb.dbo.Vacancies.
      У бойовій системі ці рядки з'являються з подій VacancyPublished /
      VacancyUpdated / VacancyClosed (Лаб. 08). Тут — наповнюємо вручну. */
INSERT dbo.Vacancies (Id, Title, CompanyName, DepartmentName, IsOpen)
SELECT src.Id, src.Title, src.CompanyName, src.DepartmentName, src.IsOpen
FROM (VALUES
        (1, N'Senior .NET Developer',      N'Softonix',       N'Backend',         CAST(1 AS BIT)),
        (2, N'Junior QA Engineer',         N'Softonix',       N'Quality',         CAST(1 AS BIT)),
        (3, N'Product Designer',           N'Softonix',       N'Design',          CAST(1 AS BIT)),
        (4, N'Data Engineer',              N'MedTech UA',     N'Data Platform',   CAST(1 AS BIT)),
        (5, N'Clinical Systems Analyst',   N'MedTech UA',     N'Implementation',  CAST(1 AS BIT)),
        (6, N'Frontend Developer (React)', N'GreenCity Tech', N'Web',             CAST(1 AS BIT)),
        (7, N'DevOps Engineer',            N'GreenCity Tech', N'Platform',        CAST(1 AS BIT)),
        (8, N'HR Generalist',              N'GreenCity Tech', N'People',          CAST(0 AS BIT))  -- закрита: заявку створити не вийде
     ) AS src (Id, Title, CompanyName, DepartmentName, IsOpen)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Vacancies v WHERE v.Id = src.Id);
GO

/* 
   3. Кандидати + профілі (через процедуру: вона сама ідемпотентна за Email).
    */
DECLARE @id BIGINT;

EXEC dbo.usp_Candidate_Upsert @Email = N'olena.kravets@example.com',  @FullName = N'Олена Кравець',
     @Phone = N'+380671112233', @Source = N'LinkedIn', @Headline = N'Senior .NET Developer, 7 років досвіду',
     @LinkedInUrl = N'https://linkedin.com/in/olena-kravets', @ExpectedSalary = 5200, @Currency = 'USD',
     @ReadyToRelocate = 0, @ActorLogin = N'seed', @CandidateId = @id OUTPUT;

EXEC dbo.usp_Candidate_Upsert @Email = N'andrii.bondar@example.com',  @FullName = N'Андрій Бондар',
     @Phone = N'+380502223344', @Source = N'Referral', @Headline = N'Backend .NET / Azure',
     @ExpectedSalary = 4800, @Currency = 'USD', @ReadyToRelocate = 1, @ActorLogin = N'seed', @CandidateId = @id OUTPUT;

EXEC dbo.usp_Candidate_Upsert @Email = N'maryna.shevchuk@example.com', @FullName = N'Марина Шевчук',
     @Phone = N'+380933334455', @Source = N'JobBoard', @Headline = N'QA Engineer, manual + Playwright',
     @ExpectedSalary = 1400, @Currency = 'USD', @ReadyToRelocate = 0, @ActorLogin = N'seed', @CandidateId = @id OUTPUT;

EXEC dbo.usp_Candidate_Upsert @Email = N'ihor.melnyk@example.com',    @FullName = N'Ігор Мельник',
     @Phone = N'+380964445566', @Source = N'Website', @Headline = N'Product Designer (Figma, design systems)',
     @ExpectedSalary = 3000, @Currency = 'USD', @ReadyToRelocate = 1, @ActorLogin = N'seed', @CandidateId = @id OUTPUT;

EXEC dbo.usp_Candidate_Upsert @Email = N'sofiia.tkachenko@example.com', @FullName = N'Софія Ткаченко',
     @Phone = N'+380685556677', @Source = N'Event', @Headline = N'Data Engineer (Spark, Airflow)',
     @ExpectedSalary = 4500, @Currency = 'EUR', @ReadyToRelocate = 1, @ActorLogin = N'seed', @CandidateId = @id OUTPUT;

EXEC dbo.usp_Candidate_Upsert @Email = N'dmytro.koval@example.com',   @FullName = N'Дмитро Коваль',
     @Phone = N'+380736667788', @Source = N'LinkedIn', @Headline = N'Frontend Developer, React/TypeScript',
     @ExpectedSalary = 3200, @Currency = 'USD', @ReadyToRelocate = 0, @ActorLogin = N'seed', @CandidateId = @id OUTPUT;

EXEC dbo.usp_Candidate_Upsert @Email = N'yuliia.hrytsenko@example.com', @FullName = N'Юлія Гриценко',
     @Phone = N'+380977778899', @Source = N'Referral', @Headline = N'DevOps / SRE, Kubernetes',
     @ExpectedSalary = 5000, @Currency = 'USD', @ReadyToRelocate = 1, @ActorLogin = N'seed', @CandidateId = @id OUTPUT;

EXEC dbo.usp_Candidate_Upsert @Email = N'petro.lysenko@example.com',  @FullName = N'Петро Лисенко',
     @Phone = N'+380508889900', @Source = N'JobBoard', @Headline = N'Junior QA, після курсів',
     @ExpectedSalary = 700, @Currency = 'USD', @ReadyToRelocate = 0, @ActorLogin = N'seed', @CandidateId = @id OUTPUT;
GO

/* 
   4. Воронка найму — будується ВИКЛЮЧНО через збережувані процедури,
      тобто seed заодно є димовим тестом бізнес-логіки.
    */
IF NOT EXISTS (SELECT 1 FROM dbo.Applications)
BEGIN
    DECLARE @cOlena   BIGINT = (SELECT Id FROM dbo.Candidates WHERE Email = N'olena.kravets@example.com'),
            @cAndrii  BIGINT = (SELECT Id FROM dbo.Candidates WHERE Email = N'andrii.bondar@example.com'),
            @cMaryna  BIGINT = (SELECT Id FROM dbo.Candidates WHERE Email = N'maryna.shevchuk@example.com'),
            @cIhor    BIGINT = (SELECT Id FROM dbo.Candidates WHERE Email = N'ihor.melnyk@example.com'),
            @cSofiia  BIGINT = (SELECT Id FROM dbo.Candidates WHERE Email = N'sofiia.tkachenko@example.com'),
            @cDmytro  BIGINT = (SELECT Id FROM dbo.Candidates WHERE Email = N'dmytro.koval@example.com'),
            @cYuliia  BIGINT = (SELECT Id FROM dbo.Candidates WHERE Email = N'yuliia.hrytsenko@example.com'),
            @cPetro   BIGINT = (SELECT Id FROM dbo.Candidates WHERE Email = N'petro.lysenko@example.com');

    DECLARE @a1 BIGINT, @a2 BIGINT, @a3 BIGINT, @a4 BIGINT,
            @a5 BIGINT, @a6 BIGINT, @a7 BIGINT, @a8 BIGINT;

    /* --- Сценарій A: повний успішний найм (Applied -> ... -> Hired) --- */
    EXEC dbo.usp_Application_Create @CandidateId = @cOlena, @VacancyId = 1,
         @ActorLogin = N'recruiter.ivanova', @ApplicationId = @a1 OUTPUT;
    EXEC dbo.usp_Application_ChangeStatus @a1, N'Screening', N'recruiter.ivanova', N'Резюме відповідає вимогам';
    EXEC dbo.usp_Application_ChangeStatus @a1, N'Interview', N'recruiter.ivanova', N'Технічна співбесіда 12.09';
    EXEC dbo.usp_Offer_Create @ApplicationId = @a1, @Salary = 5200, @StartDate = '2026-11-03',
         @Currency = 'USD', @ActorLogin = N'hr.director';

    -- Відповідь кандидата на офер. У межах ліміту «4–6 процедур» окремої
    -- процедури для цього немає — показано звичайний UPDATE (операція CRUD).
    UPDATE dbo.Offers
    SET    Status = N'Accepted', RespondedAt = SYSUTCDATETIME(),
           UpdatedAt = SYSUTCDATETIME(), UpdatedBy = N'seed'
    WHERE  ApplicationId = @a1;

    EXEC dbo.usp_Application_ChangeStatus @a1, N'Hired', N'hr.director', N'Офер прийнято, вихід 03.11';

    /* --- Сценарій B: відмова на етапі скринінгу --- */
    EXEC dbo.usp_Application_Create @CandidateId = @cAndrii, @VacancyId = 1,
         @ActorLogin = N'recruiter.ivanova', @ApplicationId = @a2 OUTPUT;
    EXEC dbo.usp_Application_ChangeStatus @a2, N'Screening', N'recruiter.ivanova', NULL;
    EXEC dbo.usp_Application_ChangeStatus @a2, N'Rejected',  N'recruiter.ivanova', N'Вакансію вже закрито іншим кандидатом';

    /* --- Сценарій C: заявка в роботі, зараз на етапі інтерв'ю --- */
    EXEC dbo.usp_Application_Create @CandidateId = @cMaryna, @VacancyId = 2,
         @ActorLogin = N'recruiter.petrenko', @ApplicationId = @a3 OUTPUT;
    EXEC dbo.usp_Application_ChangeStatus @a3, N'Screening', N'recruiter.petrenko', NULL;
    EXEC dbo.usp_Application_ChangeStatus @a3, N'Interview', N'recruiter.petrenko', N'Призначено на 05.10';

    /* --- Сценарій D: щойно подана заявка --- */
    EXEC dbo.usp_Application_Create @CandidateId = @cIhor, @VacancyId = 3,
         @ActorLogin = N'career-site', @ApplicationId = @a4 OUTPUT;

    /* --- Сценарій E: кандидат сам відкликав заявку --- */
    EXEC dbo.usp_Application_Create @CandidateId = @cSofiia, @VacancyId = 4,
         @ActorLogin = N'career-site', @ApplicationId = @a5 OUTPUT;
    EXEC dbo.usp_Application_ChangeStatus @a5, N'Withdrawn', N'candidate', N'Прийняла інший офер';

    /* --- Сценарій F: офер надіслано, відповіді ще немає --- */
    EXEC dbo.usp_Application_Create @CandidateId = @cDmytro, @VacancyId = 6,
         @ActorLogin = N'recruiter.petrenko', @ApplicationId = @a6 OUTPUT;
    EXEC dbo.usp_Application_ChangeStatus @a6, N'Screening', N'recruiter.petrenko', NULL;
    EXEC dbo.usp_Application_ChangeStatus @a6, N'Interview', N'recruiter.petrenko', NULL;
    EXEC dbo.usp_Offer_Create @ApplicationId = @a6, @Salary = 3400, @StartDate = '2026-10-20',
         @Currency = 'USD', @ActorLogin = N'hr.director';

    /* --- Сценарій G: скринінг у процесі --- */
    EXEC dbo.usp_Application_Create @CandidateId = @cYuliia, @VacancyId = 7,
         @ActorLogin = N'recruiter.ivanova', @ApplicationId = @a7 OUTPUT;
    EXEC dbo.usp_Application_ChangeStatus @a7, N'Screening', N'recruiter.ivanova', NULL;

    /* --- Сценарій H: швидка відмова --- */
    EXEC dbo.usp_Application_Create @CandidateId = @cPetro, @VacancyId = 2,
         @ActorLogin = N'career-site', @ApplicationId = @a8 OUTPUT;
    EXEC dbo.usp_Application_ChangeStatus @a8, N'Rejected', N'recruiter.petrenko', N'Немає релевантного досвіду';

    /* Оцінки рекрутера (звичайний UPDATE — демонстрація U з CRUD) */
    UPDATE dbo.Applications SET Score = 9, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = N'seed' WHERE Id = @a1;
    UPDATE dbo.Applications SET Score = 6, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = N'seed' WHERE Id = @a2;
    UPDATE dbo.Applications SET Score = 8, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = N'seed' WHERE Id = @a3;
    UPDATE dbo.Applications SET Score = 8, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = N'seed' WHERE Id = @a6;
    UPDATE dbo.Applications SET Score = 7, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = N'seed' WHERE Id = @a7;
    UPDATE dbo.Applications SET Score = 3, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = N'seed' WHERE Id = @a8;

    PRINT N'HiringDb: воронку найму створено.';
END
ELSE
    PRINT N'HiringDb: заявки вже існують — повторне наповнення пропущено (ідемпотентність).';
GO

PRINT N'HiringDb: seed завершено.';
GO


/* 
    ПЕРЕВІРКИ (ВИКОНАТИ ПІСЛЯ SEED) — відповідають розділу умови
    «Перед здачею перевірте себе»
    */

-- [1] Жодного FOREIGN KEY за межі цієї бази. У SQL Server такий FK створити
--     неможливо в принципі, тому запит показує лише внутрішні зв'язки.
SELECT  fk.name                      AS ForeignKey,
        OBJECT_NAME(fk.parent_object_id)     AS FromTable,
        OBJECT_NAME(fk.referenced_object_id) AS ToTable,
        fk.delete_referential_action_desc    AS OnDelete
FROM    sys.foreign_keys fk
ORDER   BY FromTable;
GO

-- [2] Усі три типи зв'язків присутні:
--     1:1  CandidateProfiles.CandidateId (PK = FK), Offers.ApplicationId (PK = FK)
--     1:N  ApplicationStageHistory.ApplicationId
--     M:N  Applications (CandidateId + VacancyId + власні поля)
SELECT  OBJECT_NAME(fk.parent_object_id) AS ChildTable,
        c.name                           AS ChildColumn,
        OBJECT_NAME(fk.referenced_object_id) AS ParentTable,
        CASE WHEN EXISTS (SELECT 1 FROM sys.index_columns ic
                          JOIN sys.indexes i ON i.object_id = ic.object_id AND i.index_id = ic.index_id
                          WHERE i.is_primary_key = 1 AND ic.object_id = fk.parent_object_id
                            AND ic.column_id = fkc.parent_column_id)
             THEN N'1:1 або частина M:N' ELSE N'1:N' END AS RelationshipHint
FROM    sys.foreign_keys fk
JOIN    sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN    sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id;
GO

-- [3] Перелік індексів із їх типом (фільтровані / унікальні / покриваючі).
SELECT  OBJECT_NAME(i.object_id) AS TableName,
        i.name                   AS IndexName,
        i.is_unique, i.has_filter, i.filter_definition
FROM    sys.indexes i
WHERE   i.object_id IN (OBJECT_ID(N'dbo.Candidates'), OBJECT_ID(N'dbo.Applications'),
                        OBJECT_ID(N'dbo.ApplicationStageHistory'), OBJECT_ID(N'dbo.Offers'),
                        OBJECT_ID(N'dbo.Vacancies'))
  AND   i.name IS NOT NULL
ORDER   BY TableName, IndexName;
GO

-- [4] >>> ГОЛОВНА ПЕРЕВІРКА УМОВИ <<<
--     Свідомо недопустимий перехід має завершитися КЕРОВАНОЮ ПОМИЛКОЮ,
--     а не виконати дію. Очікуємо помилку 50002.
BEGIN TRY
    DECLARE @justApplied BIGINT = (SELECT TOP 1 Id FROM dbo.Applications WHERE Status = N'Applied' ORDER BY Id);
    EXEC dbo.usp_Application_ChangeStatus @justApplied, N'Hired', N'tester', N'Спроба перестрибнути етапи';
    PRINT N'ПОМИЛКА ТЕСТУ: перехід Applied -> Hired пройшов, хоча не мав!';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'OK, перехід відхилено. Код ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
END CATCH
GO

-- [5] Друга перевірка: найм без ПРИЙНЯТОГО офера. Очікуємо помилку 50003.
BEGIN TRY
    DECLARE @offerSent BIGINT = (SELECT TOP 1 a.Id FROM dbo.Applications a
                                 JOIN dbo.Offers o ON o.ApplicationId = a.Id
                                 WHERE a.Status = N'Offer' AND o.Status = N'Sent' ORDER BY a.Id);
    EXEC dbo.usp_Application_ChangeStatus @offerSent, N'Hired', N'tester', N'Спроба найняти без згоди кандидата';
    PRINT N'ПОМИЛКА ТЕСТУ: найм без прийнятого офера пройшов!';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'OK, найм відхилено. Код ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
END CATCH
GO

-- [6] Третя перевірка: повторна заявка на ту саму вакансію. Очікуємо 50013.
BEGIN TRY
    DECLARE @c BIGINT = (SELECT Id FROM dbo.Candidates WHERE Email = N'olena.kravets@example.com');
    DECLARE @dup BIGINT;
    EXEC dbo.usp_Application_Create @CandidateId = @c, @VacancyId = 1, @ApplicationId = @dup OUTPUT;
    PRINT N'ПОМИЛКА ТЕСТУ: дубль заявки створено!';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'OK, дубль відхилено. Код ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
END CATCH
GO

-- [7] CRUD-приклади, які не обгорнуті в процедури (для повноти CRUD).
--     READ з пагінацією через процедуру:
EXEC dbo.usp_Application_Search @Status = N'Rejected', @Page = 1, @PageSize = 10;
GO
--     READ агрегату (3 набори результатів):
DECLARE @first BIGINT = (SELECT MIN(Id) FROM dbo.Applications);
EXEC dbo.usp_Application_GetById @first;
GO
--     DELETE = м'яке видалення (рядок залишається, зникає з індексів і вюшки):
-- UPDATE dbo.Candidates SET IsDeleted = 1, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = N'admin' WHERE Id = 8;
-- SELECT * FROM dbo.vw_ApplicationBoard WHERE CandidateId = 8;   -- порожньо

-- [8] Підсумок стану воронки.
SELECT Status, COUNT(*) AS Applications
FROM   dbo.Applications WHERE IsDeleted = 0
GROUP  BY Status ORDER BY Applications DESC;
GO
