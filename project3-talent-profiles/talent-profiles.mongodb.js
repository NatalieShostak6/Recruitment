/* 
   ПРОЄКТ №3 — talent_profiles (MongoDB)
   Контекст (Bounded Context): Talent Profiles — резюме кандидатів, нотатки
   інтерв'юерів, результати тестових завдань і пули талантів.

   Що продемонстровано (вимоги умови):
     * вбудовування (embedding)      — contact, experience[], education[], comments[]
     * посилання (referencing)       — assessments.resumeId, talentPools.resumeIds[]
     * гібридний підхід              — resumes.latestAssessment (знімок) + повний
                                       документ у колекції assessments
     * гнучка схема                  — документи в resumes мають РІЗНІ набори полів
     * денормалізація для читання     — candidateFullName, vacancyTitle
     * JSON Schema Validation, індекси, aggregation pipeline

   ЯК ЗАПУСКАТИ (VS Code):
     1. Розширення "MongoDB for VS Code" -> Connect -> mongodb://localhost:27017
     2. Відкрити цей файл, натиснути "Run All" (або виділити секцію -> Run Selected)

   ІДЕМПОТЕНТНІСТЬ: усі вставки — replaceOne(..., { upsert: true }) з
   детермінованими _id, тому повторний запуск не створює дублікатів.
    */

use('talent_profiles');

/* 
   Детерміновані ObjectId: "65" + 22 знаки номера = рівно 24 hex-символи.
   1xxx — resumes, 2xxx — interviewNotes, 3xxx — assessments, 4xxx — talentPools
    */
const oid = (n) => ObjectId('65' + String(n).padStart(22, '0'));

/* 
   КРОК 1. Колекції + JSON Schema Validation.

   УВАГА: схема навмисно НЕЖОРСТКА — немає additionalProperties: false.
   Валідуються лише ключові поля (типи й діапазони), решту структури кожен
   документ формує вільно. Саме це дозволяє тримати в одній колекції резюме
   senior-розробника з публікаціями і резюме джуніора з трьох рядків.
    */
const existing = db.getCollectionNames();

function ensureCollection(name, options) {
    if (existing.includes(name)) {
        db.runCommand(Object.assign({ collMod: name }, options));
        print('collMod: ' + name);
    } else {
        db.createCollection(name, options);
        print('created: ' + name);
    }
}

ensureCollection('resumes', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['candidateId', 'candidateFullName', 'source', 'skills'],
            properties: {
                candidateId: {
                    bsonType: 'number',
                    description: 'Id кандидата з HiringDb. Логічне посилання на іншу БД, без FK.'
                },
                candidateFullName: { bsonType: 'string' },
                source: { enum: ['Website', 'Referral', 'LinkedIn', 'JobBoard', 'Event'] },
                skills: {
                    bsonType: 'array',
                    items: {
                        bsonType: 'object',
                        required: ['name'],
                        properties: {
                            name: { bsonType: 'string' },
                            years: { bsonType: 'number', minimum: 0, maximum: 60 }
                        }
                    }
                }
            }
        }
    },
    validationLevel: 'moderate',
    validationAction: 'error'
});

ensureCollection('interviewNotes', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['applicationId', 'resumeId', 'round', 'interviewer'],
            properties: {
                applicationId: { bsonType: 'number' },
                round: { bsonType: 'number', minimum: 1, maximum: 10 },
                recommendation: { enum: ['StrongHire', 'Hire', 'Hold', 'NoHire'] }
            }
        }
    },
    validationLevel: 'moderate',
    validationAction: 'error'
});

ensureCollection('assessments', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['resumeId', 'type', 'takenAt'],
            properties: {
                type: { enum: ['coding', 'questionnaire', 'englishTest', 'portfolioReview'] },
                score: { bsonType: 'number', minimum: 0, maximum: 100 }
            }
        }
    },
    validationLevel: 'moderate',
    validationAction: 'error'
});

ensureCollection('talentPools', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['name', 'slug', 'resumeIds'],
            properties: {
                slug: { bsonType: 'string' },
                resumeIds: { bsonType: 'array', items: { bsonType: 'objectId' } }
            }
        }
    },
    validationLevel: 'moderate',
    validationAction: 'error'
});

/* 
   КРОК 2. Індекси. Для кожного вказано, ПІД ЯКИЙ ЗАПИТ він створений.
    */

// Запит: «резюме кандидата» + правило «одне активне резюме на кандидата».
db.resumes.createIndex({ candidateId: 1 }, { unique: true, name: 'ux_resumes_candidateId' });

// Запит: «знайти кандидатів із навичкою X і досвідом >= N років» (multikey-індекс по масиву).
db.resumes.createIndex({ 'skills.name': 1, 'skills.years': -1 }, { name: 'ix_resumes_skill_years' });

// Запит: повнотекстовий пошук по заголовку й підсумку резюме.
db.resumes.createIndex(
    { headline: 'text', summary: 'text' },
    { name: 'tx_resumes_fulltext', default_language: 'none', weights: { headline: 5, summary: 1 } }
);

// Запит: «нещодавно оновлені резюме» — стрічка рекрутера.
db.resumes.createIndex({ updatedAt: -1 }, { name: 'ix_resumes_updatedAt' });

// Запит: «усі нотатки по заявці, по раундах» + захист від дублю раунду.
db.interviewNotes.createIndex({ applicationId: 1, round: 1 }, { unique: true, name: 'ux_notes_application_round' });

// Запит: «мої інтерв'ю за останній тиждень» (кабінет інтерв'юера).
db.interviewNotes.createIndex({ 'interviewer.userId': 1, createdAt: -1 }, { name: 'ix_notes_interviewer' });

// Запит: «усі тестові завдання конкретного резюме певного типу».
db.assessments.createIndex({ resumeId: 1, type: 1 }, { name: 'ix_assessments_resume_type' });

// Запит: «найкращі результати по вакансії». Частковий індекс: документи без
// score (наприклад, незавершені) в індекс не потрапляють.
db.assessments.createIndex(
    { vacancyId: 1, score: -1 },
    { name: 'ix_assessments_vacancy_score', partialFilterExpression: { score: { $exists: true } } }
);

// Запит: відкриття пулу за slug.
db.talentPools.createIndex({ slug: 1 }, { unique: true, name: 'ux_pools_slug' });

// Запит: «у яких пулах це резюме» (multikey по масиву посилань).
db.talentPools.createIndex({ resumeIds: 1 }, { name: 'ix_pools_resumeIds' });

print('Індекси створено.');

/* 
   КРОК 3. Тестові дані.

   candidateId / applicationId / vacancyId — це ІДЕНТИФІКАТОРИ З ІНШИХ БАЗ.
   Жодних FK: цілісність посилання за потреби перевіряє прикладний код.
     candidateId  1..8  -> HiringDb.dbo.Candidates.Id
     applicationId 1..8 -> HiringDb.dbo.Applications.Id
     vacancyId    1..8  -> VacancyCatalogDb.dbo.Vacancies.Id
    */

const upsert = (coll, doc) => db.getCollection(coll).replaceOne({ _id: doc._id }, doc, { upsert: true });

/* --- RESUME 1: senior-розробниця. Найбагатший документ:
       вбудовані масиви experience/education/certifications/publications,
       вбудований об'єкт contact, ГІБРИД latestAssessment. ------------------ */
upsert('resumes', {
    _id: oid(1001),
    candidateId: 1,
    candidateFullName: 'Олена Кравець',          // ДЕНОРМАЛІЗАЦІЯ: власник — HiringDb
    candidateEmail: 'olena.kravets@example.com', // ДЕНОРМАЛІЗАЦІЯ: власник — HiringDb
    source: 'LinkedIn',
    headline: 'Senior .NET Developer',
    summary: 'Сім років на бекенді: мікросервіси, ASP.NET Core, SQL Server, черги повідомлень.',
    contact: {                                    // ВБУДОВАНИЙ ОБ\'ЄКТ
        phone: '+380671112233',
        city: 'Львів',
        links: { linkedin: 'https://linkedin.com/in/olena-kravets', github: 'https://github.com/okravets' }
    },
    skills: [                                     // ВБУДОВАНИЙ МАСИВ ОБ\'ЄКТІВ
        { name: 'C#', years: 7, level: 'Expert' },
        { name: 'ASP.NET Core', years: 6, level: 'Expert' },
        { name: 'SQL Server', years: 7, level: 'Advanced' },
        { name: 'Dapper', years: 3, level: 'Advanced' },
        { name: 'Docker', years: 4, level: 'Intermediate' }
    ],
    experience: [
        {
            company: 'Intellias', position: 'Senior .NET Engineer',
            from: ISODate('2021-03-01'), to: null, current: true,
            highlights: ['Розпил моноліту на 6 мікросервісів', 'Зниження p95 latency з 1.2с до 300мс']
        },
        {
            company: 'SoftServe', position: '.NET Developer',
            from: ISODate('2018-06-01'), to: ISODate('2021-02-28'), current: false,
            highlights: ['Платіжний шлюз для ритейлу']
        }
    ],
    education: [
        { institution: 'НУ "Львівська політехніка"', degree: 'Магістр', field: 'Комп\'ютерні науки', year: 2018 }
    ],
    certifications: [
        { name: 'AZ-204 Azure Developer Associate', issuer: 'Microsoft', year: 2023 }
    ],
    publications: [                               // ПОЛЕ Є ЛИШЕ В ЦЬОМУ РЕЗЮМЕ
        { title: 'Шаблон Outbox у .NET: практичний розбір', url: 'https://dou.ua/forums/topic/outbox', year: 2024 }
    ],
    languages: [{ code: 'uk', level: 'Native' }, { code: 'en', level: 'C1' }, { code: 'pl', level: 'B1' }],
    latestAssessment: {                           // ГІБРИД: знімок поруч із посиланням
        assessmentId: oid(3001),
        type: 'coding',
        score: 92,
        takenAt: ISODate('2026-09-16T10:00:00Z')
    },
    tags: ['dotnet', 'backend', 'senior'],
    createdAt: ISODate('2026-09-10T08:00:00Z'),
    updatedAt: ISODate('2026-09-18T12:30:00Z')
});

/* --- RESUME 2: інший набір полів — немає education і certifications,
       натомість є openSource і militaryService. ---------------------------- */
upsert('resumes', {
    _id: oid(1002),
    candidateId: 2,
    candidateFullName: 'Андрій Бондар',
    candidateEmail: 'andrii.bondar@example.com',
    source: 'Referral',
    headline: 'Backend .NET / Azure Engineer',
    summary: 'Бекенд і хмара. Самоук, прийшов із системного адміністрування.',
    contact: { phone: '+380502223344', city: 'Київ', links: { github: 'https://github.com/abondar' } },
    skills: [
        { name: 'C#', years: 5, level: 'Advanced' },
        { name: 'ASP.NET Core', years: 4, level: 'Advanced' },
        { name: 'Docker', years: 5, level: 'Advanced' },
        { name: 'Kubernetes', years: 2, level: 'Intermediate' }
    ],
    experience: [
        { company: 'Ciklum', position: '.NET Developer', from: ISODate('2020-09-01'), to: null, current: true }
    ],
    openSource: [                                  // ПОЛЕ Є ЛИШЕ ТУТ
        { repo: 'abondar/healthchecks-ui-ext', stars: 128, role: 'maintainer' }
    ],
    militaryService: { status: 'Deferred', until: ISODate('2027-01-01') },  // ПОЛЕ Є ЛИШЕ ТУТ
    languages: [{ code: 'uk', level: 'Native' }, { code: 'en', level: 'B2' }],
    tags: ['dotnet', 'azure'],
    createdAt: ISODate('2026-09-11T09:20:00Z'),
    updatedAt: ISODate('2026-09-11T09:20:00Z')
});

/* --- RESUME 3: QA. Замість experience — courses; є willingToTravel. ------- */
upsert('resumes', {
    _id: oid(1003),
    candidateId: 3,
    candidateFullName: 'Марина Шевчук',
    candidateEmail: 'maryna.shevchuk@example.com',
    source: 'JobBoard',
    headline: 'QA Engineer (manual + Playwright)',
    summary: 'Два роки ручного тестування, перехід в автоматизацію.',
    contact: { phone: '+380933334455', city: 'Львів' },
    skills: [
        { name: 'Playwright', years: 1, level: 'Basic' },
        { name: 'SQL Server', years: 2, level: 'Basic' },
        { name: 'English B2+', level: 'Intermediate' }       // тут НЕМАЄ поля years
    ],
    experience: [
        { company: 'GlobalLogic', position: 'QA Engineer', from: ISODate('2024-02-01'), to: null, current: true }
    ],
    courses: [                                               // ПОЛЕ Є ЛИШЕ ТУТ
        { title: 'QA Automation з Playwright', provider: 'Hillel', completedAt: ISODate('2026-05-20') }
    ],
    willingToTravel: false,
    latestAssessment: { assessmentId: oid(3002), type: 'questionnaire', score: 74, takenAt: ISODate('2026-09-20T09:00:00Z') },
    tags: ['qa', 'junior-plus'],
    createdAt: ISODate('2026-09-15T11:00:00Z'),
    updatedAt: ISODate('2026-09-21T08:10:00Z')
});

/* --- RESUME 4: дизайнер. З'являється portfolio і awards, зникає education. */
upsert('resumes', {
    _id: oid(1004),
    candidateId: 4,
    candidateFullName: 'Ігор Мельник',
    candidateEmail: 'ihor.melnyk@example.com',
    source: 'Website',
    headline: 'Product Designer',
    summary: 'Дизайн-системи та складні B2B-інтерфейси.',
    contact: { city: 'Одеса', links: { behance: 'https://behance.net/imelnyk' } },
    skills: [
        { name: 'Figma', years: 6, level: 'Expert' },
        { name: 'Комунікація', years: 6, level: 'Advanced' }
    ],
    portfolio: {                                             // ВКЛАДЕНИЙ ОБ\'ЄКТ, є лише тут
        caseStudies: [
            { title: 'Редизайн кабінету енергопостачальника', url: 'https://behance.net/p/1', year: 2025 },
            { title: 'Дизайн-система Aurora', url: 'https://behance.net/p/2', year: 2024 }
        ],
        preferredTools: ['Figma', 'Framer', 'Rive']
    },
    awards: [{ name: 'IT Arena Design Award', year: 2024, place: 2 }],
    tags: ['design', 'ux'],
    createdAt: ISODate('2026-09-19T14:00:00Z'),
    updatedAt: ISODate('2026-09-19T14:00:00Z')
});

/* --- RESUME 5: data engineer. Вкладений об'єкт preferences. --------------- */
upsert('resumes', {
    _id: oid(1005),
    candidateId: 5,
    candidateFullName: 'Софія Ткаченко',
    candidateEmail: 'sofiia.tkachenko@example.com',
    source: 'Event',
    headline: 'Data Engineer',
    summary: 'ETL на Spark та Airflow, досвід роботи з медичними даними і GDPR.',
    contact: { phone: '+380685556677', city: 'Київ' },
    skills: [
        { name: 'Python', years: 6, level: 'Advanced' },
        { name: 'Apache Spark', years: 4, level: 'Advanced' },
        { name: 'GDPR', years: 3, level: 'Intermediate' },
        { name: 'Docker', years: 4, level: 'Intermediate' }
    ],
    experience: [
        { company: 'Roche', position: 'Data Engineer', from: ISODate('2022-01-10'), to: null, current: true },
        { company: 'EPAM', position: 'ETL Developer', from: ISODate('2019-04-01'), to: ISODate('2021-12-31'), current: false }
    ],
    education: [{ institution: 'КНУ ім. Шевченка', degree: 'Магістр', field: 'Прикладна математика', year: 2019 }],
    preferences: {                                            // ВКЛАДЕНИЙ ОБ\'ЄКТ, є лише тут
        workMode: 'Remote',
        relocation: { ready: true, countries: ['PL', 'DE', 'NL'] },
        salary: { min: 4500, currency: 'EUR' }
    },
    languages: [{ code: 'uk', level: 'Native' }, { code: 'en', level: 'C1' }, { code: 'de', level: 'A2' }],
    tags: ['data', 'python'],
    createdAt: ISODate('2026-08-02T07:30:00Z'),
    updatedAt: ISODate('2026-09-05T16:45:00Z')
});

/* --- RESUME 6: МІНІМАЛЬНИЙ документ. Тільки обов'язкові поля + одне своє.
       Найяскравіша демонстрація гнучкої схеми в одній колекції. ------------ */
upsert('resumes', {
    _id: oid(1006),
    candidateId: 8,
    candidateFullName: 'Петро Лисенко',
    source: 'JobBoard',
    skills: [{ name: 'English B2+' }],
    note: 'Резюме заповнене частково — кандидат надіслав лише посилання на курс.',
    createdAt: ISODate('2026-09-25T18:05:00Z'),
    updatedAt: ISODate('2026-09-25T18:05:00Z')
});

/* --- INTERVIEW NOTES: посилання на заявку (інша БД) і на резюме (ця БД),
       вбудовані об'єкт interviewer, об'єкт scores і масив comments. -------- */
upsert('interviewNotes', {
    _id: oid(2001),
    applicationId: 1,                              // -> HiringDb.dbo.Applications.Id (без FK)
    resumeId: oid(1001),                           // ПОСИЛАННЯ в межах цієї ж БД
    vacancyId: 1,
    vacancyTitle: 'Senior .NET Developer',         // ДЕНОРМАЛІЗАЦІЯ: власник — VacancyCatalogDb
    round: 1,
    stage: 'Technical',
    interviewer: { userId: 'u-101', displayName: 'Тарас Гнатюк', role: 'Tech Lead' },
    scores: { technical: 9, communication: 8, culture: 9, total: 8.7 },
    recommendation: 'StrongHire',
    comments: [                                    // ВБУДОВАНИЙ МАСИВ
        { author: 'Тарас Гнатюк', text: 'Чітко пояснила ізоляцію транзакцій.', createdAt: ISODate('2026-09-12T13:10:00Z') },
        { author: 'Ірина Іванова', text: 'Узгодила вихід на 03.11.', createdAt: ISODate('2026-09-13T09:00:00Z') }
    ],
    createdAt: ISODate('2026-09-12T13:00:00Z')
});

upsert('interviewNotes', {
    _id: oid(2002),
    applicationId: 1,
    resumeId: oid(1001),
    vacancyId: 1,
    vacancyTitle: 'Senior .NET Developer',
    round: 2,
    stage: 'Final',
    interviewer: { userId: 'u-102', displayName: 'Ірина Іванова', role: 'HR Director' },
    scores: { motivation: 9, culture: 9, total: 9 },   // інший набір критеріїв — гнучка схема
    recommendation: 'Hire',
    comments: [],
    createdAt: ISODate('2026-09-15T11:00:00Z')
});

upsert('interviewNotes', {
    _id: oid(2003),
    applicationId: 3,
    resumeId: oid(1003),
    vacancyId: 2,
    vacancyTitle: 'Junior QA Engineer',
    round: 1,
    stage: 'Screening',
    interviewer: { userId: 'u-103', displayName: 'Олег Петренко', role: 'QA Lead' },
    scores: { technical: 6, communication: 8, total: 7 },
    recommendation: 'Hold',
    comments: [{ author: 'Олег Петренко', text: 'Слабка теорія тест-дизайну, але швидко вчиться.', createdAt: ISODate('2026-09-22T10:30:00Z') }],
    followUp: { needed: true, topic: 'Тест-дизайн', scheduledFor: ISODate('2026-10-05T10:00:00Z') },  // поле є лише тут
    createdAt: ISODate('2026-09-22T10:00:00Z')
});

upsert('interviewNotes', {
    _id: oid(2004),
    applicationId: 6,
    resumeId: oid(1001),
    vacancyId: 6,
    vacancyTitle: 'Frontend Developer (React)',
    round: 1,
    stage: 'Technical',
    interviewer: { userId: 'u-101', displayName: 'Тарас Гнатюк', role: 'Tech Lead' },
    scores: { technical: 8, communication: 7, total: 7.5 },
    recommendation: 'Hire',
    comments: [],
    createdAt: ISODate('2026-09-24T15:00:00Z')
});

upsert('interviewNotes', {
    _id: oid(2005),
    applicationId: 7,
    resumeId: oid(1005),
    vacancyId: 7,
    vacancyTitle: 'DevOps Engineer',
    round: 1,
    stage: 'Screening',
    interviewer: { userId: 'u-102', displayName: 'Ірина Іванова', role: 'HR Director' },
    scores: { motivation: 8, total: 8 },
    recommendation: 'Hire',
    comments: [],
    createdAt: ISODate('2026-09-26T09:40:00Z')
});

/* --- ASSESSMENTS: ПОСИЛАННЯ на resumes + структура документа ЗАЛЕЖИТЬ ВІД
       ТИПУ завдання. Чотири типи — чотири різні форми документа. ----------- */
upsert('assessments', {
    _id: oid(3001),
    resumeId: oid(1001),                           // reference
    candidateId: 1,
    vacancyId: 1,
    type: 'coding',
    takenAt: ISODate('2026-09-16T10:00:00Z'),
    durationMinutes: 85,
    score: 92,
    tasks: [                                        // структура, характерна ЛИШЕ для coding
        { title: 'Транзакційна зміна статусу', language: 'csharp', testsPassed: 12, testsTotal: 12, complexity: 'medium' },
        { title: 'Оптимізація запиту', language: 'sql', testsPassed: 7, testsTotal: 8, complexity: 'hard' }
    ],
    reviewer: { userId: 'u-101', displayName: 'Тарас Гнатюк' }
});

upsert('assessments', {
    _id: oid(3002),
    resumeId: oid(1003),
    candidateId: 3,
    vacancyId: 2,
    type: 'questionnaire',
    takenAt: ISODate('2026-09-20T09:00:00Z'),
    score: 74,
    answers: [                                      // структура ЛИШЕ для questionnaire
        { questionId: 'q1', question: 'Що таке межовий аналіз?', answer: 'Перевірка значень на межах діапазону', correct: true },
        { questionId: 'q2', question: 'Чим smoke відрізняється від sanity?', answer: 'Не впевнена', correct: false },
        { questionId: 'q3', question: 'Назвіть рівні тестування', answer: 'unit, integration, system, acceptance', correct: true }
    ]
});

upsert('assessments', {
    _id: oid(3003),
    resumeId: oid(1005),
    candidateId: 5,
    vacancyId: 4,
    type: 'englishTest',
    takenAt: ISODate('2026-08-05T12:00:00Z'),
    score: 88,
    level: 'C1',                                    // структура ЛИШЕ для englishTest
    sections: { listening: 90, reading: 92, writing: 84, speaking: 86 },
    proctored: true
});

upsert('assessments', {
    _id: oid(3004),
    resumeId: oid(1004),
    candidateId: 4,
    vacancyId: 3,
    type: 'portfolioReview',
    takenAt: ISODate('2026-09-21T16:00:00Z'),
    score: 81,
    criteria: [                                     // структура ЛИШЕ для portfolioReview
        { name: 'Візуальна якість', weight: 0.3, mark: 9 },
        { name: 'Глибина кейсів', weight: 0.4, mark: 7 },
        { name: 'Системність мислення', weight: 0.3, mark: 8 }
    ],
    reviewer: { userId: 'u-104', displayName: 'Анна Клименко' }
});

/* Документ БЕЗ поля score — навмисно: показує частковий індекс
   ix_assessments_vacancy_score (незавершені роботи в індекс не потрапляють). */
upsert('assessments', {
    _id: oid(3005),
    resumeId: oid(1002),
    candidateId: 2,
    vacancyId: 1,
    type: 'coding',
    takenAt: ISODate('2026-09-23T11:00:00Z'),
    status: 'InProgress',
    tasks: [{ title: 'Транзакційна зміна статусу', language: 'csharp', testsPassed: 4, testsTotal: 12 }]
});

/* --- TALENT POOLS: чисте ПОСИЛАННЯ (referencing). Пул може містити тисячі
       резюме, тому вбудовувати їх у документ пулу не можна — ліміт 16 МБ
       і резюме живуть власним життям. Зберігаємо лише масив ObjectId. ------ */
upsert('talentPools', {
    _id: oid(4001),
    name: '.NET талант-пул 2026',
    slug: 'dotnet-2026',
    description: 'Сильні .NET-кандидати, яких не взяли через закриття вакансії.',
    ownerUserId: 'u-102',
    resumeIds: [oid(1001), oid(1002)],              // REFERENCE на resumes
    createdAt: ISODate('2026-09-01T10:00:00Z')
});

upsert('talentPools', {
    _id: oid(4002),
    name: 'Релокація до ЄС',
    slug: 'eu-relocation',
    description: 'Кандидати, готові до переїзду.',
    ownerUserId: 'u-102',
    resumeIds: [oid(1002), oid(1004), oid(1005)],
    autoRefreshRule: { field: 'preferences.relocation.ready', equals: true },  // поле є лише тут
    createdAt: ISODate('2026-09-03T09:00:00Z')
});

print('Seed завершено. Документів: resumes=' + db.resumes.countDocuments() +
      ', interviewNotes=' + db.interviewNotes.countDocuments() +
      ', assessments=' + db.assessments.countDocuments() +
      ', talentPools=' + db.talentPools.countDocuments());

/* ===========================================================================
   КРОК 4. ЗАПИТИ. Виділіть потрібний блок і натисніть "Run Selected".
   ========================================================================= */

/* --- [1] ГНУЧКА СХЕМА: документи з різними наборами полів в одній колекції.
       Саме цей запит вимагає розділ «Перед здачею перевірте себе». --------- */
db.resumes.find({}, { candidateFullName: 1, headline: 1 }).toArray()
    .forEach(d => print(d.candidateFullName + ' -> поля: ' +
        Object.keys(db.resumes.findOne({ _id: d._id })).join(', ')));

/* --- [2] Знайти резюме, де є конкретна «необов'язкова» секція. ------------ */
db.resumes.find({ portfolio: { $exists: true } }, { candidateFullName: 1, 'portfolio.preferredTools': 1 });
db.resumes.find({ militaryService: { $exists: true } }, { candidateFullName: 1, militaryService: 1 });

/* --- [3] Пошук по вбудованому масиву (працює multikey-індекс). ------------ */
db.resumes.find(
    { skills: { $elemMatch: { name: 'C#', years: { $gte: 5 } } } },
    { candidateFullName: 1, headline: 1, 'skills.$': 1 }
);

/* --- [4] Повнотекстовий пошук. ------------------------------------------- */
db.resumes.find({ $text: { $search: 'мікросервіси' } }, { score: { $meta: 'textScore' }, candidateFullName: 1 })
          .sort({ score: { $meta: 'textScore' } });

/* --- [5] ПОСИЛАННЯ: розгорнути пул талантів у реальні резюме. ------------- */
db.talentPools.aggregate([
    { $match: { slug: 'dotnet-2026' } },
    { $lookup: { from: 'resumes', localField: 'resumeIds', foreignField: '_id', as: 'members' } },
    { $project: { name: 1, 'members.candidateFullName': 1, 'members.headline': 1 } }
]);

/* --- [6] AGGREGATION: топ навичок серед усіх кандидатів. ----------------- */
db.resumes.aggregate([
    { $unwind: '$skills' },
    { $group: { _id: '$skills.name', candidates: { $sum: 1 }, avgYears: { $avg: '$skills.years' } } },
    { $project: { _id: 0, skill: '$_id', candidates: 1, avgYears: { $round: ['$avgYears', 1] } } },
    { $sort: { candidates: -1, skill: 1 } },
    { $limit: 10 }
]);

/* --- [7] AGGREGATION: середня оцінка інтерв'ю по вакансіях.
       vacancyTitle тут денормалізований, тому звертатися до бази Каталогу
       не потрібно — у цьому й сенс дублювання поля. ----------------------- */
db.interviewNotes.aggregate([
    { $group: {
        _id: { vacancyId: '$vacancyId', vacancyTitle: '$vacancyTitle' },
        rounds: { $sum: 1 },
        avgTotal: { $avg: '$scores.total' },
        recommendations: { $push: '$recommendation' }
    } },
    { $project: { _id: 0, vacancyId: '$_id.vacancyId', vacancyTitle: '$_id.vacancyTitle',
                  rounds: 1, avgTotal: { $round: ['$avgTotal', 2] }, recommendations: 1 } },
    { $sort: { avgTotal: -1 } }
]);

/* --- [8] AGGREGATION + $lookup: нотатки разом із резюме (в межах однієї БД). */
db.interviewNotes.aggregate([
    { $match: { recommendation: { $in: ['StrongHire', 'Hire'] } } },
    { $lookup: { from: 'resumes', localField: 'resumeId', foreignField: '_id', as: 'resume' } },
    { $unwind: '$resume' },
    { $project: {
        _id: 0,
        candidate: '$resume.candidateFullName',
        headline: '$resume.headline',
        vacancyTitle: 1, round: 1, stage: 1,
        total: '$scores.total', recommendation: 1
    } },
    { $sort: { total: -1 } }
]);

/* --- [9] AGGREGATION $facet: один прохід — кілька зрізів по assessments. -- */
db.assessments.aggregate([
    { $facet: {
        byType: [
            { $group: { _id: '$type', count: { $sum: 1 }, avgScore: { $avg: '$score' } } },
            { $project: { _id: 0, type: '$_id', count: 1, avgScore: { $round: ['$avgScore', 1] } } },
            { $sort: { count: -1 } }
        ],
        topResults: [
            { $match: { score: { $gte: 80 } } },
            { $sort: { score: -1 } },
            { $project: { _id: 0, candidateId: 1, type: 1, score: 1 } }
        ],
        unfinished: [
            { $match: { score: { $exists: false } } },
            { $project: { _id: 0, candidateId: 1, type: 1, status: 1 } }
        ]
    } }
]);

/* --- [10] Гібрид у дії: швидкий список «резюме + останній бал» БЕЗ $lookup,
       бо знімок latestAssessment лежить прямо в документі резюме. --------- */
db.resumes.find(
    { latestAssessment: { $exists: true } },
    { candidateFullName: 1, headline: 1, 'latestAssessment.type': 1, 'latestAssessment.score': 1 }
).sort({ 'latestAssessment.score': -1 });

/* --- [11] Перевірка валідатора: документ без обов'язкових полів має впасти. */
try {
    db.resumes.insertOne({ candidateFullName: 'Без обов\'язкових полів' });
    print('ПОМИЛКА ТЕСТУ: валідатор пропустив некоректний документ!');
} catch (e) {
    print('OK, валідатор відхилив документ: ' + e.message.substring(0, 120));
}

/* --- [12] Перевірка валідатора: рейтинг поза діапазоном. ----------------- */
try {
    db.assessments.insertOne({ resumeId: oid(1001), type: 'coding', takenAt: new Date(), score: 150 });
    print('ПОМИЛКА ТЕСТУ: score=150 прийнято!');
} catch (e) {
    print('OK, валідатор відхилив score=150.');
}

/* --- [13] План виконання: переконатися, що індекс використовується. ------- */
db.resumes.find({ 'skills.name': 'Docker' }).explain('executionStats').executionStats;

/* --- [14] Перелік усіх індексів бази. ------------------------------------ */
['resumes', 'interviewNotes', 'assessments', 'talentPools'].forEach(c => {
    print('--- ' + c);
    db.getCollection(c).getIndexes().forEach(i => print('    ' + i.name + ' ' + JSON.stringify(i.key)));
});