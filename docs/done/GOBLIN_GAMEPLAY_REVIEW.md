# Goblin — gameplay integration и финальная приёмка

## Принятая правка походки 07.10.2026

По дополнительной просьбе пользователя усилены только три вращательных трека walk_loop: Head локально ±8° (в мире ±7°), FrontArm ±18°, Dagger ±5° (кинжал в мире ±24°). Раньше локальное движение головы компенсировало наклон Body, поэтому голова выглядела неподвижной. Длительность цикла осталась 0.64 s; движение entity, скорость, HP и attack/hit/death сохранены.

Крайние позы просмотрены через Godot MCP: явных щелей нет. В Edge подтверждено движение областей головы и руки с кинжалом; pause останавливает изображение, browser errors=[]. [Просмотр](http://127.0.0.1:4175/preview/goblin-animation/). Пользователь принял правку; она фиксируется отдельно от Frost Mage. Push не разрешён.

07.10.2026. **Goblin полностью принят пользователем**, включая art, rig/animations, gameplay integration и исправленную окраску одежды. Animated visual включён по умолчанию в обычной игре; static fallback сохранён. Объект фиксируется отдельным commit `art: add animated goblin`. Push требует отдельного разрешения.

## Просмотр

[Goblin gameplay preview](http://127.0.0.1:4175/preview/goblin-gameplay/) — отдельный Godot Web export реальной игры с текущей процедурной ареной. Внизу Goblin ANIMATED / STATIC и иконка Pause/Resume. Seed призыва 23 даёт сначала Archer, Mage и Frost Mage; веса пула, стоимость и характеристики прежние. Сетка/маршрут остаются обычными случайными. Для проверки slow можно передвинуть Frost ближе к спавну, чтобы врагов не успевали убивать другие бойцы до его попадания.

Сцена `scenes/debug/GoblinGameplayReview.tscn` — настоящий наследник `scenes/game.tscn`. Development UI, read-only browser snapshot и отдельный query load_test исключены из обычного export preset. Основная main scene — main_menu. После приёмки ordinary Web build обновлена с animated Goblin по умолчанию; переключение STATIC / ANIMATED остаётся в review. Debug fixture допускает как процедурную дорогу текущего рабочего проекта, так и исходный прямой маршрут.

## Что изменено

- В `scenes/enemy.tscn` добавлен GoblinVisual рядом со старым Sprite2D Visual; прежний assets/enemy.svg сохранён. Optional animated_visual_enabled работает только при наличии GoblinVisual. Orc, Golem и Boss используют свои прежние visuals.
- ApproachingEnemy продолжает считать движение, HP, slow и outcome. GoblinVisual только меняет позу/цвет. Прежние 30 HP, скорость 160, tower damage 20, kill mana 3, формулы волн/здоровья, выбор целей и снаряды не менялись.
- В gameplay AnimationPlayer работает в manual mode. Walk сопровождает прежнее движение; horizontal facing меняется только у visual. Hit не перезапускается от каждого попадания и не перебивает начавшийся contact windup. Lethal hit сразу выбирает death.
- Windup использует оставшееся время пути, включая остаток slow и его истечение. Seek задаёт только pose, без раннего method event. В прежний contact frame pose переводится на impact 0.16 s, visual signal выдаётся один раз, затем выполняется прежний REACHED_TOWER. Движение не ждёт анимацию.
- При KILLED/REACHED_TOWER entity сразу перестаёт быть целью, удаляется из active wave и выдаёт прежний resolved один раз. Только GoblinVisual переносится к World с сохранением transform и заканчивает death 0.32 s либо recovery 0.18 s; затем queue_free. Он не участвует в поиске целей/волне и не выдаёт damage/reward. Game Over удаляет все такие tails; restart/смена сцены освобождают старую World.
- По последней правке пользователя цвет сложности перенесён с кожи на ботинки, напульсники и набедренную повязку. equipment_palette.gdshader использует общую SVG-маску 256×256 и исходные коричневые fills этих областей; материал назначен пяти частям, Head и Dagger без него. Кожа всегда зелёная; плечевой ремень, наплечник, внутренние уши, outline, глаза, клык и кинжал сохраняют исходные цвета. Один локальный материал на экземпляр, общий между его частями. Пороги max HP прежние: 30–59 зелёная одежда, 60–119 оранжевая, 120–239 красная, 240–479 синяя, 480+ фиолетовая.

## Проверки

- Godot MCP: правильный проект C:/Gamedis/summoner-tower, Godot 4.7.2-stable official, Compatibility. Сцены/nodes/material созданы через MCP, код/shader через apply_patch.
- Lint: 37 сцен и 56 скриптов, errors=0 и warnings=0. Короткие native запуски и runtime inspection; обнаруженная при создании inherited review потеря config исправлена до передачи результата.
- Native palette: все пять порогов и screenshot кожи, параметры shader по EnemyStats, разные материалы двух экземпляров и один общий материал внутри каждого. Попадания не уменьшают difficulty tier.
- Native движение: одинаковый маршрут, позиция и срок slow у STATIC и ANIMATED, включая кадр истечения. Hit возвращается в walk и не застревает от повторного попадания.
- Native contact: pose windup до контакта, hit во время windup, новое slow отменяет/пересчитывает подготовку, далее удар на прежнем frame. Повторный resolve заблокирован, tail сохраняет global transform. На настоящем active wave enemy урон башне один раз −20, mana при escape не меняется, active count уменьшается один раз, targetable=false. Kill выдаёт ровно +3 mana, death tail удаляется; stop очищает tails.
- Однократно выполнены три существующих сценария: feature_8_enemy_contracts (цвета, квоты, boss, награды), feature_7_unit_contracts (Frost/projectile lifecycle и операции юнитов), feature_10_results_and_wallet (новый boss spawn, статистика, награды, restart/menu). Все passed, runtime errors отсутствуют. Полный набор не повторялся: изменение ограничено optional enemy visual и cleanup при остановке.
- Godot Web export через MCP: Compatibility, single-thread, без native extensions; preset и main scene восстановлены после экспорта.
- Edge Web: mouse/touch ANIMATED/STATIC, Pause фиксирует одновременно движение и время animation, реальные снаряды Frost/Mage, slow, hit и death tail, перенос/refund бойцов, contact impact ровно на 0.16 s при нулевом остатке пути, результат и restart. После stop tails=0; после restart kills=0, mana=100, projectiles=0, новые Goblin animated. Browser console/page/resource errors=[].
- Screenshots просмотрены при 450×800, 390×844 и 1280×720: бой, short death, результат, restart, portrait и широкое окно. Физический телефон не проверялся.

Начальные browser setup-попытки не показывали slow/death, потому что расположенные раньше стрелок/маг убивали врагов до Frost, либо один Frost распределял попадания между входящими целями. Проверка выполнена с Frost у начала дороги и затем соседним Mage, через обычные summon/move/refund, без изменения HP/damage/скоростей.

## Производительность

Замеры ниже выполнены до последней цветовой правки. Она добавляет одну общую mask texture 256×256 (~0.25 MiB RGBA8), без новых bones/Sprite2D/материалов на экземпляр. Общий набор textures Goblin теперь около 2 MiB; приведённые FPS после этого повторно не измерялись, поскольку исправление ограничено палитрой.

40 одновременно движущихся Goblin на обычном маршруте, пустые summon slots. Development fixture размещает их на первой четверти дороги для короткого сравнения нагрузки; это отдельный тест, не новая формула волны.

| Среда | ANIMATED | STATIC |
|---|---|---|
| Godot native, 1 s sample | ~145 кадров, avg 6.90 ms; 355 draw calls | ~145 кадров, avg 6.90 ms; 154 draw calls |
| Edge Web, после 1.1 s warmup, 180 RAF intervals | Godot FPS 144; 354 draw calls; RAF avg 6.945 ms, max 7.1 ms | Godot FPS 144; 153 draw calls; RAF avg 6.945 ms, max 7.1 ms |

Это короткие замеры на текущем desktop, с ограничением частоты экрана; они не показывают максимальную пропускную способность и не гарантируют FPS на телефоне. RAF interval — показатель browser presentation, не отдельный CPU time Godot. Первый Web sample включал запуск (FPS 33), поэтому для вывода использован повторный короткий load-only sample после warmup; полный бой не повторялся ради FPS.

Цена rig заметна по draw calls: рост примерно на 200 для 40 enemies. При текущей нагрузке замер не показал падения FPS, поэтому mesh/pooling/новые оптимизации не вводились. Общие 7 textures 256×256 ~1.75 MiB RGBA8 без учёта служебных копий, один набор для всех уровней; 8 bones и один AnimationPlayer на Goblin. Для больших поздних волн и слабых мобильных устройств нужна отдельная проверка по конкретному риску.

## Ручная финальная приёмка

Последняя цветовая правка проверена отдельно в Godot: пять цветов рядом, кожа остаётся зелёной; GPU-render сравнение всех пяти частей показывает 0 изменённых пикселей кожи и 0 изменений вне маски. На body изменилось 1130 пикселей одежды, arm_back 354, arm_front 322, leg_left 325, leg_right 259. Проверены импорт маски, shader parameters и runtime errors; обновлён Web preview и выполнен короткий Edge запуск без console/page errors. [Сравнение пяти цветов](http://127.0.0.1:4175/preview/goblin-gameplay/colors.png). Повтор полного игрового цикла для этой визуальной правки не требовался.

1. Посмотреть Goblin в обычном бою и сравнить ANIMATED / STATIC: размер, силуэт, ходьба и повороты.
2. Призвать бойцов, приблизить Frost к спавну: принять hit/slow/death и читаемость снарядов.
3. Дать врагам достигнуть башни: принять короткий замах/удар без остановки движения; урон остаётся прежним.
4. Проверить Pause/Resume и restart после поражения: старые enemies, visuals и projectiles не остаются.

Финальная приёмка получена. Native запуск обычной game scene после включения default подтвердил animated=true, видимый GoblinVisual и отсутствие материала на Head; новых runtime errors нет. Ordinary Web build обновлена; короткий Edge запуск из меню в бой прошёл без console/page/resource errors, screenshot просмотрен. Legacy art остаётся. Следующий asset — Mage, сначала отдельное обсуждение и согласование плана; art не начинается автоматически. Push только по отдельному разрешению.
