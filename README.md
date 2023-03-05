<h1 align="center">
  <img alt="Viisi" src="./assets/logo.png" width="360px">
</h1>
<p align="center">
  A RISC-V hobby computer inspired by old 80s and 90s UNIX workstations.
</p>

It's currently very bare bones right now, but it does have an almost full RV64IM(A) emulator. You can run one of the test files with `zig build run -- --kernel tests/<file>.bin`.

Currently only works with Zig version before 0.11.0-dev.1501+885d69689 (which is the latest version of Zig nightly that doesn't use the new build system), but a version of Viisi that uses the new build system.

## Progress
- [X] RV64GC emulator (WIP)
  - [X] RV32I - Base 32-bit instruction set
  - [X] RV64I - Base 64-bit instruction set
  - [X] M - Multiplication and division
  - [X] A - Atomic instructions (WIP)
  - [ ] F - Single-precision floating point
  - [ ] D - Double-precision floating point
  - [ ] C - Compressed instructions
  - [X] Zi - Additional extensions (WIP)
    - [X] Zicsr - Control and status register
    - [ ] Zifencei - Load/store fence
  - [ ] Pass all tests in [riscv-tests](https://github.com/riscv/riscv-tests)
- [X] UART
- [X] Basic disk drive controller
- [ ] RTC
- [ ] Framebuffer
- [ ] Networking

## Acknowledgements
- [rvemu-for-book](https://github.com/d0iasm/rvemu-for-book) for test files and RV64 emulator implementation.

## License
This project is open source and is licensed under the MIT license. See the [LICENSE](LICENSE) file for more informations.
