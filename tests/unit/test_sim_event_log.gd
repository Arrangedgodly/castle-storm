## Unit tests for the pooled ring-buffer event stream (T-SIM-01).
## Mirrors sim/sim_event_log.gd + sim/sim_event.gd.
extends GdUnitTestSuite


func test_record_and_read_back_in_order() -> void:
	var log := SimEventLog.new(8)
	log.record(1, &"hour_struck", &"sim", 1)
	log.record(2, &"ping_counted", &"heartbeat", 5, 7)
	assert_int(log.next_seq()).is_equal(2)
	assert_int(log.oldest_seq()).is_equal(0)
	var first := log.get_event(0)
	var second := log.get_event(1)
	assert_str(String(first.type)).is_equal("hour_struck")
	assert_int(first.tick).is_equal(1)
	assert_int(first.seq).is_equal(0)
	assert_str(String(second.type)).is_equal("ping_counted")
	assert_int(second.value).is_equal(5)
	assert_int(second.value2).is_equal(7)


func test_unwritten_seq_returns_null() -> void:
	var log := SimEventLog.new(8)
	log.record(1, &"a")
	assert_that(log.get_event(1)).is_null() # not yet written
	assert_that(log.get_event(-1)).is_null()


func test_ring_evicts_oldest_at_capacity() -> void:
	var log := SimEventLog.new(4)
	for i in 6:
		log.record(i + 1, &"tick_event", &"sim", i)
	# 6 written, capacity 4 -> seq 0 and 1 evicted, 2..5 readable.
	assert_int(log.next_seq()).is_equal(6)
	assert_int(log.oldest_seq()).is_equal(2)
	assert_that(log.get_event(0)).is_null()
	assert_that(log.get_event(1)).is_null()
	var survivor := log.get_event(2)
	assert_that(survivor).is_not_null()
	assert_int(survivor.value).is_equal(2)
	var newest := log.get_event(5)
	assert_int(newest.value).is_equal(5)
	assert_int(newest.tick).is_equal(6)


func test_ring_reuses_pooled_events_without_growth() -> void:
	var log := SimEventLog.new(4)
	var original := log.get_event(0)
	assert_that(original).is_null() # nothing recorded yet
	log.record(1, &"a", &"", 1)
	var first_ref := log.get_event(0)
	# Push 4 more events: seq 0's slot (0 % 4) is overwritten by seq 4.
	for i in 4:
		log.record(2 + i, &"b", &"", 10 + i)
	assert_int(log.get_event(0)).is_null() # evicted...
	# ...and the pooled object itself was reused in place:
	assert_str(String(first_ref.type)).is_equal("b")
	assert_int(first_ref.value).is_equal(13)
	assert_int(first_ref.seq).is_equal(4)


func test_default_capacity_is_4096() -> void:
	var log := SimEventLog.new()
	assert_int(log.capacity()).is_equal(4096)
	var engine := SimEngine.new(1)
	assert_int(engine.events.capacity()).is_equal(4096)
