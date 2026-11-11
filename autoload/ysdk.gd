extends Node
## Интеграция с Яндекс Играми (SDK v2) через JavaScriptBridge.
##
## SDK подключается в пресете экспорта: html/head_include = <script src='/sdk.js'>.
## При старте этот узел добавляет на страницу небольшую JS-обёртку (GLUE_JS):
## она вызывает SDK и складывает ответы в очередь, а мы забираем их каждый кадр.
## Опрос очереди надёжнее колбэков JavaScriptBridge: не нужно следить за временем
## жизни JS-функций, и вызовы игры всегда идут из обычного кадра движка.
##
## Вне Яндекс Игр (редактор, ПК, чужой хостинг) всё работает как заглушки:
## реклама сразу вызывает колбэк, подсказки бесплатные, облако не трогается.

## SDK инициализирован — реклама, облако и лидерборд доступны.
signal initialized
## SDK не загрузился (не Яндекс Игры, нет сети) — ждать его больше нечего (экран лидеров, 18.3).
signal init_failed
## Таблица лидеров прочитана (18.3, request_leaderboard): data — {"entries": [{"rank", "score", "name", "id"}],
## "userRank": место игрока (0 — нет в таблице)} или {"error": код}; LB_NO_SDK — вне Яндекс Игр.
signal leaderboard_loaded(board: String, data: Dictionary)
## Вход игрока узнали или он сменился (после init и после окна входа open_auth).
signal auth_changed(authorized: bool)
## Яндекс принял результат в таблицу board (setScore завершился): кэш таблицы сброшен, экран лидеров читает её
## заново — после входа строка игрока появляется без ожидания 60 с.
signal leaderboard_changed(board: String)
## Изменилось can_offer_review(): пришёл ответ canReview, оценку запросили, гость ушёл во вход или вернулся из него —
## окно настроек показывает или прячет «Оценить игру».
signal review_availability_changed

## Техническое имя лидерборда в консоли разработчика Яндекс Игр.
const LEADERBOARD_NAME := "score"
const DAILY_LEADERBOARD_NAME := "daily_streak"
const DEFAULT_INTERSTITIAL_FROM_LEVEL := 4
const DEFAULT_INTERSTITIAL_INTERVAL_MS := 90000
const DEFAULT_FREE_HINTS_PER_LEVEL := 1
## Сердца (20.1a, PLAN 20.1): сколько на попытку уровня (0 — без предела: сердец не видно, ошибки считаются, звёзды
## 3 − ошибки), с какого уровня основного пути (раньше — обучение со страховкой; задача дня — всегда с сердцами),
## сколько возрождений за попытку и можно ли один раз продолжить бесплатно, если реклама не показалась (1 / 0).
const DEFAULT_HEARTS := 3
const DEFAULT_HEARTS_FROM_LEVEL := 4
const DEFAULT_REVIVE_MAX := 3
const DEFAULT_REVIVE_FREE_ON_FAIL := 1
## Пределы флагов Remote Config (16.2a): значение вне пределов прижимается к краю, не число — значение по умолчанию.
const FLAG_FROM_LEVEL_MIN := 1
const FLAG_FROM_LEVEL_MAX := 1000
const FLAG_INTERVAL_MS_MIN := 60000  # чаще раза в минуту Яндекс межстраничную всё равно не покажет
const FLAG_INTERVAL_MS_MAX := 3600000
const FLAG_FREE_HINTS_MAX := 5
const FLAG_HEARTS_MAX := 5
const FLAG_REVIVE_MAX := 10
## Сама игра просит оценку в момент победы на уровнях REVIEW_FROM_LEVEL..REVIEW_TO_LEVEL (12.10b: было 5–7 — слишком
## рано, игрок ещё не втянулся). Раньше — только кнопка «Оценить игру» в настройках (после обучения).
const REVIEW_FROM_LEVEL := 11
const REVIEW_TO_LEVEL := 15
## Чтение таблицы (18.3): первые LEADERBOARD_TOP мест (у Яндекса не больше 20) и по LEADERBOARD_AROUND соседей
## игрока сверху и снизу (не больше 10): до 10 + 7 строк и разрыв. В карточку входит LeaderboardData.MAX_ROWS (14) —
## лишних соседей срезает LeaderboardData.fit_ranks (строка игрока остаётся всегда).
const LEADERBOARD_TOP := 10
const LEADERBOARD_AROUND := 3
## Ответ таблицы хранится столько, мс: чтение у Яндекса ограничено по частоте, вкладки и повторные входы на
## экран берут кэш. После входа игрока кэш сбрасывается.
const LEADERBOARD_CACHE_MS := 60000
## Ошибка «SDK нет» — редактор, ПК, чужой хостинг или SDK не загрузился.
const LB_NO_SDK := LeaderboardData.ERROR_NO_SDK
## Вторая отправка очков после входа — через столько секунд (setScore у Яндекса — не чаще раза в секунду).
const RESUBMIT_GAP_SEC := 1.2
## Межстраничную рекламу не показываем до этого уровня (первые впечатления важнее).
const INTERSTITIAL_FROM_LEVEL := DEFAULT_INTERSTITIAL_FROM_LEVEL
## Свой минимальный интервал между межстраничными (Яндекс сам не даёт чаще 60 с).
const INTERSTITIAL_INTERVAL_MS := DEFAULT_INTERSTITIAL_INTERVAL_MS
## Если реклама не открылась за это время, продолжаем игру без неё.
const AD_OPEN_TIMEOUT_MS := 8000

const AD_NONE := &""
const AD_INTERSTITIAL := &"interstitial"
const AD_REWARDED := &"rewarded"
## Причины отказа feedback.canReview, которые идут в Метрику как есть (в нижнем регистре; прочее — "error").
const REVIEW_REASONS: Array[String] = ["no_auth", "game_rated", "review_already_requested", "review_was_requested",
		"unknown", "unavailable"]
## Итоги отзыва (review_result), после которых больше не просим (16.2a): окно показано или отказ навсегда. Гость
## (no_auth), unknown, unavailable и ошибка — не в счёт: на следующей победе на уровнях 11–15 (в другой сессии) спросим.
const REVIEW_FINAL: Array[String] = ["sent", "closed", "game_rated", "review_already_requested", "review_was_requested"]

const GLUE_JS := """
(function () {
	if (window.GodotYSDK) { return; }
	var queue = [];
	var B = { ysdk: null, player: null };
	function push(name, data) { queue.push([name, data === undefined ? null : data]); }
	B.poll = function () {
		if (queue.length === 0) { return ""; }
		var s = JSON.stringify(queue);
		queue = [];
		return s;
	};
	function isAuth(p) {
		try {
			if (!p) { return false; }
			if (typeof p.isAuthorized === "function") { return !!p.isAuthorized(); }
			return p.getMode() !== "lite";
		} catch (e) { return false; }
	}
	function uid(p) { try { return p ? String(p.getUniqueID() || "") : ""; } catch (e) { return ""; } }
	function pushAuth(cancelled) {
		push("auth", { authorized: isAuth(B.player), id: uid(B.player), cancelled: !!cancelled });
	}
	B.init = function () {
		if (typeof YaGames === "undefined") { push("init_failed", "sdk.js not loaded"); return; }
		YaGames.init().then(function (ysdk) {
			B.ysdk = ysdk;
			var lang = "";
			try { lang = ysdk.environment.i18n.lang || ""; } catch (e) {}
			try {
				ysdk.on("game_api_pause", function () { push("api_pause", true); });
				ysdk.on("game_api_resume", function () { push("api_pause", false); });
			} catch (e) {}
			document.addEventListener("visibilitychange", function () { push("visible", !document.hidden); });
			push("init", { lang: lang });
			return ysdk.getPlayer({ scopes: false }).then(function (player) {
				B.player = player;
				pushAuth(false);
				return player.getData();
			}).then(function (data) {
				push("cloud", data || {});
			}).catch(function (err) {
				push("cloud_failed", String(err));
			});
		}).catch(function (err) {
			push("init_failed", String(err));
		});
	};
	B.loadingReady = function () {
		try { B.ysdk.features.LoadingAPI.ready(); } catch (e) {}
	};
	B.gameplay = function (active) {
		try {
			var api = B.ysdk.features.GameplayAPI;
			if (active) { api.start(); } else { api.stop(); }
		} catch (e) {}
	};
	B.showInterstitial = function () {
		try {
			B.ysdk.adv.showFullscreenAdv({ callbacks: {
				onOpen: function () { push("inter_open"); },
				onClose: function (wasShown) { push("inter_close", !!wasShown); },
				onError: function (e) { push("inter_close", false); },
				onOffline: function () { push("inter_close", false); }
			} });
		} catch (e) { push("inter_close", false); }
	};
	B.showRewarded = function () {
		try {
			B.ysdk.adv.showRewardedVideo({ callbacks: {
				onOpen: function () { push("rew_open"); },
				onRewarded: function () { push("rew_reward"); },
				onClose: function () { push("rew_close"); },
				onError: function (e) { push("rew_close"); }
			} });
		} catch (e) { push("rew_close"); }
	};
	B.saveData = function (json) {
		if (!B.player) { return; }
		try { B.player.setData(JSON.parse(json), false).catch(function () {}); } catch (e) {}
	};
	B.setScore = function (name, score) {
		var y = B.ysdk;
		if (!y) { return; }
		try {
			var done = function () { push("score_set", { name: name, score: score }); };
			if (y.leaderboards && y.leaderboards.setScore) {
				y.leaderboards.setScore(name, score).then(done).catch(function () {});
			} else if (y.getLeaderboards) {
				y.getLeaderboards().then(function (lb) {
					return lb.setLeaderboardScore(name, score);
				}).then(done).catch(function () {});
			}
		} catch (e) {}
	};
	B.lbEntries = function (name, top, around) {
		function fail(code) { push("lb", { name: name, error: String((code && code.code) || code || "ERROR") }); }
		var y = B.ysdk;
		if (!y) { fail("NO_SDK"); return; }
		try {
			var opts = { quantityTop: top, includeUser: isAuth(B.player), quantityAround: around };
			var req;
			if (y.leaderboards && y.leaderboards.getEntries) {
				req = y.leaderboards.getEntries(name, opts);
			} else if (y.getLeaderboards) {
				req = y.getLeaderboards().then(function (lb) { return lb.getLeaderboardEntries(name, opts); });
			} else { fail("UNAVAILABLE"); return; }
			req.then(function (res) {
				res = res || {};
				var out = { name: name, userRank: Number(res.userRank) || 0, entries: [] };
				var list = res.entries || [];
				for (var i = 0; i < list.length; i++) {
					var e = list[i] || {};
					var pl = e.player || {};
					out.entries.push({ rank: Number(e.rank) || 0, score: Number(e.score) || 0,
						name: String(pl.publicName || ""), id: String(pl.uniqueID || "") });
				}
				push("lb", out);
			}).catch(fail);
		} catch (e) { fail(e); }
	};
	B.openAuth = function () {
		var y = B.ysdk;
		if (!y || !y.auth) { pushAuth(true); return; }
		try {
			y.auth.openAuthDialog().then(function () {
				return y.getPlayer({ scopes: false });
			}).then(function (player) {
				B.player = player;
				pushAuth(false);
				return player.getData().then(function (data) { push("cloud", data || {}); });
			}).catch(function () { pushAuth(true); });
		} catch (e) { pushAuth(true); }
	};
	B.loadFlags = function (defaultsJson) {
		var defaults = {};
		try { defaults = JSON.parse(defaultsJson) || {}; } catch (e) {}
		try {
			B.ysdk.getFlags({ defaultFlags: defaults }).then(function (flags) { push("flags", flags || {}); })
			.catch(function () { push("flags", {}); });
		} catch (e) { push("flags", {}); }
	};
	B.checkReview = function () {
		try {
			if (!B.ysdk.feedback) { push("can_review", { value: false, reason: "UNAVAILABLE" }); return; }
			B.ysdk.feedback.canReview().then(function (result) { push("can_review", result || { value: false }); })
			.catch(function (err) { push("can_review", { value: false, reason: String(err) }); });
		} catch (e) { push("can_review", { value: false, reason: String(e) }); }
	};
	B.requestReview = function () {
		try {
			if (!B.ysdk.feedback) { push("review", { value: false, reason: "UNAVAILABLE" }); return; }
			B.ysdk.feedback.canReview().then(function (result) {
				if (!result || !result.value) { push("review", result || { value: false }); return; }
				return B.ysdk.feedback.requestReview().then(function (answer) {
					push("review", answer || {});
				});
			}).catch(function (err) { push("review", { value: false, reason: String(err) }); });
		} catch (e) { push("review", { value: false, reason: String(e) }); }
	};
	window.GodotYSDK = B;
})();
"""

## true, когда SDK Яндекса загружен и инициализирован.
var is_available: bool = false
## true, пока SDK ещё грузится (веб, обёртка есть, init не пришёл и не упал): экран лидеров показывает загрузку.
var sdk_pending: bool = false
## Игрок вошёл в аккаунт Яндекса (гостю таблица видна, но его результата в ней нет) и его uniqueID.
var is_authorized: bool = false
var player_id: String = ""
## Вход уже известен (пришёл player или облако не загрузилось): до этого таблицу не читаем — ответ без игрока
## лёг бы в кэш на минуту.
var auth_known: bool = false

var _bridge = null  # JavaScriptObject window.GodotYSDK (только в вебе)
var _cloud_ready: bool = false
var _loading_ready_wanted: bool = false
var _loading_ready_sent: bool = false
var _gameplay_wanted: bool = false
var _gameplay_active: bool = false
var _suspend: Dictionary = {}  # причины паузы геймплея: реклама, пауза платформы, скрытая вкладка
var _last_interstitial_ms: int = 0
var interstitial_from_level: int = DEFAULT_INTERSTITIAL_FROM_LEVEL
var interstitial_interval_ms: int = DEFAULT_INTERSTITIAL_INTERVAL_MS
var _free_hints: int = DEFAULT_FREE_HINTS_PER_LEVEL
var _hearts: int = DEFAULT_HEARTS
var _hearts_from_level: int = DEFAULT_HEARTS_FROM_LEVEL
var _revive_max: int = DEFAULT_REVIVE_MAX
var _revive_free_on_fail: bool = DEFAULT_REVIVE_FREE_ON_FAIL != 0
var flags_ready: bool = false
## Запрос оценки (requestReview) в этой сессии ушёл: Яндекс даёт один. Гостю (ответ NO_AUTH) окна не было — запрос
## не потрачен, флаг снимается.
var _review_requested_this_session: bool = false
## Сама игра уже просила оценку в этой сессии (победа на уровнях 11–15) — больше не просит, даже если гостю отказано.
var _auto_review_tried: bool = false
## Гость нажал «Оценить игру»: открыто окно входа. Вошёл — сразу окно оценки; отказался — кнопка возвращается.
var _review_after_auth: bool = false
## Последний ответ feedback.canReview: Яндекс разрешает запросить оценку (игрок вошёл, игру не оценивал, окно оценки
## ему ещё не показывали). Спрашиваем, когда узнали вход, и при каждой его смене (гость вошёл — NO_AUTH ушло).
var _can_review: bool = false
## Вне Яндекс Игр «Оценить игру» видна (заглушка), чтобы проверить её в редакторе. По умолчанию — только в
## отладочной сборке; selftest подменяет.
var review_stub: bool = OS.is_debug_build()

var _ad_kind: StringName = AD_NONE
var _ad_callback: Callable = Callable()
var _ad_opened: bool = false
var _ad_rewarded: bool = false
var _ad_requested_ms: int = 0

var _lb_cache: Dictionary = {}    # таблица -> {"at": мс, "data": ответ}
var _lb_pending: Dictionary = {}  # таблица -> true, пока ждём ответа
var _auth_requested: bool = false     # открыто окно входа (open_auth)
var _resubmit_after_cloud: bool = false  # вошёл — отправить очки и серию, когда сольётся облако


func _ready() -> void:
	# Реклама и пауза платформы приходят и тогда, когда дерево на паузе.
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.saved.connect(_on_saved)
	GameState.level_completed.connect(_on_level_completed)
	GameState.daily_completed.connect(_on_daily_completed)
	if not OS.has_feature("web") or not Engine.has_singleton(&"JavaScriptBridge"):
		set_process(false)
		return
	var js = Engine.get_singleton(&"JavaScriptBridge")
	js.eval(GLUE_JS, true)
	_bridge = js.get_interface("GodotYSDK")
	if _bridge == null:
		push_warning("YSDK: не удалось подключить JS-обёртку")
		set_process(false)
		return
	sdk_pending = true
	_bridge.init()


func _process(_delta: float) -> void:
	_poll_events()
	if _ad_kind != AD_NONE and not _ad_opened \
			and Time.get_ticks_msec() - _ad_requested_ms > AD_OPEN_TIMEOUT_MS:
		_finish_ad("timeout")


# --- Публичный API ----------------------------------------------------------

## Игра загружена и готова к игре (LoadingAPI.ready). Можно звать повторно.
func loading_ready() -> void:
	_loading_ready_wanted = true
	if is_available and not _loading_ready_sent:
		_loading_ready_sent = true
		_bridge.loadingReady()


## Начался активный игровой процесс (GameplayAPI.start).
func gameplay_start() -> void:
	_gameplay_wanted = true
	_sync_gameplay()


## Игровой процесс остановлен: победа, меню, выход со сцены (GameplayAPI.stop).
func gameplay_stop() -> void:
	_gameplay_wanted = false
	_sync_gameplay()


## Можно ли предложить rewarded-рекламу (иначе награду даём бесплатно).
func is_rewarded_available() -> bool:
	return is_available


## Межстраничная реклама. on_done() вызывается всегда: после рекламы или сразу,
## если показывать нельзя (рано, часто, нет SDK, уже идёт реклама).
func show_interstitial(on_done: Callable) -> void:
	var too_early := GameState.level < interstitial_from_level
	var too_often := Time.get_ticks_msec() - _last_interstitial_ms < interstitial_interval_ms
	if not is_available or _ad_kind != AD_NONE or too_early or too_often:
		on_done.call_deferred()
		return
	_start_ad(AD_INTERSTITIAL, on_done)
	_bridge.showInterstitial()


## Реклама за награду. on_done(rewarded: bool) вызывается всегда.
func show_rewarded(on_done: Callable) -> void:
	if not is_available or _ad_kind != AD_NONE:
		on_done.call_deferred(false)
		return
	_start_ad(AD_REWARDED, on_done)
	_bridge.showRewarded()


# --- Реклама ----------------------------------------------------------------

func _start_ad(kind: StringName, on_done: Callable) -> void:
	_ad_kind = kind
	_ad_callback = on_done
	_ad_opened = false
	_ad_rewarded = false
	_ad_requested_ms = Time.get_ticks_msec()
	_set_suspended(&"ad", true)


## Реклама закончилась: колбэк и итог в Метрику (16.1, Analytics.ad). result — "timeout" (не открылась за
## AD_OPEN_TIMEOUT_MS); "" — по событиям: не открылась — "not_shown", межстраничная — "shown" (shown — Яндекс
## подтвердил показ), за награду — "rewarded" или "closed" (закрыл до награды).
func _finish_ad(result: String = "", shown: bool = true) -> void:
	var kind := _ad_kind
	var cb := _ad_callback
	var rewarded := _ad_rewarded
	_ad_kind = AD_NONE
	_ad_callback = Callable()
	_set_suspended(&"ad", false)
	if kind == AD_NONE:
		return
	if result.is_empty():
		result = ad_result(kind, _ad_opened and shown, rewarded)
	Analytics.ad(kind, result)
	if not cb.is_valid():
		return
	if kind == AD_REWARDED:
		cb.call(rewarded)
	else:
		cb.call()


## Итог показа рекламы kind для Метрики: opened — реклама открылась (и Яндекс подтвердил показ), rewarded —
## пришла награда.
static func ad_result(kind: StringName, opened: bool, rewarded: bool) -> String:
	if not opened:
		return "not_shown"
	if kind == AD_REWARDED:
		return "rewarded" if rewarded else "closed"
	return "shown"


## Итог запроса отзыва для Метрики (16.1) по ответу feedback: "sent" / "closed" (окно показано, отзыв оставлен или
## нет) или причина отказа canReview в нижнем регистре (no_auth, game_rated, review_already_requested,
## review_was_requested, unknown, unavailable); прочее — "error".
static func review_result(data: Variant) -> String:
	var d: Dictionary = data if data is Dictionary else {}
	if d.has("feedbackSent"):
		return "sent" if bool(d["feedbackSent"]) else "closed"
	var reason := str(d.get("reason", "")).to_lower()
	if reason in REVIEW_REASONS:
		return reason
	return "error"


# --- События из JS ------------------------------------------------------------

func _poll_events() -> void:
	var raw = _bridge.poll()
	if typeof(raw) != TYPE_STRING or String(raw).is_empty():
		return
	var events = JSON.parse_string(String(raw))
	if not (events is Array):
		return
	for e in events:
		if e is Array and e.size() == 2:
			_handle_event(String(e[0]), e[1])


func _handle_event(event_name: String, data: Variant) -> void:
	match event_name:
		"init":
			is_available = true
			sdk_pending = false
			if data is Dictionary:
				var lang := str(data.get("lang", ""))
				if not lang.is_empty():
					GameState.set_language(lang)
			if _loading_ready_wanted:
				loading_ready()
			_sync_gameplay()
			_bridge.loadFlags(JSON.stringify(flag_defaults()))
			initialized.emit()
		"init_failed":
			sdk_pending = false
			push_warning("YSDK: SDK недоступен (%s), игра работает без Яндекса" % str(data))
			init_failed.emit()
			review_availability_changed.emit()  # заглушка «Оценить игру» (отладочная сборка) ждала конца загрузки
		"cloud":
			_cloud_ready = true
			var cloud: Dictionary = data if data is Dictionary else {}
			# merge сам сохранит и отправит в облако, если облако было впереди.
			# Если впереди локальный прогресс — отправляем его.
			if not GameState.merge_save_data(cloud):
				_push_cloud(GameState.get_save_data())
			if _resubmit_after_cloud:
				_resubmit_after_cloud = false
				submit_scores()
		"cloud_failed":
			push_warning("YSDK: облачные сохранения недоступны (%s)" % str(data))
			# Вошёл, а облако не прочиталось: очки и серию в таблицы всё равно отправляем (местные).
			if _resubmit_after_cloud:
				_resubmit_after_cloud = false
				submit_scores()
			if not auth_known:
				auth_known = true
				_check_review()
				auth_changed.emit(is_authorized)
		"flags":
			_apply_flags(data)
		"auth":
			_apply_auth(data)
		"lb":
			_on_leaderboard(data)
		"score_set":
			# Яндекс принял результат (16.3): запоминаем лучшее принятое — меньшее в таблицу больше не уйдёт.
			var sd: Dictionary = data if data is Dictionary else {"name": str(data)}
			var board := str(sd.get("name", ""))
			var value: Variant = sd.get("score", 0)
			if value is int or value is float:
				GameState.note_leaderboard_sent(board, int(value))
			_lb_cache.erase(board)
			leaderboard_changed.emit(board)
		"can_review":
			var cr: Dictionary = data if data is Dictionary else {}
			_can_review = bool(cr.get("value", false))
			review_availability_changed.emit()
		"review":
			# Ответ canReview → requestReview: окно показано или отказ навсегда — больше не просим (16.2a).
			var result := review_result(data)
			# Гость (NO_AUTH): окна не было, запрос в сессии не потрачен — «Оценить игру» снова видна (вход → оценка).
			_review_requested_this_session = result != "no_auth"
			_can_review = false
			if result in REVIEW_FINAL and not GameState.review_prompted:
				GameState.review_prompted = true
				GameState.save_settings()
			Analytics.review(result)
			review_availability_changed.emit()
		"api_pause":
			_set_suspended(&"api_pause", bool(data))
		"visible":
			_set_suspended(&"hidden", not bool(data))
		"inter_open", "rew_open":
			_ad_opened = true
			_set_suspended(&"ad", true)
		"rew_reward":
			_ad_rewarded = true
		"inter_close":
			if bool(data):
				_last_interstitial_ms = Time.get_ticks_msec()
			if _ad_kind == AD_INTERSTITIAL:
				_finish_ad("", bool(data))
			else:
				_set_suspended(&"ad", false)
		"rew_close":
			if _ad_kind == AD_REWARDED:
				_finish_ad()
			else:
				_set_suspended(&"ad", false)


# --- Пауза, звук, GameplayAPI -------------------------------------------------

## Реклама, пауза от платформы или скрытая вкладка: глушим звук и останавливаем
## GameplayAPI. Дерево на паузу не ставим: в головоломке нет таймеров, а
## «зависшая» пауза из-за потерянного события сломала бы игру.
func _set_suspended(reason: StringName, on: bool) -> void:
	if on:
		_suspend[reason] = true
	else:
		_suspend.erase(reason)
	GameState.set_audio_suspended(reason, on)
	_sync_gameplay()


func _sync_gameplay() -> void:
	if not is_available:
		return
	var active := _gameplay_wanted and _suspend.is_empty()
	if active != _gameplay_active:
		_gameplay_active = active
		_bridge.gameplay(active)


# --- Облако и лидерборд -------------------------------------------------------

func _on_saved(data: Dictionary) -> void:
	# До загрузки облака не пишем: иначе свежая установка затёрла бы прогресс
	# игрока с другого устройства.
	if _cloud_ready:
		_push_cloud(data)


func _push_cloud(data: Dictionary) -> void:
	if is_available and _bridge != null:
		_bridge.saveData(JSON.stringify(data))


func _on_level_completed(_level: int, _stars: int, _score: int) -> void:
	submit_score(LEADERBOARD_NAME, GameState.total_score)
	# Отзыв — в момент победы на уровнях 11–15 (16.2a, 12.10b), один раз за сессию (и гостю: Яндекс ответит NO_AUTH,
	# окна не будет). SDK ещё нет или оценку в сессии уже запросили кнопкой — спросим на следующей победе.
	if _level >= REVIEW_FROM_LEVEL and _level <= REVIEW_TO_LEVEL and not GameState.review_prompted \
			and not _auto_review_tried and _request_review():
		_auto_review_tried = true


func _on_daily_completed(_date_key: String, streak: int, _stars: int, _score: int) -> void:
	submit_score(DAILY_LEADERBOARD_NAME, streak)


## Отправить value в таблицу board (16.3): только если он больше лучшего, что Яндекс уже принял
## (GameState.leaderboard_best). После сброса прогресса общий счёт и серия растут с нуля — в таблицу они уйдут,
## когда перерастут прежние; что Яндекс делает с меньшим результатом, не важно: меньший не отправляется.
## Принятое приходит событием score_set и запоминается в сохранении. true — отправлено.
func submit_score(board: String, value: int) -> bool:
	if not is_available or _bridge == null or value <= GameState.leaderboard_best(board):
		return false
	_bridge.setScore(board, value)
	return true


# --- Таблица лидеров и вход (18.3) --------------------------------------------

## Прочитать таблицу board (LEADERBOARD_NAME / DAILY_LEADERBOARD_NAME); ответ — сигнал leaderboard_loaded
## (всегда в следующем кадре или позже, даже из кэша и без SDK). force — мимо кэша (после входа).
func request_leaderboard(board: String, force: bool = false) -> void:
	if not is_available or _bridge == null:
		_emit_leaderboard.call_deferred(board, {"error": LB_NO_SDK})
		return
	var cached: Dictionary = _lb_cache.get(board, {})
	if not force and not cached.is_empty() \
			and Time.get_ticks_msec() - int(cached["at"]) < LEADERBOARD_CACHE_MS:
		_emit_leaderboard.call_deferred(board, cached["data"])
		return
	if _lb_pending.has(board):
		return  # ответ уже в пути — придёт сигналом
	_lb_pending[board] = true
	_bridge.lbEntries(board, LEADERBOARD_TOP, LEADERBOARD_AROUND)


## Открыть окно входа Яндекса (только по нажатию игрока). Итог — сигнал auth_changed; вошёл — облако
## сливается заново, очки и серия уходят в таблицы, кэш таблиц сброшен.
func open_auth() -> void:
	if not is_available or _bridge == null or is_authorized:
		return
	_auth_requested = true
	_bridge.openAuth()


## Отправить общий счёт и живую серию дней в таблицы (после входа: гостю Яндекс результат не записывает).
## Как и после уровня — только больше уже принятого (submit_score, 16.3).
func submit_scores() -> void:
	if not is_available or _bridge == null or not is_authorized:
		return
	submit_score(LEADERBOARD_NAME, GameState.total_score)
	var streak := GameState.daily_current_streak()
	if streak > GameState.leaderboard_best(DAILY_LEADERBOARD_NAME):
		get_tree().create_timer(RESUBMIT_GAP_SEC, true).timeout.connect(_submit_streak.bind(streak))


func _submit_streak(streak: int) -> void:
	if is_authorized:
		submit_score(DAILY_LEADERBOARD_NAME, streak)


func _emit_leaderboard(board: String, data: Dictionary) -> void:
	leaderboard_loaded.emit(board, data)


func _apply_auth(data: Variant) -> void:
	var d: Dictionary = data if data is Dictionary else {}
	var was := is_authorized
	var was_known := auth_known
	var review_after := _review_after_auth  # вход открыт кнопкой «Оценить игру»
	_review_after_auth = false
	is_authorized = bool(d.get("authorized", false))
	player_id = str(d.get("id", ""))
	auth_known = true
	if is_authorized != was:
		_lb_cache.clear()  # гостевой ответ — без строки игрока
	if is_authorized and not was and _auth_requested:
		_resubmit_after_cloud = true
	_auth_requested = false
	# Гость нажал «Оценить игру» и вошёл — сразу окно оценки (canReview внутри requestReview: уже оценивал — окна нет).
	# Иначе — можно ли просить оценку, зависит от входа (гостю — NO_AUTH): спросить, когда вход узнали и сменился.
	if review_after and is_authorized and not was:
		_request_review()
	elif not was_known or is_authorized != was:
		_check_review()
	auth_changed.emit(is_authorized)
	review_availability_changed.emit()  # гость: кнопка «Оценить игру» видна, как только вход известен; вход отменён — снова


func _on_leaderboard(data: Variant) -> void:
	var d: Dictionary = data if data is Dictionary else {}
	var board := str(d.get("name", ""))
	_lb_pending.erase(board)
	if not d.has("error"):
		_lb_cache[board] = {"at": Time.get_ticks_msec(), "data": d}
	leaderboard_loaded.emit(board, d)


## Remote-configured count of free hints for the current level.
func free_hints_per_level() -> int:
	return _free_hints


## Сердец на попытку (флаг hearts, 20.1a): 1..FLAG_HEARTS_MAX; 0 — без предела. Game читает в начале уровня.
func hearts() -> int:
	return _hearts


## С какого уровня основного пути сердца (флаг hearts_from_level). Задача дня — с сердцами всегда.
func hearts_from_level() -> int:
	return _hearts_from_level


## Возрождений за попытку уровня (флаг revive_max): 0 — сердца кончились, остаётся только «Заново».
func revive_max() -> int:
	return _revive_max


## Реклама за возрождение не показалась — один раз за попытку продолжить бесплатно (флаг revive_free_on_fail).
func revive_free_on_fail() -> bool:
	return _revive_free_on_fail


## Один запрос за сессию; запомнится (GameState.review_prompted) по ответу — событие review. true — запрос ушёл.
func _request_review() -> bool:
	if not is_available or _bridge == null or _review_requested_this_session:
		return false
	_review_requested_this_session = true
	_bridge.requestReview()
	review_availability_changed.emit()  # «Оценить игру» прячется: второго запроса в сессии Яндекс не даст
	return true


## Спросить у Яндекса, можно ли просить оценку (canReview); ответ — событие can_review.
func _check_review() -> void:
	if is_available and _bridge != null:
		_bridge.checkReview()


## Кнопку «Оценить игру» можно показать: в этой сессии оценку ещё не запрашивали (Яндекс даёт один запрос) и окно
## входа по ней не открыто. Вошедшему — пока Яндекс разрешает запросить оценку (canReview: игру не оценивал, окно оценки
## ему не показывали). Гостю — когда вход известен и окно оценки он ещё не видел (review_prompted): нажатие — вход,
## затем окно оценки. Вне Яндекс Игр — заглушка review_stub (отладочная сборка), пока SDK не грузится.
func can_offer_review() -> bool:
	if _review_requested_this_session or _review_after_auth:
		return false
	if is_available:
		if not is_authorized:
			return auth_known and _bridge != null and not GameState.review_prompted
		return _can_review
	return review_stub and not sdk_pending


## Игрок нажал «Оценить игру» (окно настроек): окно оценки Яндекса (canReview → requestReview, ответ — событие review,
## как у запроса после победы). Гость — сначала окно входа (open_auth); вошёл — окно оценки (_apply_auth), отказался —
## кнопка возвращается. Заглушка вне Яндекс Игр только прячет кнопку до конца сессии. false — нельзя (can_offer_review).
func request_review_by_player() -> bool:
	if not can_offer_review():
		return false
	if is_available and not is_authorized:
		_review_after_auth = true
		review_availability_changed.emit()  # кнопка прячется, пока открыто окно входа
		open_auth()
	elif is_available:
		_request_review()
	else:
		_review_requested_this_session = true
		print("YSDK: запрос оценки (заглушка вне Яндекс Игр)")
		review_availability_changed.emit()
	return true


## Флаги Remote Config и значения по умолчанию — строками, как их хранит консоль и отдаёт getFlags (16.2a).
## Единственный источник: JS-обёртка получает их отсюда (loadFlags), README «Remote Config» описывает их же.
static func flag_defaults() -> Dictionary:
	return {
		"interstitial_from_level": str(DEFAULT_INTERSTITIAL_FROM_LEVEL),
		"interstitial_interval_ms": str(DEFAULT_INTERSTITIAL_INTERVAL_MS),
		"free_hints_per_level": str(DEFAULT_FREE_HINTS_PER_LEVEL),
		"hearts": str(DEFAULT_HEARTS),
		"hearts_from_level": str(DEFAULT_HEARTS_FROM_LEVEL),
		"revive_max": str(DEFAULT_REVIVE_MAX),
		"revive_free_on_fail": str(DEFAULT_REVIVE_FREE_ON_FAIL),
	}


## Целое из флага key: строка-число (так отдаёт getFlags, пробелы по краям не мешают) или число — в пределах lo..hi;
## нет флага, пусто, не число ("abc", "1.5") — fallback. Прежде мусор становился нулём и прижимался к краю: реклама
## с первого уровня, ноль бесплатных подсказок.
static func flag_int(flags: Dictionary, key: String, fallback: int, lo: int, hi: int) -> int:
	var v: Variant = flags.get(key, null)
	if v is String:
		var t := (v as String).strip_edges()
		return clampi(t.to_int(), lo, hi) if t.is_valid_int() else fallback
	if v is int:
		return clampi(int(v), lo, hi)
	return fallback


func _apply_flags(data: Variant) -> void:
	var flags: Dictionary = data if data is Dictionary else {}
	interstitial_from_level = flag_int(flags, "interstitial_from_level", DEFAULT_INTERSTITIAL_FROM_LEVEL,
			FLAG_FROM_LEVEL_MIN, FLAG_FROM_LEVEL_MAX)
	interstitial_interval_ms = flag_int(flags, "interstitial_interval_ms", DEFAULT_INTERSTITIAL_INTERVAL_MS,
			FLAG_INTERVAL_MS_MIN, FLAG_INTERVAL_MS_MAX)
	_free_hints = flag_int(flags, "free_hints_per_level", DEFAULT_FREE_HINTS_PER_LEVEL, 0, FLAG_FREE_HINTS_MAX)
	_hearts = flag_int(flags, "hearts", DEFAULT_HEARTS, 0, FLAG_HEARTS_MAX)
	_hearts_from_level = flag_int(flags, "hearts_from_level", DEFAULT_HEARTS_FROM_LEVEL,
			FLAG_FROM_LEVEL_MIN, FLAG_FROM_LEVEL_MAX)
	_revive_max = flag_int(flags, "revive_max", DEFAULT_REVIVE_MAX, 0, FLAG_REVIVE_MAX)
	_revive_free_on_fail = flag_int(flags, "revive_free_on_fail", DEFAULT_REVIVE_FREE_ON_FAIL, 0, 1) != 0
	flags_ready = true
