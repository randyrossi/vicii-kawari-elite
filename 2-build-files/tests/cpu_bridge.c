/* Exercise the real assembled renderer with Kawari VICE's NMOS CPU core. */
#include <stdint.h>
#include <string.h>
uint8_t extraMem[65536];
int vicii_legacy_busy(void) { return 0; }
#include "vicii-coproc.c"

/* The current Kawari interpreter has an incorrect BIT implementation. The
 * stock 6510 reference uses BIT; model its documented flags here. The
 * renderer itself deliberately uses no BIT instructions on the co-processor. */
static int reference_step(void) {
    uint8_t op = extraMem[cp.pc];
    if (op == 0x24 || op == 0x2c) {
        cp.pc++;
        uint8_t m = cp_rd(op == 0x24 ? cp_zp() : cp_abs());
        cp.p = (cp.p & ~(F_N | F_V | F_Z)) | (m & (F_N | F_V))
             | ((cp.a & m) ? 0 : F_Z);
        return op == 0x24 ? 3 : 4;
    }
    return cp_exec();
}

static int run(int start, int end, int a, int x, int y, int flags,
               int limit, int reference) {
    memset(&cp, 0, sizeof cp);
    cp.pc = start;
    cp.a = a; cp.x = x; cp.y = y; cp.p = flags | 0x30;
    cp.sp = 0xfd;
    extraMem[0x1fe] = (end - 1) & 255;
    extraMem[0x1ff] = (end - 1) >> 8;
    int cycles = 0;
    while (cp.pc != end && cycles < limit)
        cycles += reference ? reference_step() : cp_exec();
    return cp.pc == end ? cycles : -1;
}

int run_to(int start, int end, int a, int x, int y, int flags, int limit) {
    return run(start, end, a, x, y, flags, limit, 0);
}

int reference_run_to(int start, int end, int a, int x, int y, int flags, int limit) {
    return run(start, end, a, x, y, flags, limit, 1);
}

int continue_to(int end, int limit) {
    int cycles = 0;
    while (cp.pc != end && cycles < limit) cycles += cp_exec();
    return cp.pc == end ? cycles : -1;
}
