.PHONY: all build run clean help

# Default target
all: build

# Build the macOS App using xcodebuild
build:
	xcodebuild -project GhostWriter/GhostWriter.xcodeproj \
		-scheme GhostWriter \
		-configuration Debug \
		-derivedDataPath build

# Run the compiled macOS App binary directly in the terminal
run:
	./build/Build/Products/Debug/GhostWriter.app/Contents/MacOS/GhostWriter

# Clean build artifacts
clean:
	rm -rf build

# Display helper documentation
help:
	@echo "GhostWriter Build Commands:"
	@echo "  make build  - Compile and build the GhostWriter.app bundle using xcodebuild"
	@echo "  make run    - Execute the compiled app binary in the foreground (outputs logs to console)"
	@echo "  make clean  - Remove all build outputs"
