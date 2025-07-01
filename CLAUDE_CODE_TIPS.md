# Claude Code CLI - Поради для оптимізації роботи

Базуючись на аналізі вашої роботи з проектом cc-monitoring та інтеграцією BMAD-METHOD, ось оптимальні способи покращення продуктивності з Claude Code CLI:

## 🚀 Рекомендації для оптимізації

### 1. **Використовуйте `--resume` для довгих сесій**
```bash
ccc --resume
```
Особливо корисно при роботі з BMAD інтеграцією - зберігає контекст між сесіями.

### 2. **Створіть alias для частих команд**
```bash
# Додайте в ~/.bashrc або ~/.zshrc
alias bmad-sync="ccc 'синхронізуй .bmad-core файли з web-bundles'"
alias bmad-version="ccc 'оновити версію BMAD в усіх файлах'"
alias cc-metrics="ccc 'перевір метрики Claude Code та статус моніторингу'"
```

### 3. **Використовуйте шаблони промптів**
Створіть файл `.claude-prompts/bmad-templates.md`:
```markdown
# Оновлення агентів
Оновити всі BMAD агенти з новою версією {version} та згенерувати web bundles

# Перевірка консистентності
Перевір консистентність між .bmad-core та web-bundles директоріями

# Аналіз метрик
Проаналізуй використання Claude Code за останній період та запропонуй оптимізації
```

### 4. **Batch операції для BMAD файлів**
Замість оновлення кожного агента окремо:
```bash
ccc "оновити всі агенти в .bmad-core/agents/ з версією 4.12.0 одночасно"
```

### 5. **Автоматизуйте changelog**
```bash
ccc "проаналізуй останні зміни та оновити CHANGELOG.md відповідно до Keep a Changelog формату"
```

### 6. **Використовуйте TodoWrite для складних інтеграцій**
При плануванні великих змін як BMAD інтеграція:
```bash
ccc "створи детальний todo list для імплементації expansion pack cc-monitoring"
```

### 7. **Збережіть контекстні інструкції**
Додайте в CLAUDE.md специфічні для BMAD команди:
```markdown
## BMAD Integration Commands
- Always sync .bmad-core changes to web-bundles
- Update version in all relevant files when bumping BMAD
- Generate commit messages following BMAD conventions
- Run monitoring checks after significant changes
```

### 8. **Паралельні перевірки метрик**
```bash
ccc "перевір метрики Claude Code, статус Prometheus та доступність Grafana одночасно"
```

### 9. **Створіть скрипти для повторюваних задач**
`scripts/bmad-release.sh`:
```bash
#!/bin/bash
# Автоматизація релізу BMAD
echo "Оновлення BMAD до версії $1"
ccc "оновити BMAD версію до $1, синхронізувати файли, створити комміт"
```

`scripts/sync-bundles.sh`:
```bash
#!/bin/bash
# Синхронізація web bundles
ccc "синхронізуй всі .bmad-core файли з web-bundles та перевір консистентність"
```

### 10. **Використовуйте `--no-stream` для автоматизації**
```bash
# Для логування результатів
ccc --no-stream "згенеруй всі web bundles" > generation.log

# Для CI/CD pipelines
ccc --no-stream "перевір всі тести та метрики" | tee test-results.log
```

### 11. **Оптимізація токенів**
```bash
# Використовуйте конкретні шляхи замість широких пошуків
ccc "оновити версію в .bmad-core/install-manifest.yml" # краще ніж "знайди та оновити версію"

# Групуйте пов'язані задачі
ccc "оновити версію BMAD до 4.12.0 в install-manifest.yml, core-config.yml та всіх агентах"
```

### 12. **Використання контексту проекту**
```bash
# Додайте в CLAUDE.md проектні константи
echo "BMAD_VERSION=4.12.0" >> CLAUDE.md
echo "MONITORING_PORT=3000" >> CLAUDE.md

# Потім використовуйте їх в промптах
ccc "оновити всі посилання на версію BMAD згідно з CLAUDE.md"
```

### 13. **Швидкі перевірки статусу**
```bash
# Створіть alias для швидких перевірок
alias cc-status="ccc 'покажи статус: git status, ./manage.sh ps, curl localhost:9464/metrics | grep claude_code | head -5'"
```

### 14. **Використання пам'яті сесії**
```bash
# На початку сесії визначте контекст
ccc "я працюю над інтеграцією BMAD expansion pack для cc-monitoring"

# Далі можна використовувати короткі команди
ccc "продовж з наступним кроком плану"
```

### 15. **Документування через Claude**
```bash
# Автоматична документація змін
ccc "задокументуй всі зміни зроблені сьогодні в docs/DAILY_PROGRESS.md"

# Генерація README для нових features
ccc "створи README для expansion pack базуючись на поточній імплементації"
```

## 🎯 Специфічні поради для cc-monitoring + BMAD

1. **Моніторинг метрик під час розробки**:
   ```bash
   ccc "покажи графік використання токенів за останню годину з Grafana"
   ```

2. **Автоматизація тестування expansion pack**:
   ```bash
   ccc "створи тестовий сценарій для перевірки всіх компонентів expansion pack"
   ```

3. **Інтеграція з BMAD workflows**:
   ```bash
   ccc "адаптуй greenfield-service.yml workflow для включення моніторингу"
   ```

## 📝 Корисні комбінації

```bash
# Повний цикл оновлення BMAD
ccc "1) оновити версію BMAD 2) синхронізувати файли 3) оновити CHANGELOG 4) створити комміт"

# Аналіз продуктивності
ccc "проаналізуй метрики Claude Code та запропонуй оптимізації для зменшення використання токенів"

# Підготовка до релізу
ccc "перевір всі TODO, оновити документацію, створити PR опис"
```

Ці оптимізації дозволять вам працювати ефективніше з вашим специфічним workflow BMAD інтеграції та моніторингу.