# ==============================================================================
# 🛠️ CONFIGURATION
# ==============================================================================

# Compiler settings (switch CC to gcc for C projects)
CXX      := g++
CXXFLAGS := -Wall -Wextra -std=c++17 -O2
# LDFLAGS  := -lsecurity             # Uncomment to link external libraries

# Project structure
TARGET   := my_program
SRC_DIR  := src
OBJ_DIR  := obj
BIN_DIR  := bin

# ==============================================================================
# 🔍 AUTOMATIC FILE RESOLUTION
# ==============================================================================

# Finds all .cpp files inside SRC_DIR (switch to *.c for C projects)
SRCS := $(wildcard $(SRC_DIR)/*.cpp)

# Maps source files to object and dependency files
OBJS := $(SRCS:$(SRC_DIR)/%.cpp=$(OBJ_DIR)/%.o)
DEPS := $(OBJS:.o=.d)

# Final executable output path
EXE  := $(BIN_DIR)/$(TARGET)

# ==============================================================================
# 🎯 BUILD RULES
# ==============================================================================

# Default rule (runs when you type 'make')
.PHONY: all
all: $(EXE)

# Rule to link the final executable
$(EXE): $(OBJS) | $(BIN_DIR)
	$(CXX) $(OBJS) -o $@ $(LDFLAGS)
	@echo "🎉 Build successful! Executable created at: $@"

# Rule to compile source files into object files
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.cpp | $(OBJ_DIR)
	$(CXX) $(CXXFLAGS) -MMD -MP -c $< -o $@

# Order-only prerequisites to guarantee output directories exist
$(BIN_DIR) $(OBJ_DIR):
	mkdir -p $@

# Include generated dependency (.d) files to track header changes
-include $(DEPS)

# ==============================================================================
# 🧹 CLEANUP & UTILITIES
# ==============================================================================

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR)
	@echo "🧹 Workspace cleaned."

# Run the program instantly
.PHONY: run
run: all
	@./$(EXE)
