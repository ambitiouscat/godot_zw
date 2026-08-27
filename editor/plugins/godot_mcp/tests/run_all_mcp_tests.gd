@tool
extends SceneTree

## Headless test runner for Godot MCP unit and contract test suites.

func _init() -> void:
	print("==================================================")
	print("Running Godot MCP Dual-Track Architecture Test Suite")
	print("==================================================")

	var total_passed := 0
	var total_failed := 0
	var all_errors: Array = []

	var suites := [
		preload("res://addons/godot_mcp/tests/test_contract.gd"),
		preload("res://addons/godot_mcp/tests/test_lifecycle_coordinator.gd"),
		preload("res://addons/godot_mcp/tests/test_command_router.gd"),
	]

	for suite in suites:
		var res: Dictionary = suite.run_all_tests()
		total_passed += int(res.get("passed", 0))
		total_failed += int(res.get("failed", 0))
		for err in res.get("errors", []):
			all_errors.append(err)

	print("--------------------------------------------------")
	print("Test Results: %d PASSED, %d FAILED" % [total_passed, total_failed])
	if total_failed > 0:
		print("Failures:")
		for err in all_errors:
			print("  - " + str(err))
		print("==================================================")
		quit(1)
	else:
		print("ALL DUAL-TRACK MCP TESTS PASSED SUCCESSFULLY!")
		print("==================================================")
		quit(0)
