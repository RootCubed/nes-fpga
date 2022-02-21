const fs = require("fs");

let rom = fs.readFileSync(process.argv[2]);

// test for "NES[EOF]"
if (rom.readUInt8(0) != 0x4E || rom.readUInt8(1) != 0x45 || rom.readUInt8(2) != 0x53 || rom.readUInt8(3) != 0x1A) {
    console.log("Invalid ROM file! Aborting...");
    process.exit();
}
console.log("Valid ROM file! Reading header...");

// read PRGROM and CHRROM size in 16KB / 8KB units
let prgrom = rom.readUInt8(4) * 16;
let chrrom = rom.readUInt8(5) * 8;
let isBig = prgrom > 16;
console.log("PRG ROM is " + prgrom + "KB");
console.log("CHR ROM is " + chrrom + "KB");
console.log("Has PRG RAM: " + ((rom.readUInt8(6) & 0b00000010) != 0));
if (rom.readUInt8(6) & 0b00000010) {
    console.log("PRG RAM is " + rom.readUInt8(8) * 8 + "KB");
}
console.log("Has trainer: " + ((rom.readUInt8(6) & 0b00000100) != 0));
console.log("Mapper: " + (((rom.readUInt8(6) & 0b11110000) >> 4) | (rom.readUInt8(7) & 0b11110000)));

// write PRG ROM
let prgromBin = new Uint8Array(prgrom * 1024);
for (let i = 0; i < prgrom * 1024; i++) {
    prgromBin[i] = rom.readUInt8(i + 16);
}

// create CHR ROM
let chrromBin = new Uint8Array(chrrom * 1024);
for (let i = 0; i < chrrom * 1024; i++) {
    chrromBin[i] = rom.readUInt8(i + prgrom * 1024 + 16);
}

// configure nametable mirroring
let vertMirror = (rom[6] & 1);

if (prgrom == 16) {
    let dup = Array.from(prgromBin);
    fs.writeFileSync("prg_rom.mem", [...dup, ...dup].map(e => e.toString(16).padStart(2, '0')).join("\n"));
} else {
    fs.writeFileSync("prg_rom.mem", Array.from(prgromBin).map(e => e.toString(16).padStart(2, '0')).join("\n"));
}

if (chrrom == 0) {
    fs.writeFileSync("chr_rom.mem", Array.from(Buffer.alloc(8192)).map(e => e.toString(16).padStart(2, '0')).join("\n"));
} else {
    fs.writeFileSync("chr_rom.mem", Array.from(chrromBin).map(e => e.toString(16).padStart(2, '0')).join("\n"));
}

fs.copyFileSync("prg_rom.mem", "user/data/prg_rom.mem");
fs.copyFileSync("chr_rom.mem", "user/data/chr_rom.mem");