# Boss — gameplay review

08.10.2026. **Boss полностью принят пользователем:** «принимаю, дальше». Rigid cutout visual интегрирован, animated default включён, все четыре отчёта архивированы в docs/done. Отдельный локальный commit завершает Boss; push без отдельного разрешения не выполнять. Tower ещё не производится.

[Проверить Boss в реальном бою](http://127.0.0.1:4175/preview/boss-gameplay/). Это отдельная development-сборка: настоящий бой начинается с волны 5, доступны STATIC / ANIMATED и Pause. В [обычной игре](http://127.0.0.1:4175/) Boss теперь animated по умолчанию; main_menu сохранён. [План](BOSS_ART_PLAN.md), [art](BOSS_ART_REVIEW.md), [animations](BOSS_ANIMATION_REVIEW.md).

## Интеграция

- Через Godot MCP в `scenes/boss.tscn` добавлен экземпляр BossVisual, прежний Sprite2D Visual и assets/boss.svg сохранены. HealthBar поднят над короной: top=−113, bottom=−86, прежняя ширина и высота сохранены. Gameplay origin, SlowIndicator и маршрут не менялись.
- ApproachingEnemy получил только ссылку BossVisual и включение его в существующий общий visual contract; движение, slow, targeting, contact, outcomes и награды остаются в прежней gameplay logic.
- BossVisual в бою использует manual AnimationPlayer. Intro однократный и не задерживает движение / targetability; повторное enable из ready/configure его не перезапускает. Переключение STATIC→ANIMATED у существующего Boss возвращает walk, не повторяет intro.
- Mirroring следует направлению движения, scale=166/256. Подготовка удара занимает оставшееся до прежнего contact время; seek не вызывает событие заранее. На contact вызывается impact ровно на 0.22 s, после чего выполняется прежний outcome / 50 damage.
- Hit не прерывает подготовку contact. Intro можно прервать hit, attack или death без задержки gameplay. Boss сохраняет фиксированную палитру при любом HP.
- После outcome остаётся только visual tail, без targetability и участия в active enemies; death / recovery удаляет его. Общая очистка на stop / restart сохранена. При upgrade choice tail ставится на паузу вместе с боем и завершает fade после выбора.
- `scenes/debug/BossGameplayReview.tscn` — inherited review scene, seed=101, старт настоящей волны 5. `scripts/debug/boss_gameplay_review.gd` содержит только review toggle/snapshots и изолированную fixture `?load_test=1/2`. Fixture использует существующий BossScene / stats / route и не меняет ресурсы баланса.

Не менялись base HP=350, speed=70, tower_damage=50, kill_mana=30, рост Boss HP +250, обычные враги, wave logic, damage/cooldowns союзников, цены, merge или meta progression. На волне 5 Boss остаётся дополнительным и появляется в начале вместе с первым обычным врагом.

## Godot MCP — целевые проверки

- Подтверждены нужный проект C:/Gamedis/summoner-tower, Godot 4.7.2 / Compatibility, отсутствие несохранённых сцен. Scene / nodes / runtime / запуск / export выполнены через Godot MCP.
- Настоящий старт волны 5: Boss HP350 и Goblin HP50 активны одновременно, pending=11, всего 13 врагов — 12 обычных +1 Boss.
- Паритет на маршруте 480 px, 60 physics steps/s: STATIC и ANIMATED достигают башни на **кадре 411**, дистанция 480, HP348 после двух одинаковых попаданий. С slow 50% на 1.513 s — оба на **кадре 456**. Движение и время контакта совпадают.
- Animated contact вызывает один impact на 0.22 s; повторный resolve не выдаёт второе событие, враг больше не targetable. Static contact не вызывает visual event.
- Повторные lethal damage / contact дают ровно один KILLED outcome. Visual tail удаляется после завершения death 0.45 s.
- При intro enemy продолжает двигаться: за 1/60 s проходит 70/60≈1.1667 px. Повторный enable сохраняет текущий intro frame 0.05 s.
- На свежем реальном GameManager изолированный Boss: mana100→130, boss_kills0→1, state=UPGRADE_CHOICE, tail=1, targetable=false. Повторное повреждение / contact не дублирует награду. Выбор улучшения возвращает RUNNING, unpaused, INTERMISSION.
- После исправлений временных команд inspection финальные runtime errors отсутствуют. Native запуск остановлен.

## Web — один совмещённый прогон

Edge, Compatibility, single-thread / без extensions. Playwright использовал отдельный временный browser context; обычное браузерное сохранение игрока не использовалось. Проверки выполнялись в одной последовательности, без полного повторного прогона прежних features.

1. Проверен настоящий состав волны 5: Boss + обычный враг сразу, active+pending=13.
2. STATIC / ANIMATED проверены мышью и touch. Pause останавливает movement и visual frame. Проверены реальный summon через Tower, переносы юнитов и возврат маны.
3. Существующие Mage / Frost Mage и projectiles убили Boss с базовыми HP350: наблюдались slow, hit и death tail. Mana перед убийством12, после42, kills=1, boss_kills=1, враг не targetable. Окно улучшения открылось, выбор через обычный UI продолжил бой; через 0.65 s tails=0.
4. Просмотрены 450×800, 390×844 и 1280×720; HUD / арена / review controls сохраняют композицию. Физический телефон не проверялся.
5. Два Boss из review fixture достигли башни, каждый с исходным damage50: HP100→0, mana остаётся100, boss_kills=0. Оба contact outcome имеют impact=true / frame0.22 / remaining route0 / targetable=false. После Game Over active=0 и tails=0.
6. Restart через обычный UI: RUNNING, mana100, kills0, boss_kills0, projectiles0, tails0. Новый Boss появляется как новый экземпляр.

Console / page / resource errors отсутствуют. Просмотрены screenshots начала волны, static fallback, выбора улучшения после смерти, phone/wide, результата и restart. После изменений игрового кода потребовался один Web export review; обычная Web игра не пересобиралась, а приёмка документов не потребовала повторных тестов.

## Производительность и ограничения

Замер одной Boss entity на существующей арене без защитников / остальных врагов:

| Режим | Active Boss | Godot FPS | Draw calls |
|---|---:|---:|---:|
| ANIMATED | 1 | 144 | 54 |
| STATIC | 1 | 144 | 46 |

Разница +8 draw calls включает accepted cutout и CanvasGroup. В этой проверке FPS не снизился; это измерение конкретного desktop Web preview, не обещание для слабого телефона или поздних массовых волн. Искусственная нагрузка десятками Boss не запускалась: обычный gameplay добавляет одного на каждой пятой волне. При реальном боевом тесте присутствовали союзники, снаряды и slow; ошибок не наблюдалось.

Для Boss нужны 8 общих textures 256×256 ≈2 MiB RGBA8 без mipmaps, 9 bones, один AnimationPlayer. CanvasGroup используется только его visual, fade не раскрывает скрытые overlap. Mesh deformation не требуется для согласованного силуэта / анимаций.

После первоначальной gameplay review временный preset удалён, project.godot и export_presets.cfg восстановлены побайтно; main scene=main_menu. После финальной приёмки обычный Web build обновлён через MCP. Короткий native check подтвердил animated default=true, static_visible=false, animated_visible=true, однократное intro, HP350 / speed70 / damage50; runtime errors отсутствуют. Длительный gameplay-прогон не повторялся: менялся только default сцены. Пользовательские процедурные изменения в рабочем дереве сохранены и не включаются в commit Boss.

## Финальная ручная приёмка

1. Открыть review и призывать / перемещать защитников: Boss должен появиться из портала с обычным врагом, заметно шагать и покачивать голову / кулаки.
2. Проверить slow и попадания, короткую смерть; принять окно улучшения и продолжить бой. Рисунок не должен менять всю палитру от увеличенного HP или просвечивать в стыках.
3. Дать Boss дойти до башни: удар двумя руками и потеря 50 HP совпадают. В конце забега проверить Restart.
4. Сравнить STATIC / ANIMATED. Финальная приёмка получена: animated default включён, отчёты перенесены в docs/done, Boss фиксируется отдельным commit. Следующий asset — Tower, только после согласования нового плана. Push требует отдельного разрешения по master art prompt.
