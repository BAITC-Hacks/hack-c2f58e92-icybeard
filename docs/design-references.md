# Референсы Mobbin для экранов Darumen

Подобраны 25.09.2026 через Mobbin MCP: по одному запросу на экран, оставлены только те скриншоты, где паттерн совпадает с нашей задачей. Ссылки ведут на Mobbin (нужен вход). Стиль остаётся Clinical Minimal (`design/tokens.json`): берём структуру и иерархию, не цвета.

## Мобильное приложение (Flutter)

| Экран | Референс | Что берём |
|---|---|---|
| Login | [Opera](https://mobbin.com/screens/75ce7b25-7cb0-4cf0-bca8-931e97e3f207), [Blue Apron](https://mobbin.com/screens/faea2606-18b7-4a8b-9dbd-51fdf2456870) | одна главная кнопка (eGov mobile), разделитель «или», логин как вторичный путь, ссылка гостя текстом внизу |
| Home | [Lloyds](https://mobbin.com/screens/920c756b-1adf-46e4-9964-6a82c47ce915), [MacroFactor](https://mobbin.com/screens/1316a6e5-230c-4337-9aa4-c1ba101e8a0e) | карточка-статус сверху с одной стрелкой, плитки 2×2 с иконкой в кружке и подписью-существительным, секции с заголовком и «Все» |
| Мой путь | [Bumble «Your report»](https://mobbin.com/screens/09426d05-9e3c-4a74-b206-da7d04e07ba4), [Blue Apron order](https://mobbin.com/screens/27b81a1c-c5ff-4ec1-ac5b-b6770c87c3dc), [Fly Delta bag](https://mobbin.com/screens/549e00e8-24dd-4590-bb15-462781b4a8f6) | вертикальный таймлайн: пройденные шаги с галочкой и датой, будущие серые с нормой срока; над ним компактная карточка с прогресс-полосой стадий |
| Сколько ждут | [Zocdoc](https://mobbin.com/screens/3b03d53a-6614-4054-a34a-0d8ba4213c8e), [Fresha select date](https://mobbin.com/screens/e7f0bf07-0aa9-402e-9b35-182a0345ac82) | выбор региона и профиля крупными ячейками, список организаций карточками с одной цифрой ожидания и кнопкой |
| Лекарства | [Lloyds policy details](https://mobbin.com/screens/511cb48c-10ac-47eb-92c0-29469c70cd57), [Fresha appointment](https://mobbin.com/screens/5ef9f1bf-25b5-487c-b347-2dd30dc2d263) | статус чипом сверху («покрыт программой»), одно большое число справа, детали строками ключ-значение |
| Вакцинация | [MacroFactor calories](https://mobbin.com/screens/c41df34d-1598-4a62-ad7c-728fcb8255ae) | строка = название, процент, тонкая полоса; подпись источника под списком |
| Уведомления | [Luma](https://mobbin.com/screens/6fa303e6-c330-410c-a676-b248fa51df6a), [ShopBack](https://mobbin.com/screens/227e403c-cb93-4ccb-b10f-c02d06f8d12c) | группировка «Сегодня / Вчера / дата», одна строка описания, без аватаров; пустое состояние с одной кнопкой |
| Профиль | [Fresha profile](https://mobbin.com/screens/9f5de068-8e35-4144-8bfb-abf636a1ff75), [Lloyds profile](https://mobbin.com/screens/3998c4dc-daad-4b88-a52f-2d9bd252c922) | группы строк в карточках, язык как строка со значением, «Выйти» отдельной карточкой внизу, ИИН маской как «User ID» |
| Пациенты (врач) | [LinkedIn job tracker](https://mobbin.com/screens/3bc4f28c-6c33-473e-b9ce-70e21727a092), [Plain priorities](https://mobbin.com/screens/4b396c6e-917b-4dcf-bea8-0587c3dd4b1e) | фильтры-дропдауны в одну строку, карточка со статусом-чипом в углу, следующий шаг как вопрос с двумя действиями |
| Маршрут пациента (врач) | те же, что «Мой путь», плюс [Lloyds challenge](https://mobbin.com/screens/25e7af65-186d-4130-8244-f064bd0ddf1a) | нумерованные шаги, аккордеоны «Детали» и «Условия» под таймлайном, кнопка действия под ними |
| Направление | [Cash App](https://mobbin.com/screens/30b1b247-ff54-4679-b558-4429f4fdf551), [Lloyds «When did you move in?»](https://mobbin.com/screens/7e588637-2b44-43ee-828c-5ebb846cc276), [Tripadvisor AI](https://mobbin.com/screens/3e1d13a6-de26-4341-8dc2-60d6d5e4ddec) | один вопрос на экран, прогресс-полоса сверху, варианты крупными кнопками, «Далее» внизу справа |
| Журнал решений | [Monzo activity](https://mobbin.com/screens/8f921563-4da7-4e2b-98ea-e3e5e47b9229), [Mesh activity](https://mobbin.com/screens/483f599a-80ff-4fb0-a405-2eb956a4c9f2) | группы по дням заглавными подписями, число справа tabular, серые подстроки |
| Скрайб | [Givingli voice note](https://mobbin.com/screens/2ba9b754-8a8f-4ad7-b5bb-776915983e60), [Alta listening](https://mobbin.com/screens/74070b41-75a9-4385-9477-84375ab7b844), [Perplexity voice](https://mobbin.com/screens/139a3608-81ec-456c-8287-045f9a68c0a6) | нижний лист записи: волна, таймер, одна круглая кнопка стоп; во время распознавания текст появляется под записью |

## Веб (Vue)

| Страница | Референс | Что берём |
|---|---|---|
| Каркас для регулятора и врача | [Cloudflare](https://mobbin.com/screens/59f5d9b0-1491-4a8b-a0ea-20a27682dfd5), [Klaviyo](https://mobbin.com/screens/9e0750ed-89c5-4296-87cd-44844b5fa846) | боковая навигация с группами, поиск сверху, заголовок страницы с периодом справа |
| `/gov` обзор | [Cloudflare](https://mobbin.com/screens/59f5d9b0-1491-4a8b-a0ea-20a27682dfd5), [Substack audience](https://mobbin.com/screens/b5ff6e00-294b-4c91-b6fd-4862a7b5eadf) | KPI-ряд со спарклайнами, карта слева и таблица регионов справа в одной карточке, ранжированный список ниже |
| `/gov/regions/:kato`, `/gov/organizations/:mo` | [Sentry issue](https://mobbin.com/screens/44f8570c-f154-4173-a40b-06d1adba7f00), [Workable review](https://mobbin.com/screens/2a8c031e-ee83-4b78-adef-612a201d3c56) | шапка с сущностью и действиями, горизонтальный таймлайн-сводка, правая колонка с фактами и историей |
| `/gov/simulator` | [Quicken planner](https://mobbin.com/screens/83885d0d-82e5-45f1-94b4-17cd3148065e), [Oyster calculator](https://mobbin.com/screens/35aa2491-e2e5-4d3f-88ca-a14a25d1c212) | форма слева узкой колонкой, справа график с доверительной полосой и разбор в карточках |
| `/gov/insight` | [Gemini Notebook](https://mobbin.com/screens/80c2ce7c-50a3-4d5a-b3c8-14ac3e709c7d), [Elicit](https://mobbin.com/screens/358f5d13-4f91-4565-81d4-36e7813fe2ae) | три колонки: источники, диалог с подсказками-вопросами, отчёт с кнопкой экспорта |
| `/doctor/worklist` | [Airtable](https://mobbin.com/screens/1ccf6613-4abd-420f-9d18-ac7b40a04848), [Dovetail](https://mobbin.com/screens/832e5719-7133-4733-a7d2-87061364df60) | статус цветным чипом в первой колонке, фильтры и сортировка кнопками над таблицей, строки плотные |
| `/doctor/patients/:ref`, `/me/route` | [Workable](https://mobbin.com/screens/2a8c031e-ee83-4b78-adef-612a201d3c56), [HubSpot steps](https://mobbin.com/screens/43fe17a5-d022-4e2e-ab3c-56a6e0a8e9c3) | таймлайн полосой сверху, чек-лист строками с иконкой шага и метриками |
| `/doctor/referral` | [Hers calculator](https://mobbin.com/screens/464e2064-0912-49f6-92ac-26580c6bea49), [Oyster](https://mobbin.com/screens/35aa2491-e2e5-4d3f-88ca-a14a25d1c212) | форма слева, результат справа в цветной карточке с большими числами, разбор ниже |
| `/doctor/scribe` | [Maze session](https://mobbin.com/screens/ced395e9-7221-429e-8e37-a921d5ad215c), [Apollo](https://mobbin.com/screens/2d40bc63-69af-4e24-85e9-a570f5e659cd), [Mistral speech-to-text](https://mobbin.com/screens/13886f93-4892-47f6-b3c0-3f0b2f22d9ab) | плеер и сводка слева, стенограмма с таймкодами и метками говорящих справа, вкладки «Сводка / Стенограмма» |
| `/wait`, `/medicines` (гость) | [Care.com](https://mobbin.com/screens/e6f07e6d-922e-42a9-becc-d5569c57af51), [TravelPerk](https://mobbin.com/screens/cfe484a1-96ab-4d9b-a7f8-3fd03b21162c) | одна строка поиска с сегментами «регион · профиль», результаты карточками с одним числом справа и кнопкой |
| `/gov/audit`, `/doctor/decisions`, `/steward` | [Front audit log](https://mobbin.com/screens/0c2efddc-d2d9-4a17-b589-34523d08e1d8), [PlanetScale](https://mobbin.com/screens/d7448333-6400-49dd-b11f-e48e4e229200) | фильтры дропдаунами, экспорт справа, карточка-пояснение справа, mono для кодов |

## План переделки веба

1. Каркас: боковая навигация для регулятора, врача и стюарда; шапка страницы с KPI-рядом; верхняя полоса остаётся только гражданину.
2. Обзор регулятора по Cloudflare: KPI со спарклайнами, карта и таблица регионов в одной карточке.
3. Таблицы по Airtable и Front: свой стиль DataTable под токены, чипы статусов, плотность.
4. Формы врача по Hers и Oyster: форма слева, результат справа.
5. Скрайб по Maze: плеер, сводка, стенограмма с таймкодами и языком сегмента.
6. Гражданин по Care.com: одна поисковая строка, карточки результатов, макет 720 px.
