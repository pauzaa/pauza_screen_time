.PHONY: test-android
test-android: ## Run Android native unit tests (pauza_screen_time plugin). Use TEST=ClassName or TEST=ClassName.methodName to filter.
	cd example/android && JAVA_HOME="$$(echo /Applications/Android\ Studio*.app/Contents/jbr/Contents/Home)" ./gradlew $(if $(TEST),:pauza_screen_time:testDebugUnitTest --tests "*.$(TEST)",:pauza_screen_time:test) --console=plain; \
	echo ""; \
	echo "=== Test Summary ==="; \
	bash ../../scripts/test_summary.sh
