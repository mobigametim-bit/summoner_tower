# Boss — SVG art review

08.10.2026. Boss полностью принят пользователем, animated default включён, отчёты архивированы. Ниже сохранены результаты SVG art gate. [План](BOSS_ART_PLAN.md), [анимации](BOSS_ANIMATION_REVIEW.md), [итог gameplay](BOSS_GAMEPLAY_REVIEW.md). Push требует отдельного разрешения.

## Результат

[Открыть просмотр](http://127.0.0.1:4175/preview/boss-art/), [исходный master.svg](../../art/source/boss/master.svg), [координаты частей](../../art/source/boss/rig_manifest.json).

Boss отрисован вручную как SVG-код по существующему assets/boss.svg и стилю принятых cutout персонажей: коронованный фиолетовый громила, массивные кулаки, короткие ноги, золотые наплечники, два коротких клыка. Без image generators, внешних sprites и новых сущностей. Цвет фиксированный; HP не перекрашивает Boss. Нос расположен в центре лица, между глазами и ниже них.

Source — `art/source/boss/`: master.svg, восемь SVG parts, rig_manifest.json, README.md и review.html. Master состоит из тех же групп, что отдельные части; 51 простой path, плоские заливки, толстый outline #29180f / 7 px. Все parts — прозрачные 256×256 без trimming. Корона/лицо/клыки внутри Head; кулаки внутри forearms; наплечники внутри upper arms.

## Координаты для будущего rig

Origin=(128,128), baseline≈239, будущий scale=166/256=0.6484375. Девять костей с Root, без mesh / IK / weights / root motion. Эти параметры зафиксированы для следующего этапа, rig пока не создан.

| Part / bone | Parent | Canvas pivot | Bone local position | Z |
|---|---|---|---|---:|
| arm_back_upper / BackUpperArm | Body | (75,124) | (−53,−47) | 0 |
| arm_back_forearm / BackForearm | BackUpperArm | (45,158) | (−30,34) | 1 |
| leg_left / LeftLeg | Body | (101,201) | (−27,30) | 2 |
| leg_right / RightLeg | Body | (151,201) | (23,30) | 3 |
| body / Body | Root | (128,171) | (128,171) | 4 |
| arm_front_upper / FrontUpperArm | Body | (181,125) | (53,−46) | 5 |
| arm_front_forearm / FrontForearm | FrontUpperArm | (211,158) | (30,33) | 6 |
| head / Head | Body | (132,143) | (4,−28) | 7 |

Root.position=−origin; Sprite2D.centered=false и position=−pivot; z_as_relative=false; rest каждой кости равен исходному transform. Скрытые округлые участки плеч, локтей, шеи и бёдер дорисованы с overlap. Отсутствие дыр в движении проверяется на следующем gate.

## Выполненные проверки

- Godot MCP: подключён нужный проект C:/Gamedis/summoner-tower, Godot 4.7.2, Compatibility; несохранённых сцен нет. После rescan все восемь parts загрузились как Texture2D 256×256. Master просмотрен через MCP.
- Edge: SVG-сборка восьми parts сравнилась с master на прозрачном canvas, **0 отличающихся пикселей**. Границы рисунка с outline: x=9…247, y=7…242; за canvas не выходит.
- Визуально просмотрены 100/140/180 px, одинаковые клетки для Goblin / Orc / Golem / Boss, сетки 6/7/8 и пример масштаба экрана шириной 390 px. Boss крупнее Golem. Примерка не заменяет будущий gameplay test.
- При 6/7/8 столбцах полный Boss canvas занимает примерно 119/100/85 логических px; на экране шириной 390 px — 64/54/46 физических px. Проверены корона, лицо, кулаки и outline на уменьшении.
- В browser review работают выбор части, pivots, отражение и выбор сетки. На viewport 390×844 ширина содержимого 390, горизонтального переполнения нет. Console/page/resource errors отсутствуют.
- Проект коротко запущен через Godot MCP на main_menu после импорта; runtime errors после запуска отсутствуют. Изменения боя не выполнялись, длительный прогон не нужен для статичного art gate. Игра остановлена.

Старые assets/boss.svg, scenes/boss.tscn, gameplay scripts, баланс и настройки запуска сохранены. Существующие пользовательские изменения в рабочем дереве не затронуты. Web игра не экспортировалась повторно: опубликован только отдельный локальный HTML art preview в игнорируемом build/.

## Ручная приёмка

1. Открыть art preview: принять силуэт, пропорции, фиолетовую кожу, тёмный корпус, золотые наплечники и корону.
2. Проверить лицо и клыки на 100 px и в уменьшенной дорожной примерке; корона должна уверенно отличать Boss от остальных врагов.
3. Сравнить с Golem при одной сетке: Boss крупнее, но не закрывает соседние клетки своим статичным силуэтом.
4. Посмотреть части / pivots / mirror. Принять внешность до создания rig.

Art, animations и gameplay приняты. Boss использует rigid cutout rig + walk_loop / attack / hit / death / spawn_or_intro в существующей боевой entity. Этот отчёт перенесён в docs/done после полной финальной приёмки Boss.
