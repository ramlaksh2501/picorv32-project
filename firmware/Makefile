TOOLCHAIN_PREFIX ?= riscv64-unknown-elf-

CC      = $(TOOLCHAIN_PREFIX)gcc
OBJCOPY = $(TOOLCHAIN_PREFIX)objcopy
OBJDUMP = $(TOOLCHAIN_PREFIX)objdump

CFLAGS  = -march=rv32i -mabi=ilp32 -mno-relax -O2 -ffreestanding -Wall -Iinclude -Imemory_map
LDFLAGS = -T sections.ld -nostdlib -Wl,--no-relax

SRC_DIR = src
BUILD_DIR = build
BIN_DIR = ../binaries

SRCS = $(SRC_DIR)/start.s \
       $(SRC_DIR)/uart.c \
       $(SRC_DIR)/led.c \
       $(SRC_DIR)/delay.c \
       $(SRC_DIR)/aes.c \
       $(SRC_DIR)/main.c

OBJS = $(patsubst $(SRC_DIR)/%.s,$(BUILD_DIR)/%.o,$(filter %.s,$(SRCS))) \
       $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(filter %.c,$(SRCS)))

TARGET_ELF = $(BUILD_DIR)/app.elf
TARGET_BIN = $(BIN_DIR)/app.bin
TARGET_HEX = $(BIN_DIR)/app.hex

COM ?= COM15
PYTHON ?= python3

all: $(TARGET_BIN) $(TARGET_HEX)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.s | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET_ELF): $(OBJS) sections.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS)

$(TARGET_BIN): $(TARGET_ELF) | $(BIN_DIR)
	$(OBJCOPY) -O binary $< $@

$(TARGET_HEX): $(TARGET_BIN) | $(BIN_DIR)
	$(PYTHON) tools/makehex.py $< $@ 8192

disasm: $(TARGET_ELF)
	$(OBJDUMP) -d $< > $(BUILD_DIR)/app.dis

upload: $(TARGET_BIN)
	$(PYTHON) tools/upload.py $(COM) $(TARGET_BIN)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean disasm upload
