# Summoner Tower — приёмка анимаций

08.10.2026. Tower полностью принят пользователем. Этот отчёт описывает проверку TowerVisual до интеграции. GAMEPLAY также принят, animated default включён: [отчёт](TOWER_GAMEPLAY_REVIEW.md), [обычная игра](http://127.0.0.1:4175/).

[Посмотреть в браузере](http://127.0.0.1:4175/preview/tower-animation/) · [план](TOWER_ART_PLAN.md) · [принятый SVG art](TOWER_ART_REVIEW.md).

## Visual

`scenes/visuals/TowerVisual.tscn`: Node2D, Base Sprite2D, CrystalPivot/Crystal, BodyPivot/Body, один AnimationPlayer. Три принятые SVG parts256×256, 0 bones, без Skeleton2D, mesh, IK, shader, CanvasGroup и новых particles. Цена, contact point и ввод не входят в visual.

Base неподвижен; crystal за золотой оправой Body. Origin(128,128); crystal pivot=(0,−33), body pivot=(0,31.9) относительно origin. RESET фиксирует все изменяемые позиции, scale, rotation и self_modulate. Root scale / mirror не анимируются. Все части остаются непрозрачными, overlap не проявляется через fade.

| Animation | Длина | Поведение |
| --- | --- | --- |
| crystal_pulse | 1.6s loop | Кристалл слегка увеличивается до1.03× и светлеет; корпус неподвижен |
| tap | 0.16s | Короткое сжатие / восстановление корпуса и небольшая вспышка кристалла |
| refund | 0.26s | Кристалл сжимается до0.84×, затем расширяется до1.05× и даёт более сильную cyan вспышку |
| hit | 0.18s | Короткий recoil / наклон корпуса и вспышка; Base не двигается |
| destroyed | 0.45s | Кристалл гаснет, корпус немного оседает и наклоняется; тёмная финальная поза удерживается |

`scripts/visuals/tower_visual.gd` управляет только visual. Подготовлены входы show_tap / show_refund / show_hit / show_destroyed. Destroyed отменяет реакции и блокирует следующие; hit приоритетнее refund и tap. Хранится максимум одна ожидающая реакция, refund выигрывает у tap. Review / initialize через play_animation полностью восстанавливают позу, включая destroyed. HP, mana, цены и игровые операции контроллер не изменяет.

## Просмотр

Tower добавлен восьмым asset в общий `scenes/debug/ArtAnimationTest.tscn`. `scenes/debug/TowerAnimationTest.tscn` наследует его и сразу выбирает Tower. Сохранены Previous / Next Asset, Previous / Next Animation, Replay, Pause,0.5×/1×/2×, Repeat, Mirror и выбор масштаба.

Large preview: canvas320 логических px. Игровые примеры:108 /92 /80 px при сетке6 /7 /8 столбцов. У Tower дорожная клетка без постамента и смещения союзника. В footer указано0 bones, вместо release / impact — Visual only. В review нет цены: перенос CostLabel выполняется при внедрении.

## Выполненные проверки

- Godot MCP подтвердил нужный проект и Godot4.7.2 / Compatibility, несохранённых сцен не было. Сцена, узлы, signal connections и Animation resources созданы через MCP; `.tscn` вручную не редактировались.
- Language server: оба изменённых скрипта без errors / warnings. Native запуск TowerAnimationTest и runtime inspection — ошибок нет.
- Через MCP проверены начальные / промежуточные / финальные позы всех пяти клипов. Base position / scale стабильны; extreme tap, refund и destroyed просмотрены визуально. Видимых дыр и обрезанного кристалла не обнаружено.
-0.5× /1× /2× дают одну и ту же позу при одинаковом времени внутри клипа. Pause фиксирует видимые анимации. После destroyed башня остаётся в сцене и удерживает тёмную позу; Replay восстанавливает исходные цвета, scale, rotation и позиции.
- Проверена цепочка hit → tap → refund → tap: ожидает только refund; после hit выполняется refund, затем crystal_pulse. Destroyed отменяет ожидающий refund; последующие tap / refund / hit не снимают разрушенную позу. Полный reset восстанавливает исходный visual.
- Godot Web export single-thread release создан через MCP. Пять clips, Pause / Replay, скорости0.5×/1×/2×, mouse controls, touch Mirror и цикл выбора всех восьми assets проверены в Edge. JS / HTTP errors отсутствуют.
- Выбор6 /7 /8 columns проверен отдельным коротким прогоном: в первом браузерном сценарии клавиатура оставила dropdown открытым, поэтому завершена только эта непроверенная часть мышью. Полный прогон не повторялся. Масштаб и UI просмотрены при450×800,390×844 и1280×720, боковые поля корректны.
- Основная сцена и обычный Web preset после временного review export восстановлены; project.godot / export_presets.cfg не имеют diff. Сборка лежит в игнорируемом build. Старый art и текущий TowerHealth сохранены; commit / push не выполнялись.

Performance боя ещё не измерялась: это следующий GAMEPLAY gate. Pipeline башни —3 texture /3 Sprite2D /1 AnimationPlayer /0 bones; textures общие для экземпляров, около0.75 MiB RGBA8 без mipmaps. Review содержит скрытые visuals остальных assets и не является репрезентативной нагрузкой боя.

## Следующее внедрение после приёмки

Подключить visual к существующему TowerHealth и успешному unit_refunded, сохранив текущие кадры урона / призыва / начисления маны / Game Over. Сохранить static fallback. Отдельное уточнение пользователя: цифру призыва придвинуть вплотную к нижнему краю башни; привязать к неподвижному Base, оставить выше art и проверить реальные font metrics в Godot при6/7/8 columns. В текущем ANIMATION gate gameplay UI не менялся.

## Ручная приёмка

1. На1× посмотреть все пять клипов; сравнить tap и refund.
2. Проверить0.5×, Pause, Replay и Mirror: пересечения частей должны оставаться аккуратными.
3. Посмотреть6/7/8 columns и маленькие примеры снизу: силуэт и реакции должны читаться.
4. Проверить destroyed и Replay после него. Принять анимации либо указать правки.

ANIMATION и GAMEPLAY приняты. Документы архивированы в docs/done; отдельный commit Tower. Push только по отдельному разрешению.
