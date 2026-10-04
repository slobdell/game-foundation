class_name TestCase
extends RefCounted
## Base class for every test. `tests/run_tests.gd` finds files named test_*.gd, makes a fresh instance for each
## `test_*` method, calls it (awaiting it), then tears down.
##
## Assertions RECORD failures instead of stopping, so one run tells you everything that is wrong.
## Nodes added with `add_to_tree()` are freed after the test, and a test that leaves physics bodies behind fails:
## leftovers make the NEXT test fail for no reason, and the test that leaked is the one that should go red.

var tree: SceneTree
var failures: PackedStringArray = []
var expected_warnings: PackedStringArray = []
var expected_errors: PackedStringArray = []
var _owned_nodes: Array[Node] = []
static var _bodies_baseline := -1


## This test deliberately triggers a `push_warning` matching [param pattern] (substring, or a glob with * / ?).
## Engine warnings and errors fail a test by default; declaring one that never arrives ALSO fails, so a
## declaration cannot quietly outlive the behaviour it describes.
func expect_warning(pattern: String) -> void:
	expected_warnings.append(pattern)


## The same for `push_error`: how you test a path that is SUPPOSED to refuse loudly.
func expect_error(pattern: String) -> void:
	expected_errors.append(pattern)


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func assert_false(condition: bool, message: String) -> void:
	if condition:
		failures.append(message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, expected, actual])


func assert_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s (expected %s ± %s, got %s)" % [message, expected, tolerance, actual])


## Add a node to the running scene tree; it is freed after the test.
func add_to_tree(node: Node) -> Node:
	tree.root.add_child(node)
	_owned_nodes.append(node)
	return node


## Let physics run. Movement and collisions only happen on physics frames: await this after you push something.
func wait_physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


func wait_frames(count: int) -> void:
	for i in count:
		await tree.process_frame


## Free everything this test added (safe to call mid-test for a clean world).
func free_owned() -> void:
	for node in _owned_nodes:
		if is_instance_valid(node):
			node.free()
	_owned_nodes.clear()


## Override for extra cleanup; keep calling super.teardown().
func teardown() -> void:
	free_owned()


## Called by the runner. Not overridable on purpose: it owns the order (hook, free, leak check).
func _teardown() -> void:
	teardown()
	free_owned()
	await tree.process_frame
	var bodies := _count_bodies(tree.root)
	if _bodies_baseline >= 0 and bodies > _bodies_baseline:
		failures.append("left %d physics bodies in the world (was %d before). Free every node you add, or use add_to_tree()."
				% [bodies, _bodies_baseline])
	_bodies_baseline = maxi(_bodies_baseline, bodies)


func _count_bodies(node: Node) -> int:
	var n := 1 if node is CollisionObject3D or node is CollisionObject2D else 0
	for child in node.get_children():
		n += _count_bodies(child)
	return n


## Match the engine messages a test produced against what it declared. Static so it can be tested itself.
## Returns {"failures": PackedStringArray, "errors": int, "warnings": int}.
static func reconcile_engine_messages(entries: Array, expected_warn: PackedStringArray,
		expected_err: PackedStringArray, allowed: PackedStringArray) -> Dictionary:
	var failures: PackedStringArray = []
	var errors := 0
	var warnings := 0
	var warn_left := expected_warn.duplicate()
	var err_left := expected_err.duplicate()
	for entry: Dictionary in entries:
		var text: String = entry.get("text", "")
		if _first_match(allowed, text) >= 0:
			continue
		var is_warning: bool = entry.get("warning", false)
		var pool := warn_left if is_warning else err_left
		var hit := _first_match(pool, text)
		if hit >= 0:
			pool.remove_at(hit)
			continue
		if is_warning:
			warnings += 1
			failures.append("engine warning: " + text)
		else:
			errors += 1
			failures.append("engine error: " + text)
	for pattern in warn_left:
		failures.append("expected a warning matching '%s' and none came" % pattern)
	for pattern in err_left:
		failures.append("expected an error matching '%s' and none came" % pattern)
	return {"failures": failures, "errors": errors, "warnings": warnings}


static func _first_match(patterns: PackedStringArray, text: String) -> int:
	for index in patterns.size():
		var pattern := patterns[index]
		if pattern == "":
			continue
		if pattern.contains("*") or pattern.contains("?"):
			if text.match(pattern):
				return index
		elif text.contains(pattern):
			return index
	return -1
