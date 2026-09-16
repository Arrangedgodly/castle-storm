## CardMotion — the entrance grammar + the offline flip queue (T-UI-04).
##
## The design brief's motion vocabulary names three transitions: the FLIP
## lives on CardFrame (the seam), the UNFOLD is T-UI-05's, and the third —
## SLIDE-AND-SETTLE, "cards joining the spread" — lives here. A newly
## dealt card (a recruit at the gate, a body joining the estate) slides in
## from the table's head — the top-right, where the deck sits — with
## exactly ONE overshoot damping (TRANS_BACK out: the card slides past its
## registration and settles back, the same easing family as the flip's
## landing — one motion grammar, not a bag of eases).
##
## Entrances are opt-in per card: the screen deals only cards that JOIN a
## live table (the boot deal is the unfold's business, T-UI-05). The card
## must ALREADY be laid out (the container's sort sets the final rect; the
## slide offsets FROM final), and snap()/snap_all() land a card mid-slide
## the moment the table re-lays itself — a re-sort can never strand a card
## short of its seat. Reduced motion (MotionProfile) skips the slide
## entirely and fires the completion callback synchronously.
##
## The PromotionFlipQueue below is the OFFLINE half of the signature
## moment: army promotions that land while the host drains a foreground
## catch-up window replay as capped, staggered flips instead of fifty
## simultaneous card turns.
class_name CardMotion
extends RefCounted

## Where dealt cards come from: the table's head (top-right corner).
const DEAL_OFFSET := Vector2(170.0, -110.0)

const SETTLING_META := &"card_motion_settling"
const FINAL_META := &"card_motion_final"
const TWEEN_META := &"card_motion_tween"
const DONE_META := &"card_motion_done"


## Deal a card in: slide from the deck offset to its laid position with
## one overshoot damping. Call AFTER the container laid the card out (the
## final rect is read here). `on_done` fires EXACTLY ONCE — synchronously
## when reduced motion skips the slide, at the tween's end otherwise, and
## on snap() if the slide was interrupted.
static func settle_in(card: Control, on_done: Callable = Callable()) -> void:
	if card == null or not is_instance_valid(card):
		return
	var final_position: Vector2 = card.position
	card.set_meta(FINAL_META, final_position)
	card.remove_meta(DONE_META)
	if not MotionProfile.entrances_enabled():
		_finish(card, on_done)
		return
	card.set_meta(SETTLING_META, true)
	card.set_meta(DONE_META, on_done)
	card.position = final_position + DEAL_OFFSET
	var tween := card.create_tween()
	tween.tween_property(card, "position", final_position, MotionProfile.duration(MotionProfile.SETTLE_SECONDS)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		card.set_meta(SETTLING_META, false)
		_finish(card, Callable()))
	card.set_meta(TWEEN_META, tween)


## True while a card's entrance slide is in flight.
static func is_settling(card: Control) -> bool:
	return card != null and is_instance_valid(card) and bool(card.get_meta(SETTLING_META, false))


## Land a settling card on its seat right now (fires its completion once).
static func snap(card: Control) -> void:
	if card == null or not is_instance_valid(card) or not is_settling(card):
		return
	var tween: Tween = card.get_meta(TWEEN_META)
	if tween != null and tween.is_valid():
		tween.kill()
	card.set_meta(SETTLING_META, false)
	if card.has_meta(FINAL_META):
		card.position = card.get_meta(FINAL_META)
	var on_done: Callable = card.get_meta(DONE_META, Callable())
	_finish(card, on_done)


## Snap every settling direct child of a node (the table re-laid itself).
static func snap_all(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		if child is Control:
			snap(child)


static func _finish(card: Control, on_done: Callable) -> void:
	## Fire the completion exactly once: the DONE meta is the latch (a
	## tween-end after a snap, or a snap after tween-end, must not re-fire).
	if on_done.is_valid():
		card.remove_meta(DONE_META)
		on_done.call()
	else:
		var latched: Callable = card.get_meta(DONE_META, Callable())
		if latched.is_valid():
			card.remove_meta(DONE_META)
			latched.call()


## The offline promotion replay queue: `unit_promoted` events delivered
## while GameHost.delivering_catch_up is true (the away window's batch)
## queue a REPLAY flip instead of an immediate one — coming back to a
## table where fifty cards flipped at once is noise, so the queue keeps
## only the LATEST `cap` promotions (default 3, the task's guidance) and
## the foreground boundary replays them staggered. Older promotions stay
## printed (the full refresh already shows them; the catch-up report is
## T-UI-09's to summarize).
class PromotionFlipQueue:
	## How many offline flips may replay on one foreground (latest wins).
	var cap := 3

	var _queued: Array[String] = []


	## Queue one promoted card (a re-queue moves it to the back — latest).
	func push(card_id: String) -> void:
		_queued.erase(card_id)
		_queued.append(card_id)
		while _queued.size() > cap:
			_queued.pop_front()


	func size() -> int:
		return _queued.size()


	## Drain the queue (oldest first — the replay plays in arrival order).
	func take_all() -> Array[String]:
		var all := _queued.duplicate()
		_queued.clear()
		return all
