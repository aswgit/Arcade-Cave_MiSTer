-------------------------------------------------------------------------------
--
-- Copyright (c) 2019 Rick Wertenbroek <rick.wertenbroek@gmail.com>
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- 2. Redistributions in binary form must reproduce the above copyright notice,
-- this list of conditions and the following disclaimer in the documentation
-- and/or other materials provided with the distribution.
--
-- 3. Neither the name of the copyright holder nor the names of its
-- contributors may be used to endorse or promote products derived from this
-- software without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-------------------------------------------------------------------------------
-- File         : cave.vhd
-- Description  : Dodonpachi - contains :
--                The Main Processor a motorola 68000
--                The RAMs
--                The Graphic Hardware (sprites and layers)
--
-- Author       : Rick Wertenbroek
-- Version      : 0.2
--
-- Dependencies : All of its contents
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cave_pkg.all;

entity cave is
    generic (
        INCLUDE_GRAPHIC_PROCESSOR_G : boolean := true;
        INCLUDE_EEPROM_G            : boolean := false);
    port (
        -- Fast clock domain
        rst_i                    : in  std_logic;
        clk_fast_i               : in  std_logic;
        -- CPU clock domain
        rst_68k_i                : in  std_logic;
        clk_68k_i                : in  std_logic;
        -- Player input signals
        player_1_i               : in  std_logic_vector(8 downto 0);
        player_2_i               : in  std_logic_vector(8 downto 0);
        pause_i                  : in  std_logic;
        -- 68k ROM
        rom_addr_68k_o           : out unsigned(DDP_ROM_LOG_SIZE_C-1 downto 0);
        rom_read_68k_o           : out std_logic;
        rom_valid_68k_i          : in  std_logic;
        rom_data_68k_i           : in  word_t;
        -- GFX signals (clocked with clk_fast)
        rom_addr_gfx_o           : out gfx_rom_addr_t;
        tiny_burst_gfx_o         : out std_logic;
        rom_burst_read_gfx_o     : out std_logic;
        rom_data_valid_gfx_i     : in  std_logic;
        rom_data_gfx_i           : in  gfx_rom_data_t;
        rom_burst_done_gfx_i     : in  std_logic;
        -- Frame Buffer
        frame_buffer_addr_o      : out frame_buffer_addr_t;
        frame_buffer_data_o      : out std_logic_vector(DDP_WORD_WIDTH-2 downto 0);
        frame_buffer_write_o     : out std_logic;
        frame_buffer_dma_start_o : out std_logic;
        frame_buffer_dma_done_i  : in  std_logic;
        -- Vertical blank signal
        vblank_i                 : in std_logic;
        -- Debug signals
        TG68_PC_o                : out std_logic_vector(31 downto 0);
        TG68_PCW_o               : out std_logic
        );
end entity cave;

architecture struct of cave is

    -- Processor related signals
    signal rst_68k_s                       : std_logic;
    signal n_rst_68k_s                     : std_logic;
    signal n_data_ack_68k_s                : std_logic;
    signal addr_68k_s                      : unsigned(31 downto 0);  -- only 24 MSB bits used
    signal data_out_68k_s                  : word_t;
    signal n_addr_strobe_68k_s             : std_logic;
    signal addr_strobe_68k_s               : std_logic;
    signal addr_strobe_68k_old_reg_s       : std_logic;
    signal n_upper_data_select_68k_s       : std_logic;
    signal upper_data_select_68k_s         : std_logic;
    signal upper_data_select_68k_old_reg_s : std_logic;
    signal n_lower_data_select_68k_s       : std_logic;
    signal lower_data_select_68k_s         : std_logic;
    signal lower_data_select_68k_old_reg_s : std_logic;
    signal read_n_write_68k_s              : std_logic;
    signal n_ipl_to_68k_s                  : std_logic_vector(2 downto 0);
    signal ipl_s                           : std_logic_vector(2 downto 0);
    signal other_ack_s                     : std_logic;
    signal other_data_o_s                  : word_t;

    -- Memory bus related signals
    signal memory_bus_ack_s         : std_logic;
    signal memory_bus_data_s        : word_t;
    signal read_strobe_s            : std_logic;
    signal write_strobe_s           : std_logic;
    signal high_write_strobe_s      : std_logic;
    signal low_write_strobe_s       : std_logic;
    -- ROM
    constant ROM_LOG_SIZE_C         : natural := DDP_ROM_LOG_SIZE_C;  -- 1MB
    signal rom_ack_s                : std_logic;
    signal rom_data_o_s             : word_t;
    signal rom_enable_s             : std_logic;
    -- RAM
    constant RAM_LOG_SIZE_C         : natural := 16;  -- 64kB
    signal ram_enable_s             : std_logic;
    signal ram_ack_s                : std_logic;
    signal ram_data_o_s             : word_t;
    -- YMZ RAM
    constant YMZ_RAM_LOG_SIZE_C     : natural := 2;   -- 4B
    signal ymz_ram_enable_s         : std_logic;
    signal ymz_ram_ack_s            : std_logic;
    signal ymz_ram_data_o_s         : word_t;
    -- Sprite RAM
    constant SPRITE_RAM_LOG_SIZE_C  : natural := 16;  -- 64kB
    signal sprite_ram_enable_s      : std_logic;
    signal sprite_ram_ack_s         : std_logic;
    signal sprite_ram_data_o_s      : word_t;
    -- Layer 0 RAM
    constant LAYER_0_RAM_LOG_SIZE_C : natural := 15;  -- 32kB
    signal layer_0_ram_enable_s     : std_logic;
    signal layer_0_ram_ack_s        : std_logic;
    signal layer_0_ram_data_o_s     : word_t;
    -- Layer 1 RAM
    constant LAYER_1_RAM_LOG_SIZE_C : natural := 15;  -- 32kB
    signal layer_1_ram_enable_s     : std_logic;
    signal layer_1_ram_ack_s        : std_logic;
    signal layer_1_ram_data_o_s     : word_t;
    -- Layer 2 RAM
    constant LAYER_2_RAM_LOG_SIZE_C : natural := 16;  -- 64kB
    signal layer_2_ram_enable_s     : std_logic;
    signal layer_2_ram_ack_s        : std_logic;
    signal layer_2_ram_data_o_s     : word_t;
    -- Video Registers (should not necessarily be ram) (write only)
    constant VIDEO_REGS_LOG_SIZE_C  : natural := 7;   -- 128B
    signal video_regs_enable_s      : std_logic;
    signal video_regs_ack_s         : std_logic;
    -- IRQ Cause (read only)
    signal irq_cause_enable_s       : std_logic;
    signal irq_cause_ack_s          : std_logic;
    signal irq_cause_data_o_s       : word_t;
    -- Video Control Registers 0
    constant V_CTRL_0_LOG_SIZE_C    : natural := 3;   -- 8B (actually 6B)
    signal v_ctrl_0_enable_s        : std_logic;
    signal v_ctrl_0_ack_s           : std_logic;
    signal v_ctrl_0_data_o_s        : word_t;
    -- Video Control Registers 1
    constant V_CTRL_1_LOG_SIZE_C    : natural := 3;   -- 8B (actually 6B)
    signal v_ctrl_1_enable_s        : std_logic;
    signal v_ctrl_1_ack_s           : std_logic;
    signal v_ctrl_1_data_o_s        : word_t;
    -- Video Control Registers 2
    constant V_CTRL_2_LOG_SIZE_C    : natural := 3;   -- 8B (actually 6B)
    signal v_ctrl_2_enable_s        : std_logic;
    signal v_ctrl_2_ack_s           : std_logic;
    signal v_ctrl_2_data_o_s        : word_t;
    -- Palette RAM
    constant PALETTE_RAM_LOG_SIZE_C : natural := 16;  -- 64kB
    signal palette_ram_enable_s     : std_logic;
    signal palette_ram_ack_s        : std_logic;
    signal palette_ram_data_o_s     : word_t;
    -- Inputs 0
    constant IN_0_LOG_SIZE_C        : natural := 1;   -- 2B
    signal in_0_enable_s            : std_logic;
    signal in_0_ack_s               : std_logic;
    signal in_0_data_o_s            : word_t;
    -- Inputs 1
    constant IN_1_LOG_SIZE_C        : natural := 1;   -- 2B
    signal in_1_enable_s            : std_logic;
    signal in_1_ack_s               : std_logic;
    signal in_1_data_o_s            : word_t;
    -- EEPROM
    constant EEPROM_LOG_SIZE_C      : natural := 1;   -- 2B
    signal eeprom_enable_s          : std_logic;
    signal eeprom_ack_s             : std_logic;
    signal eeprom_data_o_s          : word_t;
    signal eeprom_ci_s              : std_logic;
    signal eeprom_cs_s              : std_logic;
    signal eeprom_di_s              : std_logic;
    signal eeprom_do_s              : std_logic;
    -- Edge Cases
    signal edge_case_enable_s       : std_logic;
    signal edge_case_ack_s          : std_logic;
    -- No data for edge cases (will be 0 since the bus is OR'ed)

    signal addr_68k_32b_s           : unsigned(31 downto 0);

    signal frame_buffer_color_s     : color_t;

begin

    -----------------------
    -- IO with top level --
    -----------------------
    rom_addr_68k_o <= addr_68k_s(ROM_LOG_SIZE_C-1 downto 0);
    rom_read_68k_o <= rom_enable_s and read_strobe_s;
    rom_ack_s      <= rom_valid_68k_i;
    -- The data bus is an OR'ed bus, so we need to ensure that the data from
    -- the ROM section does not interfere when the ROM is not enabled.
    rom_data_o_s <= rom_data_68k_i when rom_enable_s else
                    (others => '0');

    -- Sync
    process(clk_68k_i) is
    begin
        if rising_edge(clk_68k_i) then
            rst_68k_s <= rst_68k_i;
        end if;
    end process;

    -------------------
    -- Interruptions --
    -------------------
    interrupt_block : block
        signal sync_reg_s   : std_logic_vector(3 downto 0);
        signal vblank_irq_s : std_logic;
    begin

        -- Synchronisation shift register
        sync_process : process(clk_68k_i) is
        begin
            if rising_edge(clk_68k_i) then
                sync_reg_s(0) <= vblank_i;
                for i in 1 to sync_reg_s'high loop
                    sync_reg_s(i) <= sync_reg_s(i-1);
                end loop;
            end if;
        end process sync_process;

        -- Detect a rising edge on the VBLANK signal
        vblank_irq_s <= (not sync_reg_s(sync_reg_s'high)) and sync_reg_s(sync_reg_s'high-1);

        interrupt_process : process(clk_68k_i) is
        begin
            if rising_edge(clk_68k_i) then
                if rst_68k_i = '1' then
                    ipl_s <= (others => '0');
                else
                    -- This only simulates the V-Blank IRQ for now (TODO : Other IRQs and ACKs)
                    if vblank_irq_s = '1' then
                        ipl_s <= "001";
                    else
                        if (read_strobe_s = '1') and (addr_68k_s(23 downto 0) = x"800004") then
                            -- The 68k acknowledged the IRQ (I am not sure about this...)
                            ipl_s <= (others => '0');
                        end if; -- IRQ Ack
                    end if; -- IRQ fired
                end if; -- Reset
            end if; -- Rising Edge Clock
        end process interrupt_process;

        -- Test for interrupts
        process(clk_68k_i) is
        begin
            if rising_edge(clk_68k_i) then
                other_ack_s    <= '0';
                other_data_o_s <= (others => '0');
                if (read_strobe_s = '1') and (addr_68k_s(addr_68k_s'high downto addr_68k_s'high-3) = x"F") then
                    other_ack_s    <= '1';
                    --other_data_o_s <= x"0019"; -- The 68k uses auto-vectorized interrupts
                end if;
            end if;
        end process;

    end block interrupt_block;

    --------------------
    -- Main Processor --
    --------------------

    -- The main 68000 processor uses negative logic, since we use positive
    -- logic in our design we need to invert some signals.

    -- Switch from positive logic
    n_rst_68k_s      <= not rst_68k_s;
    n_data_ack_68k_s <= not memory_bus_ack_s;
    n_ipl_to_68k_s   <= not ipl_s;

    -- The main 68000 processor
    main_68k : entity work.TG68
        port map (
            clk            => clk_68k_i,
            reset          => n_rst_68k_s,
            clkena_in      => not pause_i,
            data_in        => memory_bus_data_s,
            IPL            => n_ipl_to_68k_s,
            dtack          => n_data_ack_68k_s,
            unsigned(addr) => addr_68k_32b_s,
            data_out       => data_out_68k_s,
            as             => n_addr_strobe_68k_s,
            uds            => n_upper_data_select_68k_s,
            lds            => n_lower_data_select_68k_s,
            rw             => read_n_write_68k_s,
            TG68_PC_o      => TG68_PC_o,
            TG68_PCW_o     => TG68_PCW_o);

    -- Mask the high byte since Dodonpachi only uses a 24 bit address bus,
    -- sometimes the CPU will have the upper 8 bits set due to an operation
    -- and this will lock the CPU because we are outside of the address space
    -- therefore no ack is generated, this mask makes sure the CPU only
    -- addresses 24 bits.
    --addr_68k_s <= x"00" & addr_68k_32b_s(23 downto 0); -- For some reason
    -- this deadlocks the CPU at instruction 0x57594, it could be that the TG68
    -- is written so that if the MSB byte is not used some signals get pruned
    -- and some address computation fail. (No idea for now).
    addr_68k_s <= addr_68k_32b_s;

    -- Switch to positive logic
    addr_strobe_68k_s       <= not n_addr_strobe_68k_s;
    upper_data_select_68k_s <= not n_upper_data_select_68k_s;
    lower_data_select_68k_s <= not n_lower_data_select_68k_s;

    -- TODO : Add support for byte access to RAM, check if unaligned accesses
    -- to a byte in RAM do use the uds/lds signals, and add the support for
    -- this in the RAM module, since there are accesses to bytes in RAM e.g.
    -- addq.b 1, <ram_address> in the program code. Check if these are done
    -- right.

    ---------------------
    -- Main Memory Bus --
    ---------------------

    -- TODO : Write an assertion to check that only one is active at any given
    -- time !

    -- This is an OR'ed bus
    memory_bus_ack_s <= rom_ack_s         or
                        ram_ack_s         or
                        ymz_ram_ack_s     or
                        sprite_ram_ack_s  or
                        layer_0_ram_ack_s or
                        layer_1_ram_ack_s or
                        layer_2_ram_ack_s or
                        video_regs_ack_s  or
                        irq_cause_ack_s   or
                        v_ctrl_0_ack_s    or
                        v_ctrl_1_ack_s    or
                        v_ctrl_2_ack_s    or
                        palette_ram_ack_s or
                        in_0_ack_s        or
                        in_1_ack_s        or
                        eeprom_ack_s      or
                        edge_case_ack_s   or
                        other_ack_s;

    -- TODO : Write an assertion to check that only one is active at any given
    -- time !

    -- "OR" everything together to create the "OR'ed" bus
    memory_bus_data_s <= rom_data_o_s         or
                         ram_data_o_s         or
                         ymz_ram_data_o_s     or
                         sprite_ram_data_o_s  or
                         layer_0_ram_data_o_s or
                         layer_1_ram_data_o_s or
                         layer_2_ram_data_o_s or
                         irq_cause_data_o_s   or
                         v_ctrl_0_data_o_s    or
                         v_ctrl_1_data_o_s    or
                         v_ctrl_2_data_o_s    or
                         palette_ram_data_o_s or
                         in_0_data_o_s        or
                         in_1_data_o_s        or
                         eeprom_data_o_s      or
                         other_data_o_s;

    -- This assertion is to check that therer is no byte access to any other
    -- memory than the RAM or ROM - TODO Change this, since byte read is OK on
    -- other devices
    --assert ((ram_enable_s = '0' and rom_enable_s = '0') and (not ((upper_data_select_68k_s = '1') xor (lower_data_select_68k_s = '1')))) or (ram_enable_s = '1' or rom_enable_s = '1') report "Byte access to a memory that is not RAM !" severity error;

    -- We register the address strobe in order to detect when it is asserted in
    -- order to make a single clock read/write strobe below
    addr_strobe_reg_process : process(clk_68k_i) is
    begin
        if rising_edge(clk_68k_i) then
            if rst_68k_s = '1' then
                addr_strobe_68k_old_reg_s       <= '0';
                upper_data_select_68k_old_reg_s <= '0';
                lower_data_select_68k_old_reg_s <= '0';
            else
                addr_strobe_68k_old_reg_s       <= addr_strobe_68k_s;
                upper_data_select_68k_old_reg_s <= upper_data_select_68k_s;
                lower_data_select_68k_old_reg_s <= lower_data_select_68k_s;
            end if;
        end if;
    end process addr_strobe_reg_process;

    -- These strobes indicate a read or write operation from the processor
    read_strobe_s       <= addr_strobe_68k_s and (not addr_strobe_68k_old_reg_s) and read_n_write_68k_s;
    write_strobe_s      <= addr_strobe_68k_s and (not addr_strobe_68k_old_reg_s) and (not read_n_write_68k_s);
    high_write_strobe_s <= upper_data_select_68k_s and (not upper_data_select_68k_old_reg_s) and (not read_n_write_68k_s);
    low_write_strobe_s  <= lower_data_select_68k_s and (not lower_data_select_68k_old_reg_s) and (not read_n_write_68k_s);

    -- Memory bus decode logic - Dodonpachi Address Map -- TODO Change to constants
    ---------------------------------------------------

    -- ROM                  0x000000 - 0x0fffff
    rom_enable_s         <= '1' when addr_68k_s(31 downto ROM_LOG_SIZE_C) = x"000" else
                            '0';
    -- RAM                  0x100000 - 0x10ffff
    ram_enable_s         <= '1' when addr_68k_s(31 downto RAM_LOG_SIZE_C) = x"0010" else
                            '0';
    -- YMZ RAM              0x300000 - 0x300003
    ymz_ram_enable_s     <= '1' when addr_68k_s(31 downto YMZ_RAM_LOG_SIZE_C) = x"0030000" & "00" else
                            '0';
    -- Sprite RAM           0x400000 - 0x40ffff
    sprite_ram_enable_s  <= '1' when addr_68k_s(31 downto SPRITE_RAM_LOG_SIZE_C) = x"0040" else
                            '0';
    -- Layer 0 RAM          0x500000 - 0x507fff
    layer_0_ram_enable_s <= '1' when addr_68k_s(31 downto LAYER_0_RAM_LOG_SIZE_C) = x"0050" & "0" else
                            '0';
    -- Layer 1 RAM          0x600000 - 0x607fff
    layer_1_ram_enable_s <= '1' when addr_68k_s(31 downto LAYER_1_RAM_LOG_SIZE_C) = x"0060" & "0" else
                            '0';
    -- Layer 2 RAM          0x700000 - 0x70ffff
    layer_2_ram_enable_s <= '1' when addr_68k_s(31 downto LAYER_2_RAM_LOG_SIZE_C) = x"0070" else
                            '0';
    -- Video Registers (should not necessarily be ram) (maybe remove read/write
    -- check redundancy).   0x800000 - 0x80007f
    video_regs_enable_s  <= '1' when (addr_68k_s(31 downto VIDEO_REGS_LOG_SIZE_C) = x"008000" & "0") and (read_n_write_68k_s = '0') else
                            '0';
    -- IRQ Cause (same about redundancy)
    --                      0x800000 - 0x800007
    irq_cause_enable_s   <= '1' when (addr_68k_s(31 downto 3) = x"0080000" & "0") and (read_n_write_68k_s = '1') else
                            '0';
    -- Video Control Registers 0
    --                      0x900000 - 0x900005
    v_ctrl_0_enable_s    <= '1' when addr_68k_s(31 downto V_CTRL_0_LOG_SIZE_C) = x"0090000" & "0" else
                            '0';
    -- Video Control Registers 1
    --                      0xa00000 - 0xa00005
    v_ctrl_1_enable_s    <= '1' when addr_68k_s(31 downto V_CTRL_1_LOG_SIZE_C) = x"00a0000" & "0" else
                            '0';
    -- Video Control Registers 2
    --                      0xb00000 - 0xb00005
    v_ctrl_2_enable_s    <= '1' when addr_68k_s(31 downto V_CTRL_2_LOG_SIZE_C) = x"00b0000" & "0" else
                            '0';
    -- Palette RAM          0xc00000 - 0xc0ffff
    palette_ram_enable_s <= '1' when addr_68k_s(31 downto PALETTE_RAM_LOG_SIZE_C) = x"00c0" else
                            '0';
    -- Inputs 0             0xd00000 - 0xd00001
    in_0_enable_s        <= '1' when addr_68k_s(31 downto IN_0_LOG_SIZE_C) = x"00d0000" & "000" else
                            '0';
    -- Inputs 1             0xd00000 - 0xd00003
    in_1_enable_s        <= '1' when addr_68k_s(31 downto IN_1_LOG_SIZE_C) = x"00d0000" & "001" else
                            '0';
    -- EEPROM               0xe00000 - 0xe00001
    eeprom_enable_s      <= '1' when addr_68k_s(31 downto EEPROM_LOG_SIZE_C) = x"00e0000" & "000" else
                            '0';
    -- Edge Cases
    edge_case_enable_s   <= '1' when (addr_68k_s(23 downto 16) = x"5f") or
                                     (addr_68k_s(31 downto 24) /= x"00") else
                            '0';
    -- Access to 0x5fxxxx appears in dodonpachi on attract loop when showing
    -- the air stage on frame 9355 i.e., after roughly 2 min 30 sec
    -- The game is accessing data relative to a Layer 1 address and underflows,
    -- these accesses do nothing but should be acknowledged in order not to
    -- block de CPU.
    -- The reason these accesses appear is probably because it made the layer
    -- update routine simpler to write (no need to handle edge cases) and
    -- these accesses are simply ignored by the hardware.
    -- The second case when the upper 8 bits are non zero should maybe never
    -- occur, this may be a problem with the softcore... This needs to be
    -- researched further...

    --------------
    -- Main ROM --
    --------------
    -- Main ROM is external

    --------------
    -- Main RAM --
    --------------
    main_ram_1 : entity work.main_ram
        port map (
            clk_i               => clk_68k_i,
            enable_i            => ram_enable_s,
            write_low_i         => high_write_strobe_s,
            write_high_i        => low_write_strobe_s,
            read_low_i          => read_strobe_s,
            read_high_i         => read_strobe_s,
            addr_i              => addr_68k_s(RAM_LOG_SIZE_C-1 downto 0),  -- There are unaligned byte accesses
            data_i              => data_out_68k_s,
            data_o              => ram_data_o_s,
            ack_o               => ram_ack_s);

    -------------
    -- YMZ280b --
    -------------
    ymz280b_block : block
    begin
        ymz280b_regs : entity work.true_dual_port_ram
            generic map (
                ADDR_WIDTH_A => YMZ_RAM_LOG_SIZE_C-1,
                DATA_WIDTH_A => DDP_WORD_WIDTH,
                ADDR_WIDTH_B => YMZ_RAM_LOG_SIZE_C-1,
                DATA_WIDTH_B => DDP_WORD_WIDTH)
            port map (
                clk_a  => clk_68k_i,
                cs_a   => ymz_ram_enable_s,
                wr_a   => write_strobe_s,
                rd_a   => read_strobe_s,
                addr_a => addr_68k_s(YMZ_RAM_LOG_SIZE_C-1 downto 1),
                din_a  => data_out_68k_s,
                dout_a => ymz_ram_data_o_s,
                ack_a  => ymz_ram_ack_s,
                clk_b  => clk_fast_i,
                addr_b => to_unsigned(0, YMZ_RAM_LOG_SIZE_C-1),
                dout_b => open);
    end block ymz280b_block;

    graphic_processor_block : block
        signal generate_frame_s         : std_logic;
        signal buffer_select_s          : std_logic;
        -- Sprite signals
        signal gfx_sprite_ram_addr_s    : sprite_ram_info_access_t;
        signal gfx_sprite_ram_info_s    : sprite_ram_line_t;
        -- Layer signals
        signal gfx_layer_0_ram_addr_s   : layer_ram_info_access_t;
        signal gfx_layer_1_ram_addr_s   : layer_ram_info_access_t;
        signal gfx_layer_2_ram_addr_s   : layer_ram_info_access_t;
        signal gfx_layer_0_ram_info_s   : layer_ram_line_t;
        signal gfx_layer_1_ram_info_s   : layer_ram_line_t;
        signal gfx_layer_2_ram_info_s   : layer_ram_line_t;
        signal gfx_vctrl_0_reg_s        : layer_info_line_t;
        signal gfx_vctrl_1_reg_s        : layer_info_line_t;
        signal gfx_vctrl_2_reg_s        : layer_info_line_t;
        -- Palette signals
        signal gfx_palette_ram_addr_s   : palette_ram_addr_t;
        signal gfx_palette_ram_data_s   : palette_ram_data_t;
    begin

        graphic_processor_generate : if INCLUDE_GRAPHIC_PROCESSOR_G generate

            -----------------------
            -- Graphic Processor --
            -----------------------
            graphic_processor_inst : entity work.graphic_processor
                generic map (
                    INCLUDE_LAYER_PROCESOR_G => true)
                port map (
                    rst_i                    => rst_i,
                    clk_i                    => clk_fast_i,
                    --
                    generate_frame_i         => generate_frame_s,
                    buffer_select_i          => buffer_select_s,
                    --
                    sprite_ram_addr_o        => gfx_sprite_ram_addr_s,
                    sprite_ram_info_i        => gfx_sprite_ram_info_s,
                    --
                    layer_0_ram_addr_o       => gfx_layer_0_ram_addr_s,
                    layer_0_ram_info_i       => gfx_layer_0_ram_info_s,
                    --
                    layer_1_ram_addr_o       => gfx_layer_1_ram_addr_s,
                    layer_1_ram_info_i       => gfx_layer_1_ram_info_s,
                    --
                    layer_2_ram_addr_o       => gfx_layer_2_ram_addr_s,
                    layer_2_ram_info_i       => gfx_layer_2_ram_info_s,
                    --
                    vctrl_reg_0_i            => gfx_vctrl_0_reg_s,
                    vctrl_reg_1_i            => gfx_vctrl_1_reg_s,
                    vctrl_reg_2_i            => gfx_vctrl_2_reg_s,
                    --
                    rom_addr_o               => rom_addr_gfx_o,
                    tiny_burst_gfx_o         => tiny_burst_gfx_o,
                    rom_burst_read_o         => rom_burst_read_gfx_o,
                    rom_data_i               => rom_data_gfx_i,
                    rom_data_valid_i         => rom_data_valid_gfx_i,
                    rom_data_burst_done_i    => rom_burst_done_gfx_i,
                    --
                    palette_ram_addr_o       => gfx_palette_ram_addr_s,
                    palette_ram_data_i       => gfx_palette_ram_data_s,
                    --
                    frame_buffer_addr_o      => frame_buffer_addr_o,
                    frame_buffer_color_o     => frame_buffer_color_s,
                    frame_buffer_write_o     => frame_buffer_write_o,
                    frame_buffer_dma_start_o => frame_buffer_dma_start_o,
                    frame_buffer_dma_done_i  => frame_buffer_dma_done_i);

            frame_buffer_data_o <= frame_buffer_color_s.r & frame_buffer_color_s.g & frame_buffer_color_s.b;

        else generate

            gfx_sprite_ram_addr_s    <= (others => '0');
            gfx_layer_0_ram_addr_s   <= (others => '0');
            gfx_layer_1_ram_addr_s   <= (others => '0');
            gfx_layer_2_ram_addr_s   <= (others => '0');
            rom_addr_gfx_o           <= (others => '0');
            rom_burst_read_gfx_o     <= '0';
            gfx_palette_ram_addr_s   <= (others => '0');
            frame_buffer_addr_o      <= (others => '0');
            frame_buffer_data_o      <= (others => '0');
            frame_buffer_write_o     <= '0';
            frame_buffer_dma_start_o <= '0';
            tiny_burst_gfx_o         <= '0';

        end generate graphic_processor_generate;

        ----------------
        -- Sprite RAM --
        ----------------
        sprite_ram : entity work.dual_access_ram
            port map (
                clk_68k_i    => clk_68k_i,
                enable_i     => sprite_ram_enable_s,
                write_low_i  => low_write_strobe_s,
                write_high_i => high_write_strobe_s,
                read_low_i   => read_strobe_s,
                read_high_i  => read_strobe_s,
                addr_i       => addr_68k_s(SPRITE_RAM_LOG_SIZE_C-1 downto 0),
                data_i       => data_out_68k_s,
                data_o       => sprite_ram_data_o_s,
                ack_o        => sprite_ram_ack_s,
                clk_fast_i   => clk_fast_i,
                addr_fast_i  => gfx_sprite_ram_addr_s,
                data_fast_o  => gfx_sprite_ram_info_s);

        -----------------
        -- Layer 0 RAM --
        -----------------
        layer_0_ram : entity work.true_dual_port_ram
            generic map (
                ADDR_WIDTH_A => LAYER_0_RAM_LOG_SIZE_C-1,
                DATA_WIDTH_A => DDP_WORD_WIDTH,
                ADDR_WIDTH_B => DDP_LAYER_TILE_RAM_LINE_ADDR_WIDTH-1,
                DATA_WIDTH_B => DDP_LAYER_TILE_RAM_LINE_WIDTH)
            port map (
                clk_a  => clk_68k_i,
                cs_a   => layer_0_ram_enable_s,
                wr_a   => write_strobe_s,
                rd_a   => read_strobe_s,
                addr_a => addr_68k_s(LAYER_0_RAM_LOG_SIZE_C-1 downto 1),
                din_a  => data_out_68k_s,
                dout_a => layer_0_ram_data_o_s,
                ack_a  => layer_0_ram_ack_s,
                clk_b  => clk_fast_i,
                -- Do not use the MSB bit because this RAM is 32kB and address is for 64kB
                addr_b => gfx_layer_0_ram_addr_s(gfx_layer_0_ram_addr_s'high-1 downto 0),
                dout_b => gfx_layer_0_ram_info_s);

        -----------------
        -- Layer 1 RAM --
        -----------------
        layer_1_ram : entity work.true_dual_port_ram
            generic map (
                ADDR_WIDTH_A => LAYER_1_RAM_LOG_SIZE_C-1,
                DATA_WIDTH_A => DDP_WORD_WIDTH,
                ADDR_WIDTH_B => DDP_LAYER_TILE_RAM_LINE_ADDR_WIDTH-1,
                DATA_WIDTH_B => DDP_LAYER_TILE_RAM_LINE_WIDTH)
            port map (
                clk_a  => clk_68k_i,
                cs_a   => layer_1_ram_enable_s,
                wr_a   => write_strobe_s,
                rd_a   => read_strobe_s,
                addr_a => addr_68k_s(LAYER_1_RAM_LOG_SIZE_C-1 downto 1),
                din_a  => data_out_68k_s,
                dout_a => layer_1_ram_data_o_s,
                ack_a  => layer_1_ram_ack_s,
                clk_b  => clk_fast_i,
                -- Do not use the MSB bit because this RAM is 32kB and address is for 64kB
                addr_b => gfx_layer_1_ram_addr_s(gfx_layer_1_ram_addr_s'high-1 downto 0),
                dout_b => gfx_layer_1_ram_info_s);

        -----------------
        -- Layer 2 RAM --
        -----------------
        -- The layer 2 RAM masks address bits 14 and 15 on the CPU-side (i.e.
        -- the RAM is 8KB mirrored to 64KB).
        --
        -- https://github.com/mamedev/mame/blob/master/src/mame/drivers/cave.cpp#L495
        layer_2_ram : entity work.true_dual_port_ram
            generic map (
                ADDR_WIDTH_A => LAYER_2_RAM_LOG_SIZE_C-3,
                DATA_WIDTH_A => DDP_WORD_WIDTH,
                ADDR_WIDTH_B => DDP_LAYER_TILE_RAM_LINE_ADDR_WIDTH-2,
                DATA_WIDTH_B => DDP_LAYER_TILE_RAM_LINE_WIDTH)
            port map (
                clk_a  => clk_68k_i,
                cs_a   => layer_2_ram_enable_s,
                wr_a   => write_strobe_s,
                rd_a   => read_strobe_s,
                addr_a => addr_68k_s(LAYER_2_RAM_LOG_SIZE_C-3 downto 1),
                din_a  => data_out_68k_s,
                dout_a => layer_2_ram_data_o_s,
                ack_a  => layer_2_ram_ack_s,
                clk_b  => clk_fast_i,
                addr_b => gfx_layer_2_ram_addr_s(gfx_layer_2_ram_addr_s'high-2 downto 0),
                dout_b => gfx_layer_2_ram_info_s);

        ---------------------
        -- Video Registers --
        ---------------------
        -- Could be changed to a more specific component since most of them are not
        -- needed
        video_regs_block : block
            signal video_reg_4_s : word_t;
        begin
            video_regs : entity work.true_dual_port_ram
                generic map (
                    ADDR_WIDTH_A => VIDEO_REGS_LOG_SIZE_C-1,
                    DATA_WIDTH_A => DDP_WORD_WIDTH,
                    ADDR_WIDTH_B => VIDEO_REGS_LOG_SIZE_C-1,
                    DATA_WIDTH_B => DDP_WORD_WIDTH)
                port map (
                    clk_a  => clk_68k_i,
                    cs_a   => video_regs_enable_s,
                    wr_a   => write_strobe_s,
                    rd_a   => '0', -- write-only
                    addr_a => addr_68k_s(VIDEO_REGS_LOG_SIZE_C-1 downto 1),
                    din_a  => data_out_68k_s,
                    dout_a => open, -- write-only
                    ack_a  => video_regs_ack_s,
                    clk_b  => clk_fast_i,
                    addr_b => to_unsigned(4, VIDEO_REGS_LOG_SIZE_C-1),
                    dout_b => video_reg_4_s);

            -- TODO: Check this
            buffer_select_s <= video_reg_4_s(0);

            sync_generate_frame_block : block
                signal sync_reg_s            : std_logic_vector(2 downto 0);
                signal start_frame_gen_reg_s : std_logic;
            begin
                -- Register at 68k side which indicates we need to start drawing a frame
                process (clk_68k_i) is
                begin
                    if rising_edge(clk_68k_i) then
                        if rst_68k_s = '1' then
                            start_frame_gen_reg_s <= '0';
                        else
                            -- If video reg at 0x800004 is written with 0x1F0 the graphic co-processor should start drawing a frame
                            if (write_strobe_s = '1') and (addr_68k_s(23 downto 0) = x"800004") and (data_out_68k_s = x"01f0") then
                                start_frame_gen_reg_s <= '1';
                            else
                                start_frame_gen_reg_s <= '0';
                            end if;
                        end if; -- Reset
                    end if; -- Rising Edge Clock
                end process;

                -- Shift register for sync (clock domain crossing) and edge
                -- detection (to start the frame generation)
                process (clk_fast_i) is
                begin
                    if rising_edge(clk_fast_i) then
                        if rst_i = '1' then
                            sync_reg_s <= (others => '0');
                        else
                            -- Input
                            sync_reg_s(0) <= start_frame_gen_reg_s;
                            -- Shift
                            for i in 1 to sync_reg_s'high loop
                                sync_reg_s(i) <= sync_reg_s(i-1);
                            end loop;
                        end if; -- Reset
                    end if; -- Rising Edge Clock
                end process;

                -- Edge detection
                generate_frame_s <= (not sync_reg_s(sync_reg_s'high)) and sync_reg_s(sync_reg_s'high-1);
            end block sync_generate_frame_block;

        end block video_regs_block;

        ---------------
        -- IRQ Cause --
        ---------------
        -- TODO (Temporary)
        irq_cause_process : process(clk_68k_i) is
        begin
            if rising_edge(clk_68k_i) then
                irq_cause_ack_s       <= '0';
                irq_cause_data_o_s    <= (others => '0');
                if irq_cause_enable_s = '1' then
                    if read_strobe_s = '1' then
                        irq_cause_data_o_s <= x"0003";  -- Active low
                        irq_cause_ack_s    <= '1';
                    end if;
                end if;
            end if;  -- Rising Edge Clock
        end process irq_cause_process;

        -- TODO : Check the VCTRL REGS (signals etc.)
        -- TODO : Replace the VCTRL blocks altogether (so not to use BRAM)

        -------------
        -- Vctrl 0 --
        -------------
        vctrl_regs_0 : entity work.vctrl_regs
            port map (
                clk_68k_i    => clk_68k_i,
                enable_i     => v_ctrl_0_enable_s,
                write_low_i  => low_write_strobe_s,
                write_high_i => high_write_strobe_s,
                read_low_i   => read_strobe_s,
                read_high_i  => read_strobe_s,
                addr_i       => addr_68k_s(V_CTRL_0_LOG_SIZE_C-1 downto 1),
                data_i       => data_out_68k_s,
                data_o       => v_ctrl_0_data_o_s,
                ack_o        => v_ctrl_0_ack_s,
                clk_fast_i   => clk_fast_i,
                vctrl_o      => gfx_vctrl_0_reg_s);

        -------------
        -- Vctrl 1 --
        -------------
        vctrl_regs_1 : entity work.vctrl_regs
            port map (
                clk_68k_i    => clk_68k_i,
                enable_i     => v_ctrl_1_enable_s,
                write_low_i  => low_write_strobe_s,
                write_high_i => high_write_strobe_s,
                read_low_i   => read_strobe_s,
                read_high_i  => read_strobe_s,
                addr_i       => addr_68k_s(V_CTRL_1_LOG_SIZE_C-1 downto 1),
                data_i       => data_out_68k_s,
                data_o       => v_ctrl_1_data_o_s,
                ack_o        => v_ctrl_1_ack_s,
                clk_fast_i   => clk_fast_i,
                vctrl_o      => gfx_vctrl_1_reg_s);

        -------------
        -- Vctrl 2 --
        -------------
        vctrl_regs_2 : entity work.vctrl_regs
            port map (
                clk_68k_i    => clk_68k_i,
                enable_i     => v_ctrl_2_enable_s,
                write_low_i  => low_write_strobe_s,
                write_high_i => high_write_strobe_s,
                read_low_i   => read_strobe_s,
                read_high_i  => read_strobe_s,
                addr_i       => addr_68k_s(V_CTRL_2_LOG_SIZE_C-1 downto 1),
                data_i       => data_out_68k_s,
                data_o       => v_ctrl_2_data_o_s,
                ack_o        => v_ctrl_2_ack_s,
                clk_fast_i   => clk_fast_i,
                vctrl_o      => gfx_vctrl_2_reg_s);

        -----------------
        -- Palette RAM --
        -----------------
        palette_ram : entity work.true_dual_port_ram
        generic map (
            ADDR_WIDTH_A => PALETTE_RAM_LOG_SIZE_C-1,
            DATA_WIDTH_A => DDP_WORD_WIDTH,
            ADDR_WIDTH_B => DDP_PALETTE_RAM_ADDR_WIDTH,
            DATA_WIDTH_B => DDP_WORD_WIDTH)
        port map (
            clk_a  => clk_68k_i,
            cs_a   => palette_ram_enable_s,
            wr_a   => write_strobe_s,
            rd_a   => read_strobe_s,
            addr_a => addr_68k_s(PALETTE_RAM_LOG_SIZE_C-1 downto 1),
            din_a  => data_out_68k_s,
            dout_a => palette_ram_data_o_s,
            ack_a  => palette_ram_ack_s,
            clk_b  => clk_fast_i,
            addr_b => gfx_palette_ram_addr_s,
            dout_b => gfx_palette_ram_data_s);

    end block graphic_processor_block;

    -----------------
    -- Input Ports --
    -----------------
    input_ports_block : block
        signal in_0_reg_s : word_t;
        signal in_1_reg_s : word_t;
    begin
        -- Enable for the OR'ed bus
        in_0_data_o_s <= in_0_reg_s when in_0_enable_s = '1' else (others => '0');
        in_1_data_o_s <= in_1_reg_s when in_1_enable_s = '1' else (others => '0');

        in_process : process(clk_68k_i) is
        begin
            if rising_edge(clk_68k_i) then
                in_0_ack_s <= '0';
                in_1_ack_s <= '0';
                in_0_reg_s <= "1111111" & (not player_1_i(8 downto 0));
                in_1_reg_s <= "1111" & eeprom_do_s & "11" & (not player_2_i(8 downto 0));
                if read_strobe_s = '1' then
                    if in_0_enable_s = '1' then
                        in_0_ack_s <= '1';
                    end if;
                    if in_1_enable_s = '1' then
                        in_1_ack_s <= '1';
                    end if;
                end if;
            end if;
        end process in_process;

    end block input_ports_block;

    ------------
    -- EEPROM --
    ------------
    eeprom_generate : if INCLUDE_EEPROM_G generate

        eeprom : entity work.eeprom_93c46
            port map (
                clk_i  => eeprom_ci_s,
                cs_i   => eeprom_cs_s,
                data_i => eeprom_di_s,
                data_o => eeprom_do_s);

    else generate

        eeprom_do_s <= '0';

    end generate eeprom_generate;

    eeprom_process : process(clk_68k_i) is
    begin
        if rising_edge(clk_68k_i) then
            eeprom_ack_s <= '0';
            if eeprom_enable_s = '1' then
                -- I believe it is possible that this is never ever read
                if read_strobe_s = '1' then
                    eeprom_data_o_s <= x"0000";
                    eeprom_ack_s    <= '1';
                elsif write_strobe_s = '1' then
                    eeprom_cs_s  <= data_out_68k_s(1);
                    eeprom_ci_s  <= data_out_68k_s(2);
                    eeprom_di_s  <= data_out_68k_s(3);
                    eeprom_ack_s <= '1';
                end if;
            else
                eeprom_data_o_s <= (others => '0');
            end if;  -- Enable
        end if;  -- Rising Edge Clock
    end process eeprom_process;

    ----------------
    -- Edge Cases --
    ----------------
    edge_case_process : process(clk_68k_i) is
    begin
        if rising_edge(clk_68k_i) then
            edge_case_ack_s <= '0';
            if edge_case_enable_s = '1' then
                if (read_strobe_s = '1') or (write_strobe_s = '1') then
                    edge_case_ack_s <= '1';
                end if;
            end if; -- Enable
        end if; -- Rising Edge Clock
    end process edge_case_process;

end struct;
