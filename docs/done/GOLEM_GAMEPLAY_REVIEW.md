# Golem — интеграция в бой для финальной приёмки

08.10.2026. План, SVG art и animations приняты пользователем, включая одновременный удар двумя руками. **Golem полностью принят пользователем.** Animated default включён, static сохранён. Отчёты перенесены в docs/done для отдельного commit; push требует отдельного разрешения.

- [Настоящий бой](http://127.0.0.1:4175/preview/golem-gameplay/) — шестая волна, где появляется Golem; STATIC/ANIMATED и Pause внизу.
- [Пять цветов мха](http://127.0.0.1:4175/preview/golem-gameplay/?palette_test=1) — пять настоящих Golem с HP 120/240/480/960/1920 на существующем маршруте. Просмотр начинается на паузе.
- [Принятые animations](GOLEM_ANIMATION_REVIEW.md), [SVG art](GOLEM_ART_REVIEW.md), [план](GOLEM_ART_PLAN.md).

## Изменения

В `scenes/golem.tscn` через Godot MCP добавлен экземпляр GolemVisual. Старый Sprite2D Visual и `assets/golem.svg` сохранены. HealthBar/SlowIndicator и origin существующей entity не менялись; HealthBar находится выше головы. Масштаб visual 140/256, масштаб клетки остаётся в прежнем follow_route. Balance Golem: HP 120, скорость 80, урон башне 20, мана за убийство 8 — без изменений. Формулы волн/роста HP, target selection и свойства союзников не менялись.

ApproachingEnemy получает только дополнительную ссылку GolemVisual, реализующую тот же контракт, что Goblin/Orc. Движение и время контакта остаются в gameplay. За последние 0.20 s до контакта visual готовит оба кулака через seek без method events. В исходном contact frame устанавливается impact 0.20 s и выполняется прежний однократный outcome. Подготовка учитывает slow; hit не задерживает движение/контакт и не прерывает подготовку.

При убийстве entity сразу исключается из целей и волны, награда выдаётся прежним обработчиком. Только visual переносится в World и заканчивает death 0.35 s; при контакте заканчивает recovery. Visual tail освобождается и очищается при остановке боя/рестарте через существующую группу enemy_visual_tails. Новая система lifecycle/VFX не создавалась.

`art/source/golem/moss_palette.gdshader` выделяет зелёные fills внутри общего moss_mask.svg. Один local-to-scene material назначен всем восьми частям каждого Golem; материалы экземпляров независимы, textures общие. Камень, жёлтые глаза и outline сохраняют цвета. Пороги и palette берутся из существующего EnemyStats: 120/240/480/960/1920, зелёный/оранжевый/красный/синий/фиолетовый. Hit flash по-прежнему кратковременно применяется ко всей фигуре; это отдельный эффект получения урона.

Development-only GolemGameplayReview наследует существующую сцену review и вызывает настоящий GameManager/WaveManager, summon/projectile logic. Seed поля 101, seed summon 23. Параметры load_test/palette_test создают только временные тестовые экземпляры; исходные Resources и сохранения не изменяют. После финальной приёмки обычная gameplay сцена выбирает animated Golem. В debug review Golem включается ANIMATED для проверки, STATIC остаётся доступен.

## Проверки

- MCP: нужный проект, Godot 4.7.2, Compatibility; перед сценовыми изменениями unsaved=[]. Импорт Shader/SVG и final scene connections проверены. При первоначальной смене script у наследника потерялось поле config; оно восстановлено на существующий first_encounter Resource, повторный запуск прошёл. Последние native запуски без ошибок scripts/runtime.
- Native сравнение STATIC/ANIMATED по одной Curve2D длиной 480: контакт на кадре 360 в обоих вариантах; с slow 50% на 1.513 s — на кадре 405 в обоих. Расстояние 480, HP после двух попаданий 118, outcome один, targetable=false. Animated выдаёт один impact, visual_frame=0.20 s. Повторный contact не повторяет событие.
- Повторные lethal damage/contact: outcome KILLED один, targetable=false. Death tail после advance 0.4 s поставлен на удаление. Проверена независимость moss_material у экземпляров HP 120 и 1920.
- GPU-проверка всех восьми частей в пяти цветах: камень/глаза/outline не изменились (stone_eyes_outline_changed=0), участки мха изменяются. Посмотрены пять настоящих Golem одновременно. Маска работает на всех частях, включая Head.
- Небольшая регрессия общего ApproachingEnemy: прежняя Orc parity проверка прошла, контакты 239/285 кадров совпадают для STATIC/ANIMATED, impact остаётся 0.18 s, смерть/outcome и материалы корректны. Goblin и все три союзника также присутствовали в Web review; полный набор старых сценариев не повторялся.
- Один завершённый целевой Web pass в Edge: мышь/touch STATIC↔ANIMATED; Pause сохраняет positions/visual frames; Archer/Mage/Frost Mage призываются через башню; drag/refund работают. Настоящие Frost/Mage projectiles замедлили, вызвали hit и убили Golem. За убийство kill count=1, мана 12→20 (+8), виден один death tail. Проверка использует изолированный штатный Golem, чтобы другие враги смешанной волны не завершали забег раньше целевого события.
- Отдельная часть того же Web pass: пять Golem без защитников достигли башни, каждый с impact=true/frame=0.20 s, route_remaining=0 и targetable=false. Game Over, tails=0 после завершения, Restart: mana=100, kills=0, projectiles=0, tails=0. Просмотрены 450×800, 390×844 и 1280×720; console/page/resource errors=[].
- После добавления palette_test повторно экспортирован только debug preview и проверен новый режим: tiers 1–5, HP 120/240/480/960/1920, animated=true, paused=true, browser errors=[]. Полный gameplay pass не повторялся ради этой debug-only добавки.
- Временные main scene/export preset восстановлены точно: project.godot/export_presets.cfg без diff; Web single-thread, без extensions. Основной main scene остаётся MainMenu. SVG/Shader imports и `.uid` сохранены, build/helpers исключены из Git.

## Производительность и ограничения

Восьми общим RGBA8 textures 256×256 и маске требуется примерно 2.25 MiB без mipmaps. Девять bones/один AnimationPlayer на Golem; levels используют тот же набор textures.

Короткий desktop Edge замер на текущем компьютере, 40 Golem одновременно: **ANIMATED ≈72 FPS / 443 draw calls**, **STATIC ≈144 FPS / 163 draw calls**. Animation повышает стоимость рендера; этот стрессовый состав существенно больше доли Golem в ранних штатных волнах. RAF браузера ~6.94 ms в обоих вариантах не заменяет измерение фактического FPS игры. Это не гарантия для мобильного устройства; физический телефон не тестировался. Более крупные массы/поздние волны пока не измерены. Mesh и дополнительные эффекты не вводились.

## Финальная ручная приёмка

1. В бою принять размер Golem рядом с уменьшенным Goblin/Orc, ходьбу на поворотах, положение HP bar и slow indicator.
2. Проверить удар двумя руками у башни, hit/death от настоящих снарядов и отсутствие оставшихся фигур после рестарта.
3. Открыть ссылку пяти цветов: принять окраску только мха при сохранении камня/глаз. Сравнить STATIC/ANIMATED и Pause.

Golem полностью принят. Animated default включён; короткий native запуск подтвердил animated_visible=true, static_visible=false, HP=120 и speed=80, ошибок runtime нет. Основная Web-сборка экспортирована заново, main scene остаётся MainMenu. Длительные gameplay проверки ради приёмки не повторялись. Отчёты перенесены в docs/done, ссылки обновлены для отдельного commit. Push только по отдельному разрешению. Boss и Tower art не начинались.
