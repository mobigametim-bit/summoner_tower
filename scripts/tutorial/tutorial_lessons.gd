class_name TutorialLessons
extends RefCounted

# Сценарий отдельно от контроллера. Числа экономики подставляются из текущего баланса.
const LINES: Dictionary = {
	"welcome": ["Я архимаг Бородаций. Обучу тебя призыву, обороне и ответственному расходованию чужой маны.", "I'm Archmage Beardric. I'll teach you summoning, defence and responsible spending of somebody else's mana."],
	"play": ["Начнём с леса. Нажми ▶. Гоблины уже согласились побыть учебными пособиями. Их никто не спрашивал.", "Let's start in the forest. Tap ▶. The goblins have volunteered as teaching aids. Nobody asked them."],
	"field": ["Из порталов идут незваные гости. По дороге — к нашей башне. До башни их желательно не доводить.", "Uninvited guests come through the portals and follow the road to our tower. Try not to let them arrive."],
	"health": ["Это здоровье башни. Дойдёт до нуля — крыша съедет. Буквально.", "This is the tower's health. When it reaches zero, we lose the roof over our heads. Literally."],
	"summon_first": ["Нажми на башню, чтобы призвать бойца. Число у основания — цена. Башня сдачу выдаёт бойцами.", "Tap the tower to summon a fighter. The number at its base is the price. This tower gives change in fighters."],
	"unit": ["Бойцы атакуют сами. Синий огонёк — мана. Каждый следующий призыв дороже. Магическая инфляция.", "Fighters attack automatically. The blue flame is mana. Each summon costs more than the last. Magical inflation."],
	"move": ["Перетащи лучника на подсвеченный постамент. Круг покажет дальность атаки. Желательно целиться не только в кусты.", "Drag the archer to the highlighted pedestal. The circle shows attack range. Try to cover more than just bushes."],
	"summon_second": ["Позовём второго лучника: нажми на башню. После этих двух призывов снова будет выпадать случайный боец.", "Tap the tower for another archer. After these two teaching summons, fighters will be random again."],
	"merge": ["Перетащи лучника на такого же. Одинаковый тип и уровень — слияние! При наведении оранжевый круг покажет будущую дальность.", "Drag an archer onto its match. Same type and level means a merge! The orange circle previews the new range."],
	"levels": ["Два бойца стали одним, зато сильнее! Уровни: зелёный → оранжевый → красный → синий → фиолетовый. Борода дальше не прокачивается.", "Two fighters became one stronger fighter! Levels: green → orange → red → blue → purple. Beards have no further upgrades."],
	"combat": ["Теперь бой! Призывай, переставляй и объединяй. За меткие советы я отвечаю, за меткие стрелы — лучник.", "Time to fight! Summon, reposition and merge. I provide sharp advice; the archer provides sharp arrows."],
	"mana": ["За врагов получаем ману. Даже за дошедших до башни — но тогда ремонт оплачиваем здоровьем. Чем выше уровень врага, тем больше награда.", "Enemies give mana, even when they reach the tower. But then repairs cost health. Higher-level enemies give larger rewards."],
	"random": ["Кто придёт на зов — сюрприз. Мы призываем подкрепление, а не оформляем доставку по каталогу.", "Who answers the call is a surprise. We're summoning reinforcements, not ordering from a catalogue."],
	"mage": ["Огненный маг любит скопления врагов. На высоких уровнях добавит горение и взрывы. Держи подальше от моей бороды.", "Fire mages like crowds. Higher levels add burning and explosions. Keep them away from my beard."],
	"frost_mage": ["Морозный маг замедляет врагов. Пока они мёрзнут, остальные объясняют им ошибку маршрута.", "Frost mages slow enemies. While they shiver, the others explain their navigational mistake."],
	"priest": ["Жрец света теперь доступен в обоих биомах. Его метка усиливает урон по врагу. Башню он не лечит — специализация другая.", "The Light Priest is now available in both biomes. His mark increases damage against enemies. He doesn't heal the tower: wrong speciality."],
	"range_sale": ["Круг при переносе — дальность атаки. Перетащи бойца на башню для продажи: вернёшь %s%% вложенной маны. За объединённого считаются оба бойца.", "The drag circle shows attack range. Drag a fighter onto the tower to sell for %s%% of the mana invested. Merged fighters include both investments."],
	"full": ["Свободных постаментов нет. Объединяй, переставляй или продавай. Дополнительный этаж пока не согласован.", "No free pedestals. Merge, rearrange or sell. Planning permission for another floor is still pending."],
	"swap": ["Разные бойцы не сливаются — меняются местами. Не всякую проблему решает скрещивание.", "Different fighters swap places instead of merging. Crossbreeding isn't the answer to everything."],
	"lv3": ["Новый уровень меняет и сами атаки: стрелы, огонь, мороз или свет. Боец наконец прочитал вторую страницу инструкции.", "Levels also change attacks: arrows, fire, frost or light. The fighter finally read page two of the manual."],
	"lv5": ["Пятый уровень! Особая способность срабатывает автоматически. Отдельную кнопку мы доверять тебе пока не стали.", "Level five! Special abilities activate automatically. We weren't ready to trust you with another button."],
	"max": ["Пятый уровень — предел. Два таких бойца просто меняются местами. Шестой цвет ещё не изобрели.", "Level five is the limit. Two max-level fighters just swap places. Nobody has invented a sixth colour yet."],
	"enemy_level": ["У врагов тоже есть уровни. Цвет и новое снаряжение — повод насторожиться, а не оценивать их чувство стиля.", "Enemies have levels too. New colours and equipment are a warning, not a fashion show."],
	"boss": ["Каждая пятая волна — с боссом и обычными врагами. Он приходит первым. Видимо, хочет пожаловаться руководству.", "Every fifth wave brings a boss alongside regular enemies. He arrives first. Probably wants to speak to management."],
	"boss_leftovers": ["Главного победили, но его компания ещё здесь. Сначала заканчиваем всю волну — потом делим премию.", "The boss is down, but his company is still here. Finish the whole wave, then we'll discuss bonuses."],
	"cards": ["Выбирай одну награду. Усиления действуют до конца забега, разовые подарки получишь сразу. Бонусы одинаковых карточек накапливаются.", "Choose one reward. Upgrades last for this run, while one-off gifts arrive immediately. Repeated upgrades stack."],
	"card_colors": ["Знакомые цвета: зелёный, оранжевый, красный, синий, фиолетовый. Чем выше уровень карточки, тем сильнее эффект. Смотри на числа!", "Familiar colours: green, orange, red, blue, purple. Higher-tier cards have stronger effects. Read the numbers!"],
	"reroll": ["Не нравится выбор? За просмотр можно получить новые варианты: один раз за боссовую волну. Бесплатный переброс открывается в мете.", "Don't like the choices? Watch once per boss wave to reroll. A free reroll can also be unlocked with a permanent upgrade."],
	"map_80": ["После выбора переезжаем: бойцы продадутся за %s%% вложений, а неистраченная мана сгорит. Новый запас — деньги от продажи! Цена призыва начнётся заново.", "Choosing a card moves us to a new map: fighters sell for %s%% of their investment and leftover mana is lost. Sale proceeds become your new mana! Summon prices reset."],
	"map_60": ["После этой волны за армию возвращают %s%%. Остаток маны опять сгорит. Перевозчики подняли тарифы — договор уже подписан.", "After this wave the army sells for %s%%. Leftover mana is lost again. The movers raised their rates: the contract is signed."],
	"map_40": ["Дальше возврат за армию — %s%%. Остаток маны не переносится. Зато больше сюрпризов. Понимаю, слабое утешение.", "From now on the army sells for %s%%. Unspent mana won't carry over. More surprises await. Yes, that's little comfort."],
	"gift": ["Этого бойца получили бесплатно. При продаже он вернёт столько же — ноль маны. Бухгалтерия беспощадна.", "This fighter was free. Selling returns exactly what you paid: zero mana. Accounting is merciless."],
	"revive": ["Башня прилегла. После просмотра можно вернуть %s здоровья и продолжить текущую волну. Один раз за забег. Крестик — перейти к итогам.", "The tower is having a lie-down. Watch to restore %s health and continue this wave, once per run. The cross takes you to the results."],
	"results": ["Это кристаллы душ. Они останутся после забега. Награду можно удвоить за просмотр — если захочешь. Поражение тоже можно превратить в инвестицию.", "These are soul crystals. They stay after the run. You can watch to double the reward if you like. Even defeat can be an investment."],
	"meta_entry": ["Теперь открой постоянные улучшения. Потратим кристаллы на что-нибудь полезнее новой шляпы.", "Now open permanent upgrades. Let's spend those crystals on something more useful than another hat."],
	"meta": ["Эти усиления останутся навсегда и применятся в следующем забеге. Цена нового уровня удваивается отдельно в каждой ветке. Думай с калькулятором.", "These upgrades stay forever and apply next run. Each branch doubles its own next-level price. Think with a calculator."],
	"meta_bought": ["Готово! В следующем забеге начнёшь сильнее. Вот что бывает, когда деньги не тратят на новые шляпы.", "Done! You'll start the next run stronger. That's what happens when you stop spending everything on hats."],
	"victory": ["Биом зачищен: волна 25 — победа! Если открылось кладбище, ищи стрелку в меню. Там недовольны жизнью по уважительной причине.", "Biome cleared: wave 25 is victory! If the graveyard unlocked, find the menu arrow. Its residents have good reasons to be unhappy with life."],
	"biomes": ["Стрелками переключаются биомы. Прогресс и кристаллы общие. Декорации и неприятности — местные. Жрец пополнил призыв в обоих биомах.", "Arrows switch biomes. Progress and crystals are shared. Scenery and trouble are local. The Priest joins the summon pool in both biomes."],
	"remains": ["Останки остаются между волнами. Некромант соберёт из двух голема плоти. Советую разобраться с организатором этого кружка.", "Remains persist between waves. A necromancer can turn two into a flesh golem. I suggest dealing with the club organiser."],
	"settings": ["Здесь можно перевести дух и настроить звук. Выход в меню завершит текущий забег — башню в карман не заберём.", "Take a breath and adjust the sound here. Returning to the menu ends this run. We can't put the tower in a pocket."],
	"ability_dash": ["Видишь след частиц? Враг делает рывок. Быстрые ноги — не повод пропускать его к башне.", "See that particle trail? The enemy is dashing. Fast feet are no excuse to let it reach the tower."],
	"ability_rage": ["Орк ранен и впал в ярость. Огненные частицы выдают его плохое настроение. Быстрее добивай, пока не добежал.", "The wounded orc is enraged. Fiery particles advertise his bad mood. Finish him before he arrives."],
	"ability_carapace_hit": ["Фиолетовые знаки над големом — защитный панцирь. Они расходуются от попаданий. Это не праздничная иллюминация.", "Purple symbols above the golem are armour charges. Hits consume them. This isn't festive lighting."],
	"ability_shield": ["Босс поднял щит! Сначала атаки истощают защиту. Молнии — не приглашение постоять поближе.", "The boss raised a shield! Attacks wear it down first. Those sparks aren't an invitation to come closer."],
	"ability_summon": ["Босс призвал свиту. Эти гости тоже должны покинуть поле, прежде чем волна закончится.", "The boss summoned a retinue. These guests must leave the field too before the wave can end."],
	"ability_rush": ["Босс пошёл в натиск. След частиц предупреждает об ускорении. Видимо, вспомнил, что оставил котёл на огне.", "The boss is charging. The particle trail warns of a speed boost. He must have left his cauldron on."],
	"ability_regenerate": ["Зомби восстанавливает здоровье! Эффект лечения выдаёт его хитрость. Добивай, пока он не передумал умирать.", "The zombie is regenerating! The healing effect gives him away. Finish him before he changes his mind about dying."],
	"ability_heal": ["Некромант лечит раненую нежить поблизости. Пока он жив, его компания держится дольше. Убери лекаря — убавится работы.", "The necromancer heals nearby wounded undead. His company lasts longer while he's alive. Deal with the healer to reduce your workload."],
	"ability_summon_skeletons": ["Некромант призывает скелетов. Они тоже должны исчезнуть с поля для завершения волны. Всё-таки кадровик.", "The necromancer summons skeletons. They must leave the field too before the wave ends. He's good at staffing."],
	"ability_assemble_flesh": ["Некромант собирает голема плоти из двух останков. Следи за вспышкой сборки. Вторсырьё вышло из-под контроля.", "The necromancer assembles a flesh golem from two remains. Watch the assembly flash. Recycling has got out of hand."],
	"ability_retinue": ["Лич призвал свиту! Новые скелеты — часть этой волны. Очередь на аудиенцию придётся разогнать целиком.", "The lich summoned his retinue! The new skeletons are part of this wave. Clear the entire audience queue."],
	"ability_grave_bell": ["Погребальный звон усиливает движение нежити. Смотри на частицы и ускорение. Звонят, к сожалению, не к обеду.", "The grave bell hastens the undead. Watch the particles and speed change. Unfortunately, that isn't the lunch bell."],
}


static func line(id: String, value: Variant = null) -> String:
	var language: int = 0 if LocaleService.language == "ru" else 1
	var text: String = LINES.get(id, [id, id])[language]
	return text % str(value) if value != null else text


static func ui(russian: String, english: String) -> String:
	return russian if LocaleService.language == "ru" else english
