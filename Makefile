.PHONY: test test-file lint clean

# Default test target
test:
	@echo "Running all tests..."
	nvim --headless --noplugin -u tests/minimal_init.vim -c "PlenaryBustedDirectory tests/ { minimal_init = './tests/minimal_init.vim' }"

# Run a specific test file
test-file:
ifdef FILE
	@echo "Running test file: $(FILE)"
	nvim --headless --noplugin -u tests/minimal_init.vim -c "PlenaryBustedFile $(FILE) { minimal_init = './tests/minimal_init.vim' }"
else
	@echo "Usage: make test-file FILE=tests/test_goto_preview.lua"
endif

# Lint Lua files
lint:
	@echo "Linting Lua files..."
	@if command -v luacheck >/dev/null 2>&1; then \
		luacheck lua/ tests/ --globals vim --read-globals vim; \
	else \
		echo "luacheck not found. Install with: luarocks install luacheck"; \
	fi

# Clean up any temporary files
clean:
	@echo "Cleaning up..."
	@find . -name "*.log" -delete
	@find . -name "*.tmp" -delete

# Help target
help:
	@echo "Available targets:"
	@echo "  test      - Run all tests"
	@echo "  test-file - Run specific test file (usage: make test-file FILE=path/to/test.lua)"
	@echo "  lint      - Lint Lua files with luacheck"
	@echo "  clean     - Clean up temporary files"
	@echo "  help      - Show this help message"
