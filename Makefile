.PHONY: list sim_uart_rx sim_bus_xbar sim_bus_xbar_atomic sim_cpu_boot_decode sim_cpu_fwd sim_cpu_lw sim_cpu_fib sim_cpu_uart_echo sim_cpu_boot_echo sim_cpu_memtest clean rust

RM_BUILD ?= true

list:
	fusesoc --cores-root . core list || true
	if $(RM_BUILD); then rm -rf build; fi

sim_uart_rx:
	@echo RM_BUILD is $(RM_BUILD)
	fusesoc --cores-root . run --target sim_uart_rx ::rv32im || true
	if $(RM_BUILD); then rm -rf build; fi

sim_cpu_boot_decode: tests/sample1.bin
	fusesoc --cores-root . run --target sim_cpu_boot_decode ::rv32im || true
	if $(RM_BUILD); then rm -rf build; fi

sim_cpu_fwd: tests/sample_fw.bin
	fusesoc --cores-root . run --target sim_cpu_fwd ::rv32im

sim_cpu_lw: tests/sample_lw.bin
	fusesoc --cores-root . run --target sim_cpu_lw ::rv32im || true
	if $(RM_BUILD); then rm -rf build; fi

sim_cpu_fib: tests/sample_fib.bin
	fusesoc --cores-root . run --target sim_cpu_fib ::rv32im || true
	if $(RM_BUILD); then rm -rf build; fi

sim_cpu_uart_echo: tests/sample_uart_echo.bin
	fusesoc --cores-root . run --target sim_cpu_uart_echo ::rv32im || true
	if $(RM_BUILD); then rm -rf build; fi

sim_cpu_boot_echo: asm/boot_echo.bin
	fusesoc --cores-root . run --target sim_cpu_boot_echo ::rv32im || true
	if $(RM_BUILD); then rm -rf build; fi

sim_cpu_memtest: rust
	fusesoc --cores-root . run --target sim_cpu_memtest ::rv32im || true
	if $(RM_BUILD); then rm -rf build; fi

sim_bus_xbar:
	fusesoc --cores-root . run --target sim_bus_xbar ::rv32im || true
	if $(RM_BUILD); then rm -rf build; fi

sim_bus_xbar_atomic:
	fusesoc --cores-root . run --target sim_bus_xbar_atomic ::rv32im || true
	if $(RM_BUILD); then rm -rf build; fi

test_all:
	make RM_BUILD=false sim_uart_rx sim_cpu_boot_decode sim_cpu_fwd sim_cpu_lw sim_cpu_fib sim_cpu_uart_echo sim_cpu_boot_echo sim_bus_xbar sim_bus_xbar_atomic
	rm -rf build

clean:
	rm -rf build
	rm -f tests/*.bin

define rust_bin
	cd rust ; \
	cargo objcopy --release --bin $(1) -- -O binary --only-section=.text --only-section=.rodata --only-section=.data ./$(1).bin
endef

rust:
	$(call rust_bin,hello)
	$(call rust_bin,memtest)



asm/%.bin tests/%.bin: %.s
	unas --arch=rv32i $< -o $@
