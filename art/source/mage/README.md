# Mage — SVG art и rigid cutout animation review

07.10.2026. **Mage полностью принят пользователем**: план, SVG art, rigid cutout rig/animations, idle 1.2 s, gameplay integration и свечение посоха. Animated visual включён по умолчанию; static fallback сохранён. Push только по отдельному разрешению.

Reference: `art/references/mage.png`. Production art отрисован вручную SVG-кодом: простые path/ellipse/circle/rect, flat colors, outline #29180f, 7 px, один-два простых уровня shading. Нет image generators, Krita, raster embedding и сторонних игровых ассетов.

[Посмотреть в браузере](http://127.0.0.1:4175/preview/mage-art/) — reference рядом с новой сборкой, 100/140/180 px, постаменты сеток 6/7/8 столбцов, уменьшение для экрана шириной 390 px, сравнение с принятым Archer, пять цветов ткани, выбор частей, pivots и mirror. [Результаты проверки](../../../docs/done/MAGE_ART_REVIEW.md), [согласованный план](../../../docs/done/MAGE_ART_PLAN.md).

`master.svg` — сборка тех же восьми частей. `parts/` — самостоятельные прозрачные SVG 256×256 без trimming. Runtime использует части; master предназначен для art review и drag preview. `review.html` — локальная страница просмотра, не игровая сцена. `rig_manifest.json` содержит pivots/слои, длительности и текущий gate.

[Mage animation preview](http://127.0.0.1:4175/preview/mage-animation/) — отдельный Godot Web export: idle_loop, cast, spawn, 0.5×/1×/2×, Replay, Pause, Repeat, Mirror и реальные масштабы. Можно переключаться на принятых Archer/Goblin. [Результаты animation gate](../../../docs/done/MAGE_ANIMATION_REVIEW.md).

## Силуэт и палитра

Широкая шляпа с загнутой вершиной, компактное лицо с белыми волосами/короткой бородой, короткая мантия и маленькие конечности, крупный красный кристалл посоха. Сумка/пояс/брошь входят в Body; лицо/волосы/борода в Head; кисти в руки; ботинки в ноги. Мелкие складки, декоративные искры, фон и тень reference исключены из runtime character art.

Source art сохраняет синюю ткань reference (#3568b6 / #254b85 / #5488d0). Кожа #ffc18c / #de9668, волосы #f3e7ce / #d4c4a8, золото #e5b34f / #b87a32 / #f4d17e, дерево/кожа #895334 / #613821. По правке пользователя от 07.10.2026 кристалл посоха красный (#ed5158 / #9f293f / #ffb0a0 / #fff0ce), свечение атаки тёплое красно-оранжевое. Малые украшения/брошь сохраняют cyan palette #56d9ed / #2999c0 / #b5f4f4. Форма посоха и timing не изменялись.

Согласованный gameplay принцип: только ткань шляпы, мантии и рукавов получает Lv1–Lv5 зелёный/оранжевый/красный/синий/фиолетовый. Лицо, волосы, борода, золотая отделка, сумка, ботинки, деревянный посох и кристаллы сохраняют цвета. Browser preview демонстрирует это заменой трёх исходных cloth fills; Godot material и gameplay palette будут на integration gate.

## Pivots и слои

| SVG part | Pivot canvas | Bone / parent | Bone local position | Z |
|---|---|---|---|---:|
| arm_back | 94,158 | BackArm / Body | −33,−17 | 0 |
| leg_left | 102,211 | LeftLeg / Body | −25,36 | 1 |
| leg_right | 148,211 | RightLeg / Body | 21,36 | 2 |
| body | 127,175 | Body / Root | 127,175 | 3 |
| staff | 203,175 | Staff / FrontArm | 40,16 | 4 |
| arm_front | 163,159 | FrontArm / Body | 36,−16 | 5 |
| head | 128,144 | Head / Body | 1,−31 | 6 |
| hat | 128,144 | Sprite2D / Head, без bone | — | 7 |

Actor origin=(128,128), Root.position=(−128,−128), опора ступней около y=239. Каждая часть сохраняет полный canvas; Sprite2D.centered=false, position=−pivot. Body расположен относительно Root в исходных canvas coordinates; дочерние bones относительно parent pivot. Hat использует Head pivot, отдельной кости не требует. Rest явно равен исходному transform, determinant=1 у всех 8 bones.

Свободная рука за корпусом, посох за держащей кистью и перед корпусом, голова скрывает плечо, шляпа перед головой. Округлые скрытые окончания плеч/ног/шеи дорисованы под соседние части. Крайние позы cast и mirror просмотрены в Godot/Web; принятые SVG shapes не менялись.

Visual scale=100/256. Примерка использует настоящий `SummonSlot.fit_to_cell`: размер слота=672/columns−4, UnitHost.scale=min((slot_size−12)/100,1), UnitHost.y=26×slot_size/140−42×scale. При 6/7/8 столбцах canvas≈96/80/68 логических px; на экране шириной 390≈52/43/37 физических px. Это visual preview, не выполненная gameplay integration.

## Следующий gate

`scenes/visuals/MageVisual.tscn` создана через Godot MCP: 8 bones вместе с Root, 8 Sprite2D, AnimationPlayer и отдельный SpawnPlayer для будущего независимого spawn overlay. Hat под Head без своей кости; Staff под FrontArm. Idle 1.2 s, cast 0.42 s с release 0.18 s, spawn 0.4 s. По правке пользователя от 07.10.2026 idle ускорен вдвое без изменения амплитуды. MageVisual управляет только позой и визуальным событием; снаряды не создаёт. ReleasePoint в release pose совпадает с Muzzle=(32,−8).

[Настоящий бой для приёмки](http://127.0.0.1:4175/preview/mage-gameplay/) — первые два призыва Mage, production pool/цены/характеристики прежние. STATIC/ANIMATED, pause и restart доступны внизу. CombatUnit вызывает прежний fireball на release 0.18 s без задержки cooldown. `cloth_palette.gdshader` меняет только ткань; материал локален для экземпляра и используется также drag preview. Свечение кристалла — три Polygon2D с opacity/scale tracks внутри cast, без новой текстуры или postprocessing. В обычной игре Mage animated по умолчанию, static fallback сохранён. [Результаты и checklist](../../../docs/done/MAGE_GAMEPLAY_REVIEW.md).
