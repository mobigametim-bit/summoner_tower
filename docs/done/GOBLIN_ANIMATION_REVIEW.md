# Goblin — rig и animation review

07.10.2026. **Goblin полностью принят пользователем.** Этот отчёт сохраняет результаты animation gate, выполненного после приёмки SVG art и исправления носа. Последующая gameplay integration и окраска только одежды приняты; итог описан отдельно в [GOBLIN_GAMEPLAY_REVIEW.md](GOBLIN_GAMEPLAY_REVIEW.md).

## Результат

[Браузерный Goblin preview](http://127.0.0.1:4175/preview/goblin-animation/) — отдельный Godot Web export. Верхняя строка переключает Archer/Goblin, вторая — animation. Иконки Replay/Pause, 0.5×/1×/2×, Repeat, Mirror и выбор масштаба; внизу одновременно видны три игровых размера для сеток 6/7/8 столбцов. Goblin показан на существующем тайле дороги, Archer — на постаменте.

Сцены и AnimationPlayer созданы через Godot MCP. SVG art сохранён без изменений; gameplay scenes/scripts и статичный enemy.svg не менялись.

- `scenes/visuals/GoblinVisual.tscn`: Node2D → Skeleton2D → Root → Body → Head, BackArm, FrontArm/Dagger, LeftLeg, RightLeg; AnimationPlayer отдельно.
- 7 SVG textures 256×256, 8 Bone2D с явными rest transforms. Sprite2D centered=false, position=−pivot, порядок слоёв соответствует manifest. Scale visual 108/256; sample scale соответствует текущему enemy scale min((cell_size−12)/140,1).
- `scripts/visuals/goblin_visual.gd`: только управление позой и визуальные события; не создаёт enemies, не выбирает цели, не двигает gameplay entity и не наносит урон.
- `scenes/debug/ArtAnimationTest.tscn` расширена двумя принимаемыми assets. `GoblinAnimationTest.tscn` — её настоящая наследуемая сцена с initial_asset_index=1. Скрытые экземпляры остановлены на паузе.

| Animation | Длительность | Поведение |
|---|---:|---|
| walk_loop | 0.64 s, loop | Короткие шаги, лёгкий bob/движение головы и оружия; Root position постоянна |
| attack | 0.34 s | Замах, короткий удар, recovery; visual attack_impact один раз на 0.16 s |
| hit | 0.16 s | Короткий recoil, punch и тёплый tint; затем walk_loop |
| death | 0.32 s | Оседание с наклоном и fade; финальная невидимая поза удерживается |

RESET — техническая pose анимация; Replay восстанавливает положение, scale, alpha и все анимируемые кости. Attack/hit возвращаются в walk_loop. Death не запускает ходьбу самопроизвольно.

Impact пока является только visual signal. Согласованная синхронизация с прежним моментом damage при достижении башни будет реализована и проверена на gameplay gate; здесь урон не подключён.

## Выполненные проверки

- Godot MCP: правильный проект, Godot 4.7.2-stable, Compatibility; сохранённые сцены без несохранённых правок. Все восемь rest determinant=1, все семь textures 256×256.
- Lint сцен/скриптов: 36 сцен, 55 скриптов; после исправлений errors=0, warnings=0. Короткий native запуск и runtime inspection через MCP.
- Visual inspection: крайний замах 0.14 s, удар 0.22 s, walk, hit/death, mirror, три малых игровых размера; явных дыр, обрезания частей или потерянного хвата не обнаружено.
- Native targeted checks: impact отсутствует до 0.16 s, ровно один после, защищён от повторного вызова при 0.5×/1×/2×. Прерывание attack через hit до impact не выдаёт событие; hit возвращается к walk. Death удерживает alpha=0; Resume не перезапускает законченную death. Replay возвращает alpha=1, Root position/scale. Pause фиксирует время AnimationPlayer.
- Selector: четыре активных preview, скрытые Goblin на паузе при переключении на Archer. Archer attack по-прежнему выдаёт release на 0.24 s. Mirror проверен по направлению transform, включая все samples.
- Godot Web export через MCP: debug, Compatibility, single-thread, без native extensions. Временные main scene/exclude filter после экспорта восстановлены к обычному main_menu и production preset; обычная game build не заменялась.
- Edge Web: walk/attack/hit/death, Replay после death, reset, 0.5×/1×/2×, Pause/Resume, touch Mirror, selector Archer/Goblin. Две картинки после Pause идентичны. Окна 450×800, 390×844, 1280×720; просмотрены screenshots, UI доступен, portrait composition сохранена. Ошибок browser console/page/resource loading не обнаружено.
- На финальном native запуске нет новых runtime errors. Первоначальные ошибки сборки preview и проверки исправлены до передачи результата.

Проверки были целевыми для visual/test scene; полный набор gameplay scenarios не запускался, поскольку gameplay код не изменялся.

## HTML5 и ограничения

На один Goblin: 8 костей, 7 Sprite2D, один AnimationPlayer. Семь общих textures 256×256 занимают около 1.75 MiB в несжатом RGBA8, без учёта возможных дополнительных копий и служебных данных; экземпляры используют те же textures. Новых материалов/mesh/IK нет. Это оценка ресурса, не измерение полной памяти Web runtime.

На animation gate проверены четыре одновременных Goblin; массовый тест, материалы и синхронизация gameplay проверены позже и описаны в gameplay отчёте. По окончательному решению пользователя max HP меняет только одежду; кожа сохраняет зелёный цвет. Legacy art сохранён. Push только по отдельному разрешению.

## Ручная приёмка

1. Оценить walk на 1×, крупно и в трёх нижних samples: движение спокойное, ноги читаются.
2. Переключить attack, выбрать 0.5× и Repeat: принять замах/удар, хват кинжала и суставы; проверить Mirror.
3. Проверить hit и death на 1×. Для death отключить Repeat, дождаться исчезновения, нажать Replay.
4. Проверить Pause/Resume, смену скорости и размера. После смены animation не должно оставаться fade/scale предыдущей.

Animation gate и последующий gameplay gate приняты. [План Goblin](GOBLIN_ART_PLAN.md) сохраняет согласованные решения; отдельный commit закрывает объект. Mage проходит новое согласование плана до создания art.
