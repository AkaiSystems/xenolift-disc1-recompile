//! xenolift — MIPS R3000A (PS1) static recompiler
//!
//! Phase 2: PS-X EXE loader + MIPS I decoder + function discovery + C emitter.
//! Target: Xenogears (SLUS_006.64), text segment at 0x80010000.
//!
//! PS-X EXE layout (verified against real dumps):
//!   0x00  "PS-X EXE"
//!   0x10  pc0    — initial program counter (entry point)
//!   0x18  t_addr — load address in RAM (KSEG0)
//!   0x1C  t_size — program byte count
//!   0x800        — program data always starts here (fixed, not a header field)

mod decoder;
mod discovery;
mod emitter;

use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::process::exit;

/// file offset where the program image begins in every PS-X EXE
const DATA_OFF: usize = 0x800;

/// R1150 (b8-c334) DISC STAGE — the overlay-pivot build step (Jos-confirmed
/// Sep 15 23:52: "commit to the overlay pivot"). The twin-project flow (step 3
/// we skipped): translate the disc overlay modules AOT from the DISC — the
/// single deterministic source of truth — instead of folding runtime
/// snapshots captured at particular emulator moments (the graveyard of
/// wrong-moment guards: R779 zero-coordinator, R783 poison predicate, R786
/// prologue fingerprint). This mode decodes the in-exe ftab (layout
/// receipt-proven: entries at 0x800100AC + 7*(n-2), LBA u24le + size u24le,
/// c333 sandbox decode matches runtime receipts exactly — file#14 LBA 108933
/// size 125304 = the R1005 field-module receipt), and with --disc extracts
/// every file from the disc image, LZSS-decompresses size-prefixed streams
/// (byte-exact port of lzss_ref.py, itself reverse-engineered from
/// fn_80032EB4 UnpackCompressedBuffer), and writes canonical payloads to
/// disc_stage/. The fold pipeline then has ONE authority: the disc.
/// Sector math is a byte-exact port of xenolift_disc_mount (runtime.c:9513):
/// sync 00FFFFFFFFFFFFFFFF00 -> 2352B sectors, user data at +0x18 (mode2) or
/// +0x10 (mode1); otherwise ISO 2048B, +0.
/// R1156 (b8-c340): consumed-input variant. c340 receipts resolve the
/// tool-vs-runtime contradiction: staged f14 @0x801D9724 and f15 @0x801F8724
/// are exactly 0x1F000 apart - the HLE's input contract (src + 0x20000) reads
/// PAST the ftab size into the NEXT staged file, and R1005's expansion of
/// file#14 completed there. The ftab size is a delivery unit, not the
/// compressed-stream bound. This variant reports how many input bytes the
/// decode consumed so the EXTENDED-STREAM class is receipted distinctly.
fn lzss_decode_used(src: &[u8]) -> Option<(Vec<u8>, usize)> {
    if src.len() < 4 { return None; }
    let size = u32::from_le_bytes([src[0], src[1], src[2], src[3]]) as usize;
    if size == 0 || size > 0x800000 { return None; }
    let mut dst = vec![0u8; size];
    let mut pos: usize = 0;
    let mut i: usize = 4;
    let n = src.len();
    while pos < size {
        if i >= n { return None; }
        let mut ctrl = src[i]; i += 1;
        for _t in 0..8 {
            if pos >= size { break; }
            if ctrl & 1 != 0 {
                if i + 1 >= n { return None; }
                let b1 = src[i] as u32; let b2 = src[i + 1] as u32; i += 2;
                let off = ((b2 & 0xF) << 8) | b1;
                let ln = (b2 >> 4) + 3;
                let sp = pos as isize - off as isize;
                if sp < 0 { return None; }
                for k in 0..ln {
                    if pos >= size { break; }
                    dst[pos] = dst[(sp + k as isize) as usize]; pos += 1;
                }
            } else {
                if i >= n { return None; }
                dst[pos] = src[i]; pos += 1; i += 1;
            }
            ctrl >>= 1;
        }
    }
    Some((dst, i))
}

fn lzss_decode(src: &[u8]) -> Option<Vec<u8>> {
    if src.len() < 4 { return None; }
    let size = u32::from_le_bytes([src[0], src[1], src[2], src[3]]) as usize;
    if size == 0 || size > 0x800000 { return None; }
    // faithful zero-buffer model (heap-calloc semantics): overlap reads past
    // the write position return zeros, never fail.
    let mut dst = vec![0u8; size];
    let mut pos = 0usize;
    let mut i = 4usize;
    let n = src.len();
    while pos < size {
        if i >= n { return None; } // truncated input
        let mut ctrl = src[i]; i += 1;
        for _t in 0..8 {
            if pos >= size { break; }
            if ctrl & 1 != 0 {
                if i + 1 >= n { return None; }
                let b1 = src[i]; let b2 = src[i + 1]; i += 2;
                let off = (((b2 as u32) & 0xF) << 8) as usize | b1 as usize;
                let ln = ((b2 >> 4) as usize) + 3;
                if off > pos { return None; } // reads before block = corrupt
                let sp = pos - off;
                for k in 0..ln {
                    if pos >= size { break; }
                    dst[pos] = dst[sp + k];
                    pos += 1;
                }
            } else {
                if i >= n { return None; }
                dst[pos] = src[i]; pos += 1; i += 1;
            }
            ctrl >>= 1;
        }
    }
    Some(dst)
}

/// R1154 (b8-c338): shared stream-start scan - the failing files (#7/#13/#14/
/// #18/...) fail decode at +0 while the runtime HLE expanded file#14 from the
/// staged buffer (R1005) - container headers before the stream are the
/// hypothesis; the scan names the true start empirically.
/// R1155 (b8-c339): TOLERANT LZSS probe. c339 receipts: #7/#13/#14/#18 have
/// NO plausible stream start at any offset 0-8192 (container-header hypothesis
/// dead). Next hypothesis: back-references BEFORE the block start (sp < 0) -
/// the strict decoder rejects them as corrupt, but the kernel unpacks into a
/// zero-initialized HeapCalloc block and a pre-start read on real HW sees
/// preceding heap/RAM, not a failure. Tolerant mode reads those as zeros:
/// if the failing class decodes cleanly under tolerance, the divergence is
/// receipted; if it still fails (input exhausted), the files are not this
/// LZSS variant at all and the raw-byte receipts discriminate the codec.
fn lzss_decode_tolerant(raw: &[u8]) -> Option<Vec<u8>> {
    if raw.len() < 4 { return None; }
    let size = u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]) as usize;
    if size == 0 || size > 0x800000 { return None; }
    let mut dst = vec![0u8; size];
    let mut pos: usize = 0;
    let mut i: usize = 4;
    let n = raw.len();
    while pos < size {
        if i >= n { return None; }
        let mut ctrl = raw[i]; i += 1;
        for _t in 0..8 {
            if pos >= size { break; }
            if ctrl & 1 != 0 {
                if i + 1 >= n { return None; }
                let b1 = raw[i] as u32; let b2 = raw[i + 1] as u32; i += 2;
                let off = ((b2 & 0xF) << 8) | b1;
                let ln = (b2 >> 4) + 3;
                let sp: isize = pos as isize - off as isize;
                for k in 0..ln {
                    if pos >= size { break; }
                    let src_idx = sp + k as isize;
                    let b = if src_idx < 0 { 0u8 } else { dst[src_idx as usize] };
                    dst[pos] = b; pos += 1;
                }
            } else {
                if i >= n { return None; }
                dst[pos] = raw[i]; pos += 1; i += 1;
            }
            ctrl >>= 1;
        }
    }
    Some(dst)
}

fn r1154_scan(raw: &[u8], n: u32) -> String {
    let e_size = raw.len();
let mut scan = String::from(" | LZSS@0 FAILED - SCAN:");
                        let mut found = false;
                        let mut attempts = 0u32;
                        let scan_lim = std::cmp::min(e_size, 8192);
                        let step_offsets: Vec<usize> = vec![4, 8, 16, 32, 64];
                        let mut cand: Vec<usize> = step_offsets.clone();
                        for o in 1..scan_lim { if !step_offsets.contains(&o) { cand.push(o); } if cand.len() >= 4096 { break; } }
                        for o in cand {
                            if o + 4 > e_size { break; }
                            let hdr2 = u32::from_le_bytes([raw[o], raw[o+1], raw[o+2], raw[o+3]]);
                            if hdr2 == 0 || hdr2 > 0x800000 { continue; }
                            attempts += 1;
                            if attempts > 2048 { break; }
                            match lzss_decode(&raw[o..e_size]) {
                                Some(dec) => {
                                    let words: Vec<String> = (0..8usize)
                                        .filter(|&w| w * 4 + 4 <= dec.len())
                                        .map(|w| format!("{:08X}", u32::from_le_bytes([dec[w*4], dec[w*4+1], dec[w*4+2], dec[w*4+3]])))
                                        .collect();
                                    scan += &format!(" STREAM FOUND at +{} (header={}, {}B) first words: {}", o, hdr2, dec.len(), words.join(" "));
                                    let out_dec = format!("disc_stage/file{:02}s.dec", n);
                                    fs::write(&out_dec, &dec).unwrap_or_else(|er| eprintln!("stage: #{} write {}: {}", n, out_dec, er));
                                    if dec.len() >= 16 {
                                        let w0 = u32::from_le_bytes([dec[0],dec[1],dec[2],dec[3]]);
                                        let w1 = u32::from_le_bytes([dec[4],dec[5],dec[6],dec[7]]);
                                        let w2 = u32::from_le_bytes([dec[8],dec[9],dec[10],dec[11]]);
                                        let w3 = u32::from_le_bytes([dec[12],dec[13],dec[14],dec[15]]);
                                        if w0 == 0x27BDFFC8 && w1 == 0x3C038001 && w2 == 0x8C630000 && w3 == 0x2402FFFF {
                                            scan += " | FLDMAIN-PROLOGUE-MATCH (R1122 FieldMain fingerprint)";
                                        }
                                    }
                                    found = true;
                                    break;
                                }
                                None => {}
                            }
                        }
                        
    if !found {
        scan += &format!(" NO STREAM FOUND in first {}B ({} hdr-plausible offsets tried)", std::cmp::min(e_size, 8192), attempts);
        /* R1155: tolerant probe at +0 (sp<0 reads as zeros) + raw bytes for codec discrimination */
        match lzss_decode_tolerant(raw) {
            Some(dec) => {
                let words: Vec<String> = (0..8usize)
                    .filter(|&w| w * 4 + 4 <= dec.len())
                    .map(|w| format!("{:08X}", u32::from_le_bytes([dec[w*4], dec[w*4+1], dec[w*4+2], dec[w*4+3]])))
                    .collect();
                scan += &format!(" | TOLERANT PROBE: decoded {}B (sp<0 = zeros) first words: {}", dec.len(), words.join(" "));
                if dec.len() >= 16 {
                    let w0 = u32::from_le_bytes([dec[0],dec[1],dec[2],dec[3]]);
                    let w1 = u32::from_le_bytes([dec[4],dec[5],dec[6],dec[7]]);
                    let w2 = u32::from_le_bytes([dec[8],dec[9],dec[10],dec[11]]);
                    let w3 = u32::from_le_bytes([dec[12],dec[13],dec[14],dec[15]]);
                    if w0 == 0x27BDFFC8 && w1 == 0x3C038001 && w2 == 0x8C630000 && w3 == 0x2402FFFF {
                        scan += " | FLDMAIN-PROLOGUE-MATCH (R1122 FieldMain fingerprint)";
                    }
                }
            }
            None => { scan += " | TOLERANT PROBE: still failed (input exhausted - not this LZSS variant at +0)"; }
        }
        let hex: Vec<String> = raw.iter().take(16).map(|b| format!("{:02X}", b)).collect();
        scan += &format!(" | raw[0..16]: {}", hex.join(" "));
    }
    scan
}

fn ftab_stage_main(args: &[String]) -> i32 {
    // xenolift --ftab <psx-exe> [--disc <disc-image>]
    let exe = match args.iter().position(|a| a == "--ftab").map(|p| p + 1) {
        Some(p) if p < args.len() => &args[p],
        _ => { eprintln!("usage: xenolift --ftab <psx-exe> [--disc <disc-image>]"); return 1; }
    };
    let disc_path = match args.iter().position(|a| a == "--disc") {
        Some(p) if p + 1 < args.len() => Some(args[p + 1].clone()),
        _ => std::env::var("XG_DISC").ok(),
    };
    let data = match fs::read(exe) {
        Ok(d) => d,
        Err(e) => { eprintln!("ftab: cannot read {}: {}", exe, e); return 1; }
    };
    if data.len() < DATA_OFF || &data[0..8] != b"PS-X EXE" {
        eprintln!("ftab: not a PS-X EXE image"); return 1;
    }
    let base = 0x80010000u32;
    let tab_off = DATA_OFF + (0x800100ACusize - base as usize);
    println!("ftab: entries at 0x800100AC + 7*(n-2), u24le LBA + u24le size");
    struct Ent { n: u32, lba: u32, size: u32 }
    let mut ents: Vec<Ent> = Vec::new();
    for n in 2u32..64u32 {
        let off = tab_off + 7 * (n as usize - 2);
        if off + 7 > data.len() { break; }
        let e = &data[off..off + 7];
        let lba = u32::from(e[0]) | (u32::from(e[1]) << 8) | (u32::from(e[2]) << 16);
        let size = u32::from(e[3]) | (u32::from(e[4]) << 8) | (u32::from(e[5]) << 16);
        if lba == 0 { continue; } // gap/terminator slots (8-11, 19-22 receipted)
        if e[6] != 0 || size > 0x200000 { // #12 raw 5da901faffffff = poisoned slot
            println!("ftab: #{} SKIP (LBA={} size={} b7={:02X} - poisoned/oversize slot)", n, lba, size, e[6]);
            continue;
        }
        println!("ftab: #{} LBA={} size={}", n, lba, size);
        ents.push(Ent { n, lba, size });
    }
    let disc = match &disc_path {
        Some(p) => match fs::read(p) {
            Ok(d) => Some(d),
            Err(e) => { eprintln!("ftab: --disc {}: {} (dumping table only)", p, e); None }
        },
        None => { println!("ftab: no --disc given (dumping table only; XG_DISC env also honored)"); None }
    };
    if let Some(d) = disc {
        // sector math: byte-exact port of xenolift_disc_mount (runtime.c:9513)
        static SYNC: [u8; 12] = [0x00,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x00];
        let (sec_bytes, sec_off): (usize, usize) =
            if d.len() >= 16 && d[0..12] == SYNC {
                (2352, if d[15] == 2 { 0x18 } else { 0x10 })
            } else { (2048, 0) };
        println!("disc: {} bytes, sector={} off={} ({} format)", d.len(), sec_bytes, sec_off,
                 if sec_bytes == 2352 { "raw" } else { "ISO" });
        let _ = fs::create_dir_all("disc_stage");
        for e in &ents {
            let nsec = (e.size as usize + 2047) / 2048;
            /* R1156: extended input contract - the HLE reads up to 0x20000
             * bytes from the stream start (xenolift_lzss_hle lim = src +
             * 0x20000), and c340 receipts prove file#14's stream continues
             * past its ftab size into the next staged file (f14/f15 staged
             * 0x1F000 apart = 62 sectors). Read 64 sectors from the LBA so
             * the decode sees exactly what the HLE sees; the ftab-size
             * slice stays authoritative for the .bin dump and scans. */
            let nsec_ext = std::cmp::max(nsec, 64);
            let mut raw = Vec::with_capacity(nsec_ext * 2048);
            let mut ok = true;
            for s in 0..nsec_ext {
                let fo = (e.lba as usize + s) * sec_bytes + sec_off;
                if fo + 2048 > d.len() { break; }
                raw.extend_from_slice(&d[fo..fo + 2048]);
            }
            if raw.len() < nsec * 2048 { println!("stage: #{} TRUNCATED at disc end", e.n); continue; }
            let out_raw = format!("disc_stage/file{:02}.bin", e.n);
            fs::write(&out_raw, &raw[..e.size as usize]).unwrap_or_else(|er| eprintln!("stage: #{} write {}: {}", e.n, out_raw, er));
            // LZSS detection: u32le expanded size, sane bound
            let hdr = u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]);
            let mut line = format!("stage: #{} raw {}B", e.n, e.size);
            if hdr > 0 && hdr <= 0x800000 {
                match lzss_decode_used(&raw[..std::cmp::min(raw.len(), 0x20000)]) {
                    Some((dec, used)) => {
                        if used > e.size as usize {
                            line += &format!(" | EXTENDED-STREAM: consumed {}B > ftab size {}B (R1005 class: stream continues past the delivery unit into the next file's sectors)", used, e.size);
                        }
                        let out_dec = format!("disc_stage/file{:02}.dec", e.n);
                        fs::write(&out_dec, &dec).unwrap_or_else(|er| eprintln!("stage: #{} write {}: {}", e.n, out_dec, er));
                        let words: Vec<String> = (0..8usize)
                            .filter(|&w| w * 4 + 4 <= dec.len())
                            .map(|w| format!("{:08X}", u32::from_le_bytes([dec[w*4], dec[w*4+1], dec[w*4+2], dec[w*4+3]])))
                            .collect();
                        let ratio: usize = if e.size > 0 { dec.len() / e.size as usize } else { 0 };
                        line += &format!(" | LZSS -> {}B ({}x) first words: {}", dec.len(), ratio, words.join(" "));
                        // R1122 receipt: FieldMain prologue = 27BDFFC8 3C038001 8C630000 2402FFFF
                        if dec.len() >= 16 {
                            let p = [dec[0],dec[1],dec[2],dec[3],dec[4],dec[5],dec[6],dec[7],
                                     dec[8],dec[9],dec[10],dec[11],dec[12],dec[13],dec[14],dec[15]];
                            let w0 = u32::from_le_bytes([p[0],p[1],p[2],p[3]]);
                            let w1 = u32::from_le_bytes([p[4],p[5],p[6],p[7]]);
                            let w2 = u32::from_le_bytes([p[8],p[9],p[10],p[11]]);
                            let w3 = u32::from_le_bytes([p[12],p[13],p[14],p[15]]);
                            if w0 == 0x27BDFFC8 && w1 == 0x3C038001 && w2 == 0x8C630000 && w3 == 0x2402FFFF {
                                line += " | FLDMAIN-PROLOGUE-MATCH (R1122 FieldMain fingerprint)";
                            }
                            /* R1156: door-anchored scan - find the FieldMain
                             * prologue ANYWHERE in the decode and name the
                             * offsets; +0x8398 = 0x80077E88 - 0x8006FAF0 = the
                             * coordinator door within a window-0-based
                             * expansion (c340: coordinator slot = prologue
                             * after R1005 expansion). */
                            if dec.len() >= 0x8398 + 16 {
                                let mut hits: Vec<usize> = Vec::new();
                                let mut o = 0usize;
                                while o + 16 <= dec.len() {
                                    if u32::from_le_bytes([dec[o],dec[o+1],dec[o+2],dec[o+3]]) == 0x27BDFFC8
                                        && u32::from_le_bytes([dec[o+4],dec[o+5],dec[o+6],dec[o+7]]) == 0x3C038001
                                        && u32::from_le_bytes([dec[o+8],dec[o+9],dec[o+10],dec[o+11]]) == 0x8C630000
                                        && u32::from_le_bytes([dec[o+12],dec[o+13],dec[o+14],dec[o+15]]) == 0x2402FFFF {
                                        hits.push(o);
                                        if hits.len() >= 4 { break; }
                                    }
                                    o += 4;
                                }
                                if !hits.is_empty() {
                                    let hs: Vec<String> = hits.iter().map(|h| format!("+{:#X}", h)).collect();
                                    line += &format!(" | FLDMAIN-PROLOGUE @ {} (door +0x8398 {})", hs.join(" "),
                                        if hits.contains(&0x8398) { "MATCH = coordinator door 0x80077E88 anchored by disc bytes" } else { "not at door" });
                                }
                            }
                        }
                    }
                    None => {
                        line += &r1154_scan(&raw[..e.size as usize], e.n);
                    }
                }
            } else {
                line += &" | not size-prefixed LZSS at +0 (header=0x{hdr:X})".replace("{hdr:X}", &format!("{:X}", hdr));
                /* R1154: scan this branch too - a container header before
                 * the stream yields an implausible first u32 (c338
                 * synthetic proof: 16B header + stream = "not size-prefixed"
                 * at +0, stream at +16). Same scan, same receipts. */
                line += &r1154_scan(&raw[..e.size as usize], e.n);
            }
            println!("{}", line);
        }
        println!("disc stage: {} files extracted to disc_stage/ (canonical disc-sourced payloads; the fold gates check against THESE bytes now)", ents.len());
    }
    0
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.iter().any(|a| a == "--ftab") {
        exit(ftab_stage_main(&args));
    }
    if args.len() < 2 {
        eprintln!("usage: xenolift <psx-exe> [out.c]");
        eprintln!("       xenolift --ftab <psx-exe> [--disc <disc-image>]");
        exit(1);
    }
    let path = &args[1];
    let out_path = args.get(2).cloned().unwrap_or_else(|| "out.c".into());

    let data = fs::read(path).unwrap_or_else(|e| {
        eprintln!("error: cannot read {}: {}", path, e);
        exit(1);
    });

    if data.len() < DATA_OFF || &data[0..8] != b"PS-X EXE" {
        eprintln!("error: not a PS-X EXE image");
        exit(1);
    }
    let pc0 = u32::from_le_bytes(data[0x10..0x14].try_into().unwrap());
    let t_addr = u32::from_le_bytes(data[0x18..0x1C].try_into().unwrap());
    let t_size = u32::from_le_bytes(data[0x1C..0x20].try_into().unwrap()) as usize;
    println!(
        "exe: entry=0x{:08X} load_addr=0x{:08X} size=0x{:X}",
        pc0, t_addr, t_size
    );

    if t_size == 0 {
        eprintln!("error: empty text segment");
        exit(1);
    }
    // clamp to what's actually in the file (protects against truncated dumps)
    let end = (DATA_OFF + t_size).min(data.len());
    let mut blob_vec: Vec<u8> = data[DATA_OFF..end].to_vec();
    // R120: OVERLAY MODULE SUPPORT (capture-compile). The kernel installs a
    // runtime-loaded code module at 0x80070000-0x8008FFFF (phase callbacks
    // 0x800737EC/0x80077E88/0x80070CFC/0x80088E90 + launch state 0x80077C5C
    // all point there). If overlay_region.bin — captured POST-INSTALL by the
    // runtime at boot-main entry #2 — exists and contains real code, map it
    // into the image: the 2e/2f scans then discover its functions and the
    // emitter emits them natively, so the kernel's jump into the overlay
    // lands in recompiled code instead of unresolved garbage.
    {
        /* R1260: the emitter input is overlay_input.bin ONLY (approved, verified,
         * never written by the runtime - captures go to unique files). */
        if let Ok(ovl) = fs::read("overlay_input.bin") {
            let nz = ovl.chunks(4).filter(|c| c.iter().any(|&b| b != 0)).count();
            /* R142: module load base is 0x8006FAF0 (recomp inventory);
             * window aligned down to 0x8006F000. */
            const OVL_BASE: u32 = 0x8006F000;
            const IMG_END: usize = 0x80000; /* 0x80090000 - 0x80010000 */
            /* R142: >=0x21000 (135168B) also REJECTS stale 131072B
             * captures from the old 0x80070000 window — those would
             * misalign by 0x10000 at the new base. Fresh capture only. */
            /* R783 POISON PREDICATE (c366): the c365 ASCII formatter sprayed
             * TEXT "0000" over the coordinator (0x80077E88 first words
             * 30303030x4) and that capture got folded as CODE — the whole
             * translation became ASCII and the guest hung (240s watchdog
             * kill, no digest). Real MIPS prologues are never all-printable
             * or 4 identical words: poisoned = every nonzero byte in
             * 0x20..=0x7E, or all 4 words equal. Applied to BOTH the base
             * overlay_region.bin fold AND the fault-capture fold. */
            /* text poison: mostly-nonzero coordinator bytes ALL printable
             * ASCII ("30303030x4" class). Zeros are LEGAL for the BASE
             * capture (module installs later - R681's whole premise), so
             * the base gate uses text-only; the FAULT capture must hold
             * REAL installed code: reject text, 4-identical-words, or
             * zeros (R779). */
            let coord_text = |bytes: &[u8], off: usize| -> bool {
                if bytes.len() < off + 16 { return true; }
                let nz = bytes[off..off+16].iter().filter(|&&b| b != 0).count();
                if nz < 12 { return false; }
                bytes[off..off+16].iter().all(|&b| b == 0 || (0x20..=0x7E).contains(&b))
            };
            let coord_same = |bytes: &[u8], off: usize| -> bool {
                if bytes.len() < off + 16 { return true; }
                let w: Vec<u32> = (0..4)
                    .map(|i| u32::from_le_bytes([bytes[off+4*i], bytes[off+4*i+1], bytes[off+4*i+2], bytes[off+4*i+3]]))
                    .collect();
                w[0] == w[1] && w[1] == w[2] && w[2] == w[3]
            };
            let ce_b = (0x80077E88u32 - OVL_BASE) as usize;
            let base_ok = ovl.len() >= 0x21000 && nz > 1000 && !coord_text(&ovl, ce_b);
            if ovl.len() >= 0x21000 && nz > 1000 && !base_ok {
                println!("overlay module: REJECTED ({}B, {} nonzero words but coordinator POISONED - R783; pristine exe kept)", ovl.len(), nz);
            } else if ovl.len() >= 0x21000 && nz > 1000 {
                if blob_vec.len() < IMG_END {
                    blob_vec.resize(IMG_END, 0);
                }
                let off = (OVL_BASE - 0x80010000) as usize;
                let n = ovl.len().min(IMG_END - off);
                blob_vec[off..off + n].copy_from_slice(&ovl[..n]);
                println!(
                    "overlay module: {} bytes mapped at 0x{:08X} ({} nonzero words)",
                    n, OVL_BASE, nz
                );
                /* R681: overlay_fault.bin (captured at the wild-jump fault,
                 * AFTER the field coordinator installs) supersedes the stale
                 * pre-menu capture - map it over the same window so the
                 * kernel's dispatch into 0x80077E88 lands in REAL recompiled
                 * code instead of compiled zeros. */
                if let Ok(fov) = fs::read("overlay_fault.bin") {
                    let fnz = fov.chunks(4).filter(|c| c.iter().any(|&b| b != 0)).count();
                    /* R779 ZERO-COORDINATOR GUARD (c362): the fault-capture
                     * fold gate (>=0x21000B, >1000 nonzero words) accepted a
                     * PRE-EXPANSION capture (6643 nonzero words but the
                     * coordinator entry at window offset 0x8E88 all zeros)
                     * — the emit compiled a BLANK window-0 coordinator and
                     * the R682 proof line warned while the damage shipped.
                     * A capture whose coordinator entry is zeroed was taken
                     * before the field module expanded into window-0:
                     * folding it DELETES real code. Reject and keep the
                     * pre-menu mapping instead. */
                    let ce_f = (0x80077E88u32 - OVL_BASE) as usize;
                    /* R786 PROLOGUE FINGERPRINT (c369): a 14217-nonzero
                     * capture passed every shape predicate (not zero, not
                     * all-printable, not 4-identical) yet its coordinator
                     * words EBE10222/543DAE66/3FFCCCE1/B142E144 were GARBAGE
                     * — the run's fault jump targets matched the folded
                     * words EXACTLY. The real coordinator prologue is stable
                     * module code: 8E020050 3C04800A (every healthy era +
                     * the runtime fldreloc expansion agree). Fold ONLY on
                     * exact prologue match; anything else = wrong-moment
                     * capture, keep pre-menu mapping. LESSON 86: demand the
                     * known-good fingerprint, never "not-obviously-bad". */
                    let coord_live = fov.len() >= ce_f + 8
                        && fov[ce_f] == 0x50 && fov[ce_f + 1] == 0x00
                        && fov[ce_f + 2] == 0x02 && fov[ce_f + 3] == 0x8E
                        && fov[ce_f + 4] == 0x0A && fov[ce_f + 5] == 0x80
                        && fov[ce_f + 6] == 0x04 && fov[ce_f + 7] == 0x3C;
                    if fov.len() >= 0x21000 && fnz > 1000 && !coord_live {
                        println!("overlay fault-capture REJECTED: {}B, {} nonzero words but coordinator PROLOGUE MISMATCH (not 8E020050 3C04800A; wrong-moment capture, keeping pre-menu mapping - R786)", fov.len(), fnz);
                    } else if fov.len() >= 0x21000 && fnz > 1000 {
                        let n2 = fov.len().min(IMG_END - off);
                        blob_vec[off..off + n2].copy_from_slice(&fov[..n2]);
                        println!("overlay fault-capture mapped OVER pre-menu snapshot: {} bytes, {} nonzero words (R681 real field coordinator)",
                                 n2, fnz);
                        /* R682: PROOF the coordinator entry made it into the
                         * compiled image - print the bytes at window offset
                         * 0x8E88 (= 0x80077E88 - 0x8006F000). Zeros here = the
                         * coordinator still isn't installed at capture time and
                         * the blank-page crash will recur; nonzero = real code
                         * compiled, dispatch lands natively next run. */
                        let ce = (0x80077E88u32 - OVL_BASE) as usize;
                        let words: Vec<String> = (0..4)
                            .map(|i| format!("{:08X}",
                                u32::from_le_bytes([blob_vec[off + ce + 4*i],
                                                    blob_vec[off + ce + 4*i + 1],
                                                    blob_vec[off + ce + 4*i + 2],
                                                    blob_vec[off + ce + 4*i + 3]])))
                            .collect();
                        println!("overlay coordinator entry 0x80077E88 first words: {} {} {} {} (R682 proof - zeros = blank-page crash recurs)",
                                 words[0], words[1], words[2], words[3]);
                    } else {
                        println!("overlay fault-capture ignored ({}B, {} nonzero words)", fov.len(), fnz);
                    }
                }
            } else {
                println!(
                    "overlay module: capture ignored ({}B, {} nonzero words — pre-install zeros?)",
                    ovl.len(),
                    nz
                );
            }
        }
    }
    /* R226: STAGE-2 WINDOW (capture-compile). The movie module (window 1)
     * reads an 88,604B second-stage payload into its 132,256B allocation at
     * 0x801D3000 and calls 0x801D3538 inside it mid-stream. stage2_region.bin
     * — captured at that halt by the runtime (R225), with the pending read
     * completed straight from the disc — maps the window so the call lands
     * in recompiled code. Size gate: >=0x21000 rejects stale/empty captures. */
    {
        if let Ok(s2) = fs::read("stage2_region.bin") {
            let nz = s2.chunks(4).filter(|c| c.iter().any(|&b| b != 0)).count();
            const STAGE2_BASE: u32 = 0x801D3000;
            const S2_END: usize = 0x1E4000; /* 0x801F4000 - 0x80010000 */
            if s2.len() >= 0x21000 && nz > 1000 {
                if blob_vec.len() < S2_END {
                    blob_vec.resize(S2_END, 0);
                }
                let off = (STAGE2_BASE - 0x80010000) as usize;
                let n = s2.len().min(S2_END - off);
                blob_vec[off..off + n].copy_from_slice(&s2[..n]);
                println!(
                    "overlay stage-2 module: {} bytes mapped at 0x{:08X} ({} nonzero words)",
                    n, STAGE2_BASE, nz
                );
            } else {
                println!(
                    "overlay stage-2 capture ignored ({}B, {} nonzero words)",
                    s2.len(), nz
                );
            }
        }
    }
    let blob = &blob_vec[..];

    let mut insts = Vec::with_capacity(blob.len() / 4);
    for chunk in blob.chunks_exact(4) {
        insts.push(decoder::decode(u32::from_le_bytes(chunk.try_into().unwrap())));
    }

    // phase 2b: the kernel is table-driven — many calls go through function
    // pointers stored in DATA. A pure code walk can't see those, so scan the
    // raw image for words that look like code addresses; each becomes an
    // extra function entry for discovery.
    let region_end = t_addr + (blob.len() as u32);
    let mut ptr_entries: BTreeSet<u32> = BTreeSet::new();
    for chunk in blob.chunks_exact(4) {
        let w = u32::from_le_bytes(chunk.try_into().unwrap());
        if w >= t_addr && w < region_end && (w & 3) == 0 {
            ptr_entries.insert(w);
        }
    }
    // phase 2e: runtime-registered callbacks. The kernel also MATERIALIZES
    // code addresses with lui+addiu/ori pairs (factory returns, registration
    // arguments — e.g. fn_8004BF20 returns fn_8004BFF0 in v0), and never
    // stores them in static data. Scan for those pairs and for function
    // prologues (addiu sp, sp, -N) so every plausible entry is dispatchable.
    let data_scan_count = ptr_entries.len();
    let mut lui_val: std::collections::BTreeMap<usize, (u32, usize)> = std::collections::BTreeMap::new();
    let mut mat_count = 0usize;
    let mut prologue_count = 0usize;
    for (i, chunk) in blob.chunks_exact(4).enumerate() {
        let w = u32::from_le_bytes(chunk.try_into().unwrap());
        let pc = t_addr + (i as u32) * 4;
        let op = w >> 26;
        let rs = ((w >> 21) & 31) as usize;
        let rt = ((w >> 16) & 31) as usize;
        let imm = w & 0xFFFF;
        if op == 0x0F {
            // lui rt, imm — remember (reg -> high half, instruction index)
            lui_val.insert(rt, (imm << 16, i));
        } else if op == 0x09 || op == 0x0D {
            if rt == 0 || rt == 29 {
                // keep the map clean of sp/zero churn
            } else if let Some((high, li)) = lui_val.get(&rs).cloned() {
                // only pair with a RECENT lui (within 8 instructions) so a
                // register's content is still the lui result
                if i - li <= 8 {
                    let v = if op == 0x09 {
                        high.wrapping_add(imm as i16 as i32 as u32)
                    } else {
                        high | imm
                    };
                    if v >= t_addr && v < region_end && (v & 3) == 0 {
                        mat_count += 1;
                        ptr_entries.insert(v);
                    }
                    // chains: lui 0x8006; addiu r,-x; addiu r,-y — track on
                    lui_val.insert(rt, (v, i));
                }
            }
            if op == 0x09 && rs == 29 && rt == 29 && (imm & 0x8000) != 0 {
                // addiu sp, sp, -N: classic function prologue
                prologue_count += 1;
                ptr_entries.insert(pc);
            }
        }
    }
    // phase 2f (R91): byte-granular pointer scan + relative-handler seeding.
    // The CD module's descriptor table uses 7-byte rows with fn ptrs at +3
    // (unaligned — the 4-aligned scan misses them), and the boot module
    // registers internal helpers as RUNTIME-COMPUTED base+offset pointers
    // (0x80019B78 = boot_main 0x80019578 + 0x600 — invisible to every
    // static scan). Sweep both: any text-range pointer at any byte offset
    // becomes a seed, and every 4-aligned address in the boot module's
    // helper range becomes dispatchable so trampoline calls never hit
    // "unresolved indirect jump".
    {
        let mut added = 0usize;
        for i in 0..blob.len().saturating_sub(3) {
            let w = u32::from_le_bytes([blob[i], blob[i + 1], blob[i + 2], blob[i + 3]]);
            if w >= t_addr && w < region_end && (w & 3) == 0 {
                if ptr_entries.insert(w) { added += 1; }
            }
        }
        for a in (0x80019578u32..0x80019C00u32).step_by(4) {
            if ptr_entries.insert(a) { added += 1; }
        }
        /* R120: the overlay module's known entry points (phase callbacks +
         * launch state) — always dispatchable when the module is mapped. */
        for a in [0x80077C5Cu32, 0x800737EC, 0x80077E88, 0x80070CFC, 0x80088E90, 0x801D3538u32] {
            if ptr_entries.insert(a) { added += 1; }
        }
        println!("2f scan: {} extra seeds", added);
    }
    println!(
        "data scan: {} static pointers | 2e: {} materialized code addresses, {} prologues",
        data_scan_count, mat_count, prologue_count
    );

    // walk the code from the entry point; mark what is actually reachable
    let (visited, functions, jr_targets) = discovery::discover(t_addr, &insts, pc0, &ptr_entries);
    println!(
        "decoded {} words total; {} are reachable code ({} functions); the rest is data",
        insts.len(),
        visited.len(),
        functions.len()
    );

    // stats over the REACHABLE code only — honest decoder coverage
    let mut cf = 0usize;
    let mut cop = 0usize;
    let mut unknown = 0usize;
    for (i, ins) in insts.iter().enumerate() {
        let pc = t_addr + (i as u32) * 4;
        if !visited.contains(&pc) {
            continue;
        }
        if matches!(ins, decoder::Inst::Unknown { .. }) {
            unknown += 1;
        } else if matches!(ins, decoder::Inst::CopUnknown { .. }) {
            cop += 1;
        }
        if decoder::is_control_flow(ins) {
            cf += 1;
        }
    }
    println!(
        "reachable code: control-flow {} | COP (GTE/etc.) {} | unknown {}",
        cf, cop, unknown
    );

    // R93: symbol map from the community annotations CSV — names all
    // 1,219 functions of this exact binary (OpokXeno/xenogears-recomp).
    let mut syms: std::collections::BTreeMap<u32, String> = std::collections::BTreeMap::new();
    if let Ok(txt) = std::fs::read_to_string("annotations.csv") {
        for line in txt.lines() {
            let mut it = line.splitn(2, ',');
            let a = it.next().unwrap_or("").trim().trim_start_matches("0x");
            let n = it.next().unwrap_or("").trim().to_string();
            if let Ok(addr) = u32::from_str_radix(a, 16) {
                if !n.is_empty() && addr >= t_addr && addr < region_end {
                    syms.insert(addr, n);
                }
            }
        }
    }
    // R919 (b8-c23, manager - PHASE 1 REFERENCE INGEST, Jos directive
    // 22:05/22:15 "tool should not only read code but help in the
    // recompilation"): merge the matching decompilation's symbol map
    // (ladysilverberg/xenogears-decomp, SLUS-006.64) so emitted functions
    // carry the community's real names at emit time. Format per line:
    // "Name = 0xADDR;" (splat symbol_addrs; trailing comments after the
    // semicolon are ignored). Decomp names are AUTHORITATIVE (matching
    // decomp of this exact binary) - they override CSV annotations on
    // conflict. Data symbols outside the code window are skipped.
    let mut decomp_n = 0usize;
    if let Ok(txt) = std::fs::read_to_string("symbol_addrs.txt") {
        for line in txt.lines() {
            let lhs = line.split(';').next().unwrap_or("");
            let mut it = lhs.splitn(2, '=');
            let n = it.next().unwrap_or("").trim().to_string();
            let a2 = it.next().unwrap_or("").trim().trim_start_matches("0x");
            if let Ok(addr) = u32::from_str_radix(a2, 16) {
                if !n.is_empty() && addr >= t_addr && addr < region_end {
                    syms.insert(addr, n);
                    decomp_n += 1;
                }
            }
        }
    }
    println!("reference ingest: +{} decomp symbols merged (xenogears-decomp SLUS-006.64; decomp names authoritative)", decomp_n);
    // R921 (b8-c26, manager - SYMBOL MAP FILE, Jos directive 22:24
    // "remember what you're learning, implement it in xenolift"): emit
    // disc1.map - every named function with its address. The crash kit
    // (R853/R858) resolves smashed host frames by LOOKUP instead of atos
    // offset archaeology; future digests can annotate cur_fn with real
    // names. Unnamed fns keep the fn_XXXXXXXX convention.
    {
        let mut map = String::new();
        for (&fa, fname) in syms.iter() {
            map.push_str(&format!("{:08X} {}\n", fa, fname));
        }
        let _ = fs::write("disc1.map", map);
        println!("symbol map file: disc1.map ({} named entries)", syms.len());
    }
    println!("symbol map: {} named functions", syms.len());
    emitter::set_symbols(syms);

    let c = emitter::emit(t_addr, &insts, &visited, &functions, &jr_targets, pc0);
    fs::write(&out_path, &c).unwrap_or_else(|e| {
        eprintln!("error: write {}: {}", out_path, e);
        exit(1);
    });
    println!("wrote {}", out_path);

    // R919 PHASE 2 COVERAGE MANIFEST (Jos directive 22:15 - the burn-down
    // chart): every emit reports what fraction of the executable image is
    // NATIVELY TRANSLATED (visited instruction addresses) vs mapped-as-
    // data (overlays folded into the image get discovered + emitted as
    // native fns only on a FRESH emit - EMIT_REFRESH). The manifest makes
    // translation gaps visible per build and doubles as a regression
    // test: a decoder tweak that drops coverage fails loudly here.
    {
        /* R920 (b8-c25, manager - COVERAGE DENOMINATOR FIX): c25's first
         * manifest printed 356.2% because visited counts ALL translated
         * addresses, and the fresh emit translates regions OUTSIDE the
         * 512KB exe image (overlay modules folded at 0x8006F000 are inside,
         * but stage-2 at 0x801D3000 and discovery extras are not). Split:
         * in-image % vs overlay/extra bytes - the burn-down number must be
         * the in-image one; overlay extras are progress, not noise. */
        let total_bytes = visited.len() as u64 * 4;
        let in_img = visited.iter().filter(|&&a| a >= t_addr && a < t_addr + 0x80000u32).count() as u64 * 4;
        let img_bytes: u64 = 0x80000; /* 0x80010000..0x80090000 */
        let pct = (in_img as f64) * 100.0 / (img_bytes as f64);
        println!("coverage: {} bytes natively translated total; {} within the 512KB exe image ({:.1}%); {} overlay/extra bytes; {} functions",
                 total_bytes, in_img, pct, total_bytes - in_img, functions.len());
        let _ = fs::write("coverage.txt", format!(
            "translated_bytes {}\nimage_bytes {}\nin_image_bytes {}\noverlay_extra_bytes {}\ntranslated_functions {}\ncoverage_pct {:.1}\n",
            total_bytes, img_bytes, in_img, total_bytes - in_img, functions.len(), pct));
    }

    /* R922 (b8-c27, manager - E0382 LESSON): R921 shipped a seam scan
 * that borrowed the emitted source AFTER fs::write(&out_path, c) had
 * MOVED it - borrow-of-moved-value, cargo failed on the Mac (rc=101),
 * one dead cycle. Fix: fs::write borrows (&c). Standing check for every
 * future main.rs ship: if no local cargo, audit every use-after-write of
 * heap values; verify moves with the same rigor as the runtime nm check. */
// R921 PHASE 4 SEAM INVENTORY v1 (Jos directive 22:15/22:24 - the HLE
    // contract): the emitted code builds every hardware-register access
    // from the MMIO page base ("0x1F80u << 16"); counting those sites per
    // function yields the platform-seam checklist - which functions speak
    // to hardware and how often. This turns runtime archaeology into a
    // contract list the roster works top-down. v1 counts; v2 will list
    // the register offsets each site touches.
    {
        let mut seam_fns = std::collections::BTreeSet::<String>::new();
        let mut cur = String::new();
        let mut total = 0u64;
        for line in c.lines() {
            let t = line.trim_start();
            if t.starts_with("static void xenolift_fn_") {
                if let Some(n) = t.split('(').next() {
                    cur = n.trim_start_matches("static void ").to_string();
                }
            } else if line.contains("0x1F80u << 16") {
                total += 1;
                if !cur.is_empty() { seam_fns.insert(cur.clone()); }
            }
        }
        let _ = fs::write("seams.txt", format!(
            "mmio_page_base_hits {}\nseam_functions {}\n", total, seam_fns.len()));
        println!("seams: {} hardware-touch sites across {} functions (seams.txt - the HLE contract list v1)",
                 total, seam_fns.len());
    }
}
