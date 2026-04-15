.PHONY: list sim_pc sim_if sim_uart_rx sim_cpu_boot_decode sim_cpu_top_fwd sim_cpu_top_lw clean

list:
	fusesoc --cores-root . core list || true
	rm -r build

sim_pc:
	fusesoc --cores-root . run --target sim_pc ::rv32im || true
	rm -r build

sim_if:
	fusesoc --cores-root . run --target sim_if ::rv32im || true
	rm -r build

sim_uart_rx:
	fusesoc --cores-root . run --target sim_uart_rx ::rv32im || true
	rm -r build

sim_cpu_boot_decode: tests/sample1.bin
	fusesoc --cores-root . run --target sim_cpu_boot_decode ::rv32im || true
	rm -r build

sim_cpu_top_fwd: tests/sample_fw.bin
	fusesoc --cores-root . run --target sim_cpu_top_fwd ::rv32im

sim_cpu_top_lw: tests/sample_lw.bin
	fusesoc --cores-root . run --target sim_cpu_top_lw ::rv32im || true
	rm -r build

clean:
	rm -rf build
	rm -f tests/*.bin

%.bin: %.s
	unas --arch=rv32i $< -o $@
