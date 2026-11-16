CFLAGS ?= -W -Wall -Wextra -Werror -Wundef -Wshadow -Wdouble-promotion \
					-Wformat-truncation -fno-common -Wconversion \
					-g3 -O0 -ffunction-sections -fdata-sections -I. \
					-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 -mfloat-abi=hard $(EXTRA_CFLAGS)
LDFLAGS ?= -Tf446re.ld -nostartfiles -nostdlib --specs nano.specs -lc -lgcc -Wl,--gc-sections -Wl,-Map=$@.map

SOURCES = startup.c main.c gpio.c i2c.c display.c rom.S

ROM ?= ../rom/ibm_logo.ch8

ZIG_SRC = ../src/stm32_frontend.zig
ZIG_DEPS = $(wildcard ../src/*.zig)
ZIG_OBJ = stm32_frontend.o
ZIGFLAGS = -target thumb-freestanding-eabihf -mcpu cortex_m4 -O ReleaseSmall -fno-unwind-tables

build: firmware.elf


$(ZIG_OBJ): $(ZIG_DEPS)
	zig build-obj $(ZIGFLAGS) -femit-bin=$@ $(ZIG_SRC)

rom.bin: FORCE
	@cp "$(ROM)" rom.tmp
	@cmp -s rom.tmp rom.bin || mv rom.tmp rom.bin
	@rm -f rom.tmp

firmware.elf: $(SOURCES) $(ZIG_OBJ) chip8_frontend.h rom.bin
	arm-none-eabi-gcc $(SOURCES) $(ZIG_OBJ) $(CFLAGS) $(LDFLAGS) -o $@

firmware.bin: firmware.elf
	arm-none-eabi-objcopy -O binary $< $@

flash: firmware.bin
	st-flash --connect-under-reset --reset write $< 0x08000000

clean: 
	rm -rf firmware.* $(ZIG_OBJ) rom.bin rom.tmp

.PHONY: all clean flash FORCE

FORCE:
