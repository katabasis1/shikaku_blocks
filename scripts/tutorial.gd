class_name Tutorial
extends RefCounted
## Обучение по навыкам: на каждом обучающем уровне один новый навык, остальному
## учим в момент, когда оно впервые понадобилось. Пройденные навыки — биты
## в сохранении (GameState.tutorial): вернувшийся игрок обучение не видит.
## Здесь только данные; когда и что показать, решает TutorialCoach
## (scenes/game/tutorial_coach.gd). Уровни 1–3 сделаны вручную: tools/tutorial_levels.py.

## Навыки (биты GameState.tutorial).
## Уровень 1: перетащить блок; число — это размер блока.
const DRAG := 1
## Уровень 2: повернуть блок.
const ROTATE := 2
## Уровень 3: в блоке ровно одно число.
const ONE_NUMBER := 4
## Был «Дальше — сам!» на первом уровне без страховки; убран 07.10 (обучение кончилось — без напутствий).
## Бит оставлен: он есть в сохранениях и в ALL.
const SOLO := 8
## Первый тупик без страховки: отмена хода.
const UNDO := 16
## Первый долгий простой: кнопка подсказки.
const HINT := 32
const ALL := DRAG | ROTATE | ONE_NUMBER | SOLO | UNDO | HINT

## Уровни со страховкой: тупиковое место подсвечивается красным, блок туда не встаёт,
## а подпись над полем объясняет, почему.
const GUARD_LEVELS := 3
## Навык каждого обучающего уровня.
const LEVEL_SKILL := {1: DRAG, 2: ROTATE, 3: ONE_NUMBER}
## Обучающие уровни — 1..LEVELS (LEVEL_SKILL). Пройден последний — обучение кончилось: в настройках появляется
## «Оценить игру» (GameState.tutorial_done, SettingsPanel).
const LEVELS := 3
## Навык DRAG пройден после стольких своих ходов на уровне 1 — дальше рука не нужна.
const DRAG_OWN_MOVES := 2
## Кнопку подсказки предлагаем (пульс) на уровнях HINT_FROM..HINT_TO после HINT_IDLE секунд простоя.
const HINT_FROM := 2
const HINT_TO := 9
const HINT_IDLE := 20.0

## Почему блок не встаёт на место (Board.rect_issue, страховка DragController).
enum Issue { OK, OUTSIDE, OCCUPIED, NO_NUMBER, MANY_NUMBERS, WRONG_SIZE, DEAD_END, BLOCKED, WRONG_COLOR }


## Навык, которому учит уровень level (0 — никакому или уже пройден).
static func skill_for_level(level: int, learned: int) -> int:
	var s: int = int(LEVEL_SKILL.get(level, 0))
	return 0 if (s & learned) != 0 else s
