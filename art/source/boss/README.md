# Boss — SVG art

Boss полностью принят пользователем 08.10.2026: «принимаю, дальше». Animated visual включён по умолчанию, исходный static сохранён. [Итоговый отчёт](../../../docs/done/BOSS_GAMEPLAY_REVIEW.md).

Образ: существующий [Boss](../../../assets/boss.svg), стилизация принятых Archer / Orc / Golem. Ручной SVG-код, без image generators и сторонних изображений. Новый Boss крупнее Golem, с фиолетовой кожей, тёмным корпусом, золотой короной и наплечниками, короткими клыками. HP не меняет его палитру.

- `master.svg` — сборка восьми исходных групп в порядке слоёв; preview, не цельная runtime texture.
- `parts/` — восемь отдельных прозрачных SVG 256×256, без trimming.
- `rig_manifest.json` — pivots, bones/parents, offsets и z-order созданного rig.
- `review.html` — art preview: текущий образ, 100/140/180 px, реальные размеры сеток 6–8, сравнение с врагами, части и pivots.

Outline #29180f, 7 px, округлые соединения. Origin=(128,128), baseline ступней≈239; будущий visual.scale=166/256. Голова вращается относительно шеи (132,143); нос в центре лица, ниже между глазами. Корона и клыки следуют голове. Кулаки следуют предплечьям, наплечники — плечам; отдельных костей этим деталям не требуется.

Rig: Root.position=−origin, Sprite2D.centered=false, position=−pivot; Bone.position=pivot−parent_pivot, rest=исходный transform. Z-index абсолютный, `z_as_relative=false`. Девять костей с Root. Скрытые шея/плечи/локти/бёдра имеют округлое продолжение под соседнюю часть.

`scenes/visuals/BossVisual.tscn`: CanvasGroup (наследник Node2D) → Skeleton2D / Bone2D / Sprite2D и AnimationPlayer. CanvasGroup.self_modulate делает fade единым рисунком, без просвечивания скрытых стыков; стандартный материал, без mipmaps, fit_margin=0, clear_margin=2. Root отвечает только за pose/scale, а не прозрачность.

Clips: walk_loop 1.2 s, attack 0.55 s / impact 0.22 s, hit 0.16 s, death 0.45 s, spawn_or_intro 0.35 s. После коротких clips возвращается walk_loop; death удерживает исчезнувшую позу до Replay. RESET восстанавливает transforms и self_modulate. Impact — однократный visual event: в review без урона, в бою синхронизирован с исходным contact / damage ApproachingEnemy.

[Animation review](http://127.0.0.1:4175/preview/boss-animation/): `scenes/debug/BossAnimationTest.tscn`, наследует общий ArtAnimationTest, начальный asset Boss. Есть 0.5×/1×/2×, Replay/Pause, Mirror и размеры сеток 6–8.

[Gameplay review](http://127.0.0.1:4175/preview/boss-gameplay/): `scenes/debug/BossGameplayReview.tscn`, старт с настоящей волны 5, переключатель STATIC / ANIMATED. Intro запускается один раз и не останавливает movement / targetability. AnimationPlayer в бою обновляется вручную из ApproachingEnemy; windup подстраивается к прежнему времени контакта, impact вызывается ровно в момент contact. Hit не прерывает подготовку удара. Boss не перекрашивается от HP.

После outcome выживает только короткий visual tail, без targetability / участия в волне; удаляется после death или recovery, а при stop/restart очищается общей системой. Upgrade choice может поставить tail на паузу вместе с боем; после выбора fade заканчивается. Старый `assets/boss.svg` сохранён; в `scenes/boss.tscn` сохранён static Sprite2D и добавлен BossVisual. Animated default включён после финальной приёмки; STATIC доступен в review.
