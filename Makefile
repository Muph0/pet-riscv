.PHONY: list sim_pc sim_if sim_uart_rx sim_cpu_boot_decode clean

list:
	fusesoc --cores-root . core list

sim_pc:
	fusesoc --cores-root . run --target sim_pc ::rv32im

sim_if:
	fusesoc --cores-root . run --target sim_if ::rv32im

sim_uart_rx:
	fusesoc --cores-root . run --target sim_uart_rx ::rv32im

sim_cpu_boot_decode: tests/sample1.bin
	fusesoc --cores-root . run --target sim_cpu_boot_decode ::rv32im

clean:
	rm -rf build

%.bin: %.s
	unas --arch=rv32i $< -o $@