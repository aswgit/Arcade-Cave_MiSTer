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

package cave.gpu

import cave.Config
import chisel3._
import chiseltest._
import org.scalatest._

class SpriteDecoderTest extends FlatSpec with ChiselScalatestTester with Matchers {
  behavior of "4BPP"

  it should "request a word from the tile ROM for every row" in {
    test(new SpriteDecoder) { dut =>
      dut.io.format.poke(Config.GFX_FORMAT_4BPP.U)
      dut.clock.step()

      // Initial request
      dut.io.rom.valid.poke(true.B)
      dut.io.rom.ready.expect(true.B)
      dut.clock.step()
      dut.io.pixelData.valid.expect(true.B)
      dut.io.rom.ready.expect(false.B)
      dut.clock.step()

      // First request
      dut.io.pixelData.ready.poke(true.B)
      dut.clock.step()
      dut.io.pixelData.ready.poke(false.B)
      dut.io.rom.ready.expect(true.B)
      dut.clock.step()
      dut.io.pixelData.valid.expect(true.B)
      dut.io.rom.ready.expect(false.B)
      dut.clock.step()

      // Second request
      dut.io.pixelData.ready.poke(true.B)
      dut.clock.step()
      dut.io.pixelData.ready.poke(false.B)
      dut.io.rom.ready.expect(true.B)
      dut.clock.step()
      dut.io.pixelData.valid.expect(true.B)
      dut.io.rom.ready.expect(false.B)
    }
  }

  it should "decode a 4BPP tile" in {
    test(new SpriteDecoder) { dut =>
      dut.io.format.poke(Config.GFX_FORMAT_4BPP.U)
      dut.clock.step()
      dut.io.rom.valid.poke(true.B)
      dut.io.rom.bits.poke("hfedcba9876543210".U)
      dut.clock.step()
      dut.io.pixelData.valid.expect(true.B)
      dut.io.pixelData.bits(0).expect(0xe.U)
      dut.io.pixelData.bits(1).expect(0xf.U)
      dut.io.pixelData.bits(14).expect(0x0.U)
      dut.io.pixelData.bits(15).expect(0x1.U)
    }
  }

  it should "decode a 4BPP MSB tile" in {
    test(new SpriteDecoder) { dut =>
      dut.io.format.poke(Config.GFX_FORMAT_4BPP_MSB.U)
      dut.clock.step()
      dut.io.rom.valid.poke(true.B)
      dut.io.rom.bits.poke("hfedcba9876543210".U)
      dut.clock.step()
      dut.io.pixelData.valid.expect(true.B)
      dut.io.pixelData.bits(0).expect(0xd.U)
      dut.io.pixelData.bits(1).expect(0xc.U)
      dut.io.pixelData.bits(14).expect(0x3.U)
      dut.io.pixelData.bits(15).expect(0x2.U)
    }
  }

  behavior of "8BPP"

  it should "request two words from the tile ROM for every row" in {
    test(new SpriteDecoder) { dut =>
      dut.io.format.poke(Config.GFX_FORMAT_8BPP.U)
      dut.clock.step()

      // Initial request
      dut.io.rom.valid.poke(true.B)
      dut.io.rom.ready.expect(true.B)
      dut.clock.step()
      dut.io.pixelData.valid.expect(false.B)
      dut.io.rom.ready.expect(true.B)
      dut.clock.step()
      dut.io.pixelData.valid.expect(true.B)
      dut.io.rom.ready.expect(false.B)
      dut.clock.step()

      // First request
      dut.io.pixelData.ready.poke(true.B)
      dut.clock.step()
      dut.io.pixelData.ready.poke(false.B)
      dut.io.rom.ready.expect(true.B)
      dut.clock.step()
      dut.io.pixelData.valid.expect(false.B)
      dut.io.rom.ready.expect(true.B)
      dut.clock.step()
      dut.io.pixelData.valid.expect(true.B)
      dut.io.rom.ready.expect(false.B)
      dut.clock.step()

      // Second request
      dut.io.pixelData.ready.poke(true.B)
      dut.clock.step()
      dut.io.pixelData.ready.poke(false.B)
      dut.io.rom.ready.expect(true.B)
      dut.clock.step()
      dut.io.pixelData.valid.expect(false.B)
      dut.io.rom.ready.expect(true.B)
      dut.clock.step()
      dut.io.pixelData.valid.expect(true.B)
      dut.io.rom.ready.expect(false.B)
      dut.clock.step()
    }
  }

  it should "decode a 8BPP tile" in {
    test(new SpriteDecoder) { dut =>
      dut.io.format.poke(Config.GFX_FORMAT_8BPP.U)
      dut.clock.step()
      dut.io.rom.valid.poke(true.B)
      dut.io.rom.bits.poke("hfedcba9876543210".U)
      dut.clock.step(2)
      dut.io.pixelData.valid.expect(true.B)
      dut.io.pixelData.bits(0).expect(0xec.U)
      dut.io.pixelData.bits(1).expect(0xfd.U)
      dut.io.pixelData.bits(14).expect(0x20.U)
      dut.io.pixelData.bits(15).expect(0x31.U)
    }
  }
}
