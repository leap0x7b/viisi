# viisi
A RISC-V hobby computer inspired by old 80s and 90s UNIX workstations.

It's currently very bare bones right now, but it does have an almost full RV64IM(A) emulator. You can run one of the test files with `zig build run -- tests/<file>.bin`.

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
- [ ] Other actual stuff

## Credits
- [rvemu-for-book](https://github.com/d0iasm/rvemu-for-book) for test files and RV64 emulator implementation.

## License
This project is open source and is licensed under the MIT license. See the [LICENSE](LICENSE) file for more information.
