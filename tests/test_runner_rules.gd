extends TestCase
## The test runner's own rules, with known answers. If these go red, a green suite stops meaning anything.


func test_an_unexpected_error_fails() -> void:
	var r := TestCase.reconcile_engine_messages([{"warning": false, "text": "boom"}], [], [], [])
	assert_eq(r["failures"].size(), 1, "an error nobody declared fails the test")


func test_a_declared_error_passes_and_a_missing_one_fails() -> void:
	var ok := TestCase.reconcile_engine_messages([{"warning": false, "text": "no level called 'x'"}], [], ["no level called"], [])
	assert_eq(ok["failures"].size(), 0, "declared and seen: fine")
	var missing := TestCase.reconcile_engine_messages([], [], ["no level called"], [])
	assert_eq(missing["failures"].size(), 1, "declared but never seen: fails (the behaviour changed)")


func test_warnings_fail_too_unless_allowed() -> void:
	var r := TestCase.reconcile_engine_messages([{"warning": true, "text": "careful"}], [], [], [])
	assert_eq(r["failures"].size(), 1, "an undeclared warning fails")
	var allowed := TestCase.reconcile_engine_messages([{"warning": true, "text": "careful"}], [], [], ["careful"])
	assert_eq(allowed["failures"].size(), 0, "an allowlisted one does not")
