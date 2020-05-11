derive_pll_clocks
derive_clock_uncertainty;

set_multicycle_path -to {emu|video|video_mixer|*} -setup 2
set_multicycle_path -to {emu|video|video_mixer|*} -hold 1

set_multicycle_path -to {emu|cpu_z80|*} -setup 2
set_multicycle_path -to {emu|cpu_z80|*} -hold 1

set_multicycle_path -to {emu|cpu_i80|*} -setup 2
set_multicycle_path -to {emu|cpu_i80|*} -hold 1
