#include "screen_renderer.hpp"

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>

#include <verilated.h>
#include "Vnes.h"
#include "Vnes_nes.h"
#include "Vnes_cpu6502.h"
#include "Vnes_ppu.h"

class iNESFile {
private:
    struct hdr {
        char magic[4];
        uint8_t prgROMSize;
        uint8_t chrROMSize;
        uint8_t flags6;
        uint8_t flags7;
        uint8_t pad[8];
    };
public:
    char *prgROM;
    char *chrROM;
    uint32_t prgROMSize;
    uint32_t chrROMSize;
    bool verticalMirroring;

    iNESFile(const char *filepath) {
        std::ifstream file(filepath);
        hdr header;
        if (file.fail()) {
            printf("ERROR: Could not open the file \"%s\"\n", filepath);
            exit(0);
        }
        file.read((char *) &header, 16);
        verticalMirroring = header.flags6 & 1;

        prgROMSize = 16384 * header.prgROMSize;
        chrROMSize = 8192 * header.chrROMSize;

        prgROM = (char *) malloc(prgROMSize);
        chrROM = (char *) malloc(chrROMSize);

        file.read(prgROM, prgROMSize);
        file.read(chrROM, chrROMSize);
    }
};


unsigned char nesColors[64][3] = {
    { 84, 84, 84},{  0, 30,116},{  8, 16,144},{ 48,  0,136},{ 68,  0,100},{ 92,  0, 48},{ 84,  4,  0},{ 60, 24,  0},
    { 32, 42,  0},{  8, 58,  0},{  0, 64,  0},{  0, 60,  0},{  0, 50, 60},{  0,  0,  0},{  0,  0,  0},{  0,  0,  0},
    {152,150,152},{  8, 76,196},{ 48, 50,236},{ 92, 30,228},{136, 20,176},{160, 20,100},{152, 34, 32},{120, 60,  0},
    { 84, 90,  0},{ 40,114,  0},{  8,124,  0},{  0,118, 40},{  0,102,120},{  0,  0,  0},{  0,  0,  0},{  0,  0,  0},
    {236,238,236},{ 76,154,236},{120,124,236},{176, 98,236},{228, 84,236},{236, 88,180},{236,106,100},{212,136, 32},
    {160,170,  0},{116,196,  0},{ 76,208, 32},{ 56,204,108},{ 56,180,204},{ 60, 60, 60},{  0,  0,  0},{  0,  0,  0},
    {236,238,236},{168,204,236},{188,188,236},{212,178,236},{236,174,236},{236,174,212},{236,180,176},{228,196,144},
    {204,210,120},{180,222,120},{168,226,144},{152,226,180},{160,214,228},{160,162,160},{  0,  0,  0},{  0,  0,  0}
};

int main(int argc, char **argv) {
    iNESFile nesFile("../simvectors/smb.nes");
    
    std::ifstream expFile("../simvectors/exp_smb.txt");
    bool expFileFinished = true;
    
    char cpu_ram[0x800];
    char test_output[0x1000];
    char vram[0x2000];
    char chr_ram[0x2000];
    
    GLubyte pixels[240][256][3];
    for (int i = 0; i < 240; i++) {
        for (int j = 0; j < 256; j++) {
            pixels[i][j][0] = pixels[i][j][1] = pixels[i][j][2] = 0;
        }
    }
    
    ScreenRenderer sr = ScreenRenderer();
    sr.updateScreen(pixels);

    VerilatedContext *contextp = new VerilatedContext;
    Verilated::traceEverOn(true);

    Vnes* nes = new Vnes{ contextp };

    // Reset
    nes->rst_n = 1;
    nes->eval();
    nes->rst_n = 0;
    nes->clk = 0;
    nes->eval();
    nes->clk = 1;
    nes->eval();
    nes->clk = 0;
    contextp->timeInc(5);
    nes->eval();
    nes->rst_n = 1;
    contextp->timeInc(5);

    // Controller input
    int buttonIndex = 0;
    
    unsigned long long frames = 0;
    unsigned long long cycles = 0;
    unsigned long long cpuCycles = 0;
    bool wasDma = false;
    while (frames < 1000) {
        nes->clk = 1;
        nes->eval();
        contextp->timeInc(5);

        unsigned int x = nes->nes->i_ppu->get_x();
        unsigned int y = nes->nes->i_ppu->get_y();
        if (x < 256 && y < 240) {
            pixels[y][x][0] = nesColors[vram[0x1F00 | nes->color_o]][0];
            pixels[y][x][1] = nesColors[vram[0x1F00 | nes->color_o]][1];
            pixels[y][x][2] = nesColors[vram[0x1F00 | nes->color_o]][2];
        }
        if (x == 0 && y == 261) {
            frames++;
            printf("Frame %lld\n", frames);
            sr.updateScreen(pixels);
        }
        if (!expFileFinished && cycles % 3 == 0) {
            if (nes->nes->i_cpu6502->get_state() == 1 && !wasDma) {
                printf("%04x A:%02x X:%02x Y:%02x P:%02x SP:%02x PPU:%3d,%3d CYC:%lld\n",
                    nes->nes->i_cpu6502->get_pc(),
                    nes->nes->i_cpu6502->get_a(), nes->nes->i_cpu6502->get_x(), nes->nes->i_cpu6502->get_y(),
                    nes->nes->i_cpu6502->get_status(), nes->nes->i_cpu6502->get_sp(),
                    x, y, cpuCycles
                );

                // Check with golden log
                int pc, a, x, y, p, sp, ppuX, ppuY, cyc;
                std::string expLine;
                if (!getline(expFile, expLine)) {
                    printf("Testbench \e[0;32mPASSED\e[0m!\n");
                    expFileFinished = true;
                } else {
                    sscanf(expLine.c_str(), "%x", &pc);
                    sscanf(expLine.c_str() + 48,
                        "A:%x X:%x Y:%x P:%x SP:%x PPU:%d,%d CYC:%d",
                        &a, &x, &y, &p, &sp, &ppuX, &ppuY, &cyc
                    );
                    printf("%04x:%02x:%02x:%02x:%02x:%02x:%d:%d:%d\n", pc, a, x, y, p, sp, ppuX, ppuY, cyc);
                    int pc_act = nes->nes->i_cpu6502->get_pc();
                    int a_act = nes->nes->i_cpu6502->get_a();
                    int x_act = nes->nes->i_cpu6502->get_x();
                    int y_act = nes->nes->i_cpu6502->get_y();
                    int p_act = nes->nes->i_cpu6502->get_status() | 0b00100000;
                    int sp_act = nes->nes->i_cpu6502->get_sp();
                    if (pc != pc_act || a != a_act || x != x_act || y != y_act || p != p_act || sp != sp_act || cyc != cpuCycles) {
                        printf("Mismatch: expected %04x:%02x:%02x:%02x:%02x:%02x:%d, got %04x:%02x:%02x:%02x:%02x:%02x:%lld\n",
                            pc, a, x, y, p, sp, cyc,
                            pc_act, a_act, x_act, y_act, p_act, sp_act, cpuCycles
                        );
                        printf("Testbench \e[0;31mFAILED\e[0m with mismatch at PC = 0x%04x\n", nes->nes->i_cpu6502->get_pc());
                        break;
                    }
                }
            }
            cpuCycles++;
        }

        nes->clk = 0;
        nes->eval();
        contextp->timeInc(3);
        if (cycles % 3 == 0) {
            // CPU read/write
            if (!nes->cpu_rw_o) {
                /*if (nes->cpu_a_o >= 0xFFFA) {
                    printf("CPU read %04x -> %02x\n", nes->cpu_a_o, nesFile.prgROM[nes->cpu_a_o % nesFile.prgROMSize]);
                }*/
                //printf("CPU read %04x\n", nes->cpu_a_o);
                if (nes->cpu_a_o >= 0x8000) {
                    nes->cpu_d_i = nesFile.prgROM[nes->cpu_a_o % nesFile.prgROMSize];
                } else if (nes->cpu_a_o < 0x4000) {
                    nes->cpu_d_i = cpu_ram[nes->cpu_a_o & 0x7FF];
                } else if (nes->cpu_a_o == 0x4016) {
                    //nes->cpu_d_i = (frames == 6 && buttonIndex == 3) ? 0x41 : 0x40;
                    nes->cpu_d_i = 0x40;
                    buttonIndex++;
                } else {
                    nes->cpu_d_i = 0x00;
                }
            } else {
                //printf("CPU write %04x = %02x\n", nes->cpu_a_o, nes->cpu_d_o);
                if (nes->cpu_a_o == 0x4016) {
                    buttonIndex = 0;
                }
                if (nes->cpu_d_o >= 0x6000) {
                    printf("hi\n");
                    test_output[nes->cpu_d_o - 0x6000] = nes->cpu_d_o;
                    printf("%s\n", test_output + 4);
                }
                if (nes->cpu_a_o < 0x2000) {
                    cpu_ram[nes->cpu_a_o & 0x7FF] = nes->cpu_d_o;
                }
            }
        }
        // PPU read/write
        if (!nes->ppu_rw_o) {
            //printf("PPU read %04x\n", nes->ppu_a_o);
            if (nes->ppu_a_o < 0x2000) {
                if (nesFile.chrROMSize == 0) {
                    nes->ppu_d_i = chr_ram[nes->ppu_a_o];
                } else {
                    nes->ppu_d_i = nesFile.chrROM[nes->ppu_a_o % nesFile.chrROMSize];
                }
            } else {
                nes->ppu_d_i = vram[nes->ppu_a_o & 0x1FFF];
            }
        } else {
            //printf("PPU write %04x = %02x\n", nes->ppu_a_o, nes->ppu_d_o);
            if (nes->ppu_a_o >= 0x2000) {
                vram[nes->ppu_a_o & 0x1FFF] = nes->ppu_d_o;
            } else {
                if (nesFile.chrROMSize == 0) {
                    chr_ram[nes->ppu_a_o] = nes->ppu_d_o;
                }
            }
        }
        nes->eval();
        contextp->timeInc(2);

        cycles++;
    }
    printf("Testbench complete.\n");
    nes->final();
    delete nes;
    delete contextp;

    while (true) {
        XEvent xev;
        XNextEvent(sr.dpy, &xev);
        if (xev.type == Expose) {
            sr.updateScreen(pixels);
        } else if (xev.type == KeyPress) {
            break;
        }
    }
}
