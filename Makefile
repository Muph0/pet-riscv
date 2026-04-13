.PHONY: list sim_pc sim_if sim_uart_rx clean

list:
	fusesoc --cores-root . core list

sim_pc:
	fusesoc --cores-root . run --target sim_pc ::rv32im

sim_if:
	fusesoc --cores-root . run --target sim_if ::rv32im

sim_uart_rx:
	fusesoc --cores-root . run --target sim_uart_rx ::rv32im

sim_cpu_top:
	fusesoc --cores-root . run --target sim_cpu_top ::rv32im

clean:
	rm -rf build
