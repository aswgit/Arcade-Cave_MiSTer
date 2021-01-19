/*
 *   __   __     __  __     __         __
 *  /\ "-.\ \   /\ \/\ \   /\ \       /\ \
 *  \ \ \-.  \  \ \ \_\ \  \ \ \____  \ \ \____
 *   \ \_\\"\_\  \ \_____\  \ \_____\  \ \_____\
 *    \/_/ \/_/   \/_____/   \/_____/   \/_____/
 *   ______     ______       __     ______     ______     ______
 *  /\  __ \   /\  == \     /\ \   /\  ___\   /\  ___\   /\__  _\
 *  \ \ \/\ \  \ \  __<    _\_\ \  \ \  __\   \ \ \____  \/_/\ \/
 *   \ \_____\  \ \_____\ /\_____\  \ \_____\  \ \_____\    \ \_\
 *    \/_____/   \/_____/ \/_____/   \/_____/   \/_____/     \/_/
 *
 * https://joshbassett.info
 * https://twitter.com/nullobject
 * https://github.com/nullobject
 *
 * Copyright (c) 2021 Josh Bassett
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package cave.types

import chisel3._
import chisel3.util._

/** Represents a game configuration. */
class GameConfig extends Bundle {
  /** The game index */
  val index = UInt(4.W)
  /** The program ROM offset */
  val progRomOffset = UInt(32.W)
  /** The tile ROM offset */
  val tileRomOffset = UInt(32.W)
  /** The sound ROM offset */
  val soundRomOffset = UInt(32.W)
  /** The number of colors per palette */
  val numColors = UInt(9.W)
  /** The number of tilemap layers */
  val numLayers = UInt(2.W)
  /** Asserted when zoomed sprites are enabled */
  val spriteZoom = Bool()
}

object GameConfig {
  /** DoDonPachi */
  val DODONPACHI = 0
  /** Dangun Feveron */
  val DANGUN_FEVERON = 1

  def apply() = new GameConfig

  /**
   * Returns a game configuration for the given game index.
   *
   * @param index The game index.
   */
  def apply(index: UInt): GameConfig = {
    MuxLookup(index, dodonpachiConfig, Seq(
      DANGUN_FEVERON.U -> dangunFeveronConfig
    ))
  }

  private def dodonpachiConfig = {
    val wire = Wire(new GameConfig)
    wire.index := DODONPACHI.U
    wire.progRomOffset := 0x00000000.U
    wire.tileRomOffset := 0x00100000.U
    wire.soundRomOffset := 0x00f00000.U
    wire.numColors := 256.U
    wire.numLayers := 3.U
    wire.spriteZoom := false.B
    wire
  }

  private def dangunFeveronConfig = {
    val wire = Wire(new GameConfig)
    wire.index := DANGUN_FEVERON.U
    wire.progRomOffset := 0x00000000.U
    wire.tileRomOffset := 0x00100000.U
    wire.soundRomOffset := 0x00d00000.U
    wire.numColors := 16.U
    wire.numLayers := 2.U
    wire.spriteZoom := true.B
    wire
  }
}
