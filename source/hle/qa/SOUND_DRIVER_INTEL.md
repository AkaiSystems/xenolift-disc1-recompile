# xenolift Sound Driver Intel & SPU HLE Module Audit
**Document version:** 1.0 (2026-09-11)  
**Target:** Xenogears USA Disc-1 (SLUS-006.64) Sound Driver Architecture & SPU Subsystem (`hle_spu.c`)

---

## 1. Overview & Sound Driver Architecture

The Xenogears sound driver architecture (`system/sound.c`) manages 24 physical SPU voices, music scores (SMDS), sound effects (SEDS), wave sample banks (WDS), sequence modulation, and hardware DSP reverb.

### Key Entry Points & Global Symbols
- **`InitializeSoundSystem` (`0x80037C80`)**: Initializes the sound heap (`0x80065B10`-`0x8006BE00`), resets SPU registers, clears driver registries, and installs the 240Hz timer callback.
- **`SoundSequencerCallback240Hz` (`0x8003C020`)**: Root-counter timer interrupt handler running 240 times per second (~4.167ms period). Orchestrates sequence step evaluation, 4-slot modulator updates, voice staging, and SPU MMIO register flushes.
- **`InterpretReadySequenceTracks` (`0x8003C6E8`)**: Evaluates active SEDS and SMDS sequence bytecode instructions up to the next timed note, rest, or delay.
- **`LoadAndRegisterWdsBank` (`0x80037FD8`)**: Allocates SPU RAM -> initiates async ADPCM DMA upload via channel 4 -> copies 16-byte preset records into driver main RAM -> records hardware SPU base address -> links bank to loaded-WDS registry.
- **`LoadInstrumentVoiceParameters` (`0x8003E5BC`)**: Reads 16-byte WDS preset records (offsets `+0x00`..`+0x0D`) to establish voice ADPCM start/repeat addresses, Q8 tuning, and ADSR envelopes.
- **`StageTrackVoiceParameters` (`0x8003EBF0`)**: Derives per-track pitch, volume, pan, and envelope state, marks voice fields dirty, and enqueues pending key-ons/key-offs.
- **`CommitPendingSpuVoiceKeyOffs` (`0x8003EB5C`)**: Fast-releases voices awaiting termination and writes Key Off masks (`0x1F801D8C` / `0x1F801D8E`).
- **`CommitPendingSpuVoiceWrites` (`0x8003E900`)**: Flushes dirty voice registers, updates global feature masks (PMON, NON, EON), and writes Key On masks (`0x1F801D88` / `0x1F801D8A`).
- **`SoundSpuIRQHandler` (`0x8003BFA0`)**: SPU IRQ interrupt handler installed via `SpuSetIRQCallback`. Bumps `g_SoundSpuIRQCount` (`0x80069514`) and executes `g_SoundSpuIrqCallbackFn` (`0x8006950C`).
- **`SetReverbModeDepthDelayFeedback` (`0x80038934`)**: Reallocates SPU RAM reverb work area and writes hardware reverb DSP registers (`0x1F801DC0`-`0x1F801DFE`).

---

## 2. File Formats: WDS, SEDS, SMDS & ADPCM Layout

All sound resources are little-endian and begin with a 4-byte ASCII magic header.

### 2.1 WDS Wave Banks (`wds `)
WDS contains instrument preset descriptors and raw PS1 ADPCM compressed audio samples.

#### WDS Header Structure (`0x0000` - `0x002F`)
| Offset | Size | Field | Meaning |
|---:|---:|---|---|
| `0x00` | 4 B | `magic` | ASCII `"wds "` (`0x20736477`) |
| `0x04` | 4 B | `checksum` | 32-bit checksum word (balances header sum to 0 mod $2^{32}$) |
| `0x08` | 4 B | `hdr_size_copy` | Copy of header size; must equal `0x00000010` |
| `0x0C` | 4 B | `marker` | Format marker; must be `0x00000101` |
| `0x10` | 4 B | `header_size` | Offset where preset array ends and ADPCM payload begins |
| `0x14` | 4 B | `adpcm_size` | Nonzero size of ADPCM payload (multiple of 16) |
| `0x18` | 4 B | `adpcm_offset` | Offset of ADPCM payload (equals `header_size`) |
| `0x1C` | 2 B | `count_minus_one` | Preset count $- 1$ (actual preset count = value $+ 1$) |
| `0x1E` | 2 B | `alloc_aux` | Auxiliary value passed to SPU allocator (0 in retail corpus) |
| `0x20` | 2 B | `wds_id` | Bank ID used by sequence opcodes |
| `0x22` | 6 B | `reserved` | Reserved zero bytes |
| `0x28` | 4 B | `spu_address` | Configured SPU RAM base byte address requested by loader |
| `0x2C` | 4 B | `next_ptr` | Runtime next pointer in loaded WDS linked list (0 on disc) |

$$\text{header\_size} = 0x30 + \text{preset\_count} \times 16, \quad \text{total\_size} = \text{adpcm\_offset} + \text{adpcm\_size}$$

#### WDS Preset Record (`0x30 + preset_index * 16`, 16 bytes)
```c
struct WdsPreset {
    uint32_t start_units;      /* +0x00: ADPCM start offset in 8-byte units */
    uint16_t repeat_units;     /* +0x04: Loop repeat displacement in 8-byte units from start */
    int16_t  pitch_q8;          /* +0x06: Signed Q8 semitone tuning adjustment */
    uint32_t adsr;              /* +0x08: Packed SPU ADSR envelope rates and level */
    uint16_t modes;             /* +0x0C: ADSR mode/shape bits */
    uint8_t  authoring_value;   /* +0x0E: Nominal gain/velocity (0x7F in 774 presets, ignored by loader) */
    uint8_t  reserved;          /* +0x0F: Reserved zero */
};
```
- **Byte address calculation**:
  $$\text{start\_byte} = \text{start\_units} \times 8, \quad \text{repeat\_byte} = \text{start\_byte} + \text{repeat\_units} \times 8$$
- **Packed ADSR Bit Allocation (`adsr` field, `+0x08`)**:
  - Bits `0..6`: Attack rate ($0..127$)
  - Bits `8..11`: Decay rate ($0..15$)
  - Bits `12..15`: Sustain level ($0..15$, scaled to $0..0x7FFF$ in steps of $0x0800$)
  - Bits `16..22`: Sustain rate ($0..127$)
  - Bits `24..28`: Release rate ($0..31$)
- **Packed ADSR Modes (`modes` field, `+0x0C`)**:
  - Bit 2: Exponential Attack ($1 = \text{exp}, 0 = \text{linear}$)
  - Bit 5: Sustain Direction ($1 = \text{decrease}, 0 = \text{increase}$)
  - Bit 6: Exponential Sustain ($1 = \text{exp}, 0 = \text{linear}$)
  - Bit 10: Exponential Release ($1 = \text{exp}, 0 = \text{linear}$)
- **Out-of-range preset behavior**:
  The driver computes $\text{record} = \text{bank\_header} + 0x30 + \text{preset\_index} \times 16$ without checking bounds first. In WDS 3, preset 23, this read deliberately enters the ADPCM region; the resulting bytes form a valid instrument descriptor with block-aligned SPU addresses.

#### PS1 ADPCM Payload Layout
Each ADPCM block is 16 bytes and decodes to 28 signed 16-bit PCM samples ($44.1\text{ kHz}$):
- **Byte 0**: Low nibble = shift factor ($0..12$); High nibble = predictor/filter index ($0..4$).
- **Byte 1**: Flag bits:
  - Bit 0 (`0x01`): Loop End
  - Bit 1 (`0x02`): Loop Repeat (repeat from `repeat_addr`)
  - Bit 2 (`0x04`): Loop Start (latch current block address as loop start)
- **Bytes 2..15**: 14 bytes containing 28 4-bit nibble samples (low nibble first).
- **Filter Predictors**:
  $$K_0 = \{0, 60, 115, 98, 122\}, \quad K_1 = \{0, 0, -52, -55, -60\}$$
  $$\text{predict} = \frac{s_1 \cdot K_0[f] + s_2 \cdot K_1[f] + 32}{64}$$

---

### 2.2 SEDS Sound-Effect Banks (`seds`)
SEDS stores bank collections of two-channel short sound-effect sequences.

#### SEDS Header Layout (`0x0000` - `0x001F`)
- `0x00` (4B): Magic ASCII `"seds"` (`0x73646573`)
- `0x04` (4B): Checksum word (balances sum to 0 mod $2^{32}$)
- `0x08` (4B): Total resource byte size
- `0x0C` (4B): Format marker (`0x00000101`)
- `0x10` (2B): Effect policy flags (Bit 0 marks active tracks to prevent opcode `0xBA` reverb override)
- `0x12` (2B): Effect count ($> 0$)
- `0x14` (2B): SEDS Bank ID
- `0x16` (2B): Default WDS Bank ID for initial tracks
- `0x18` (4B): Volume table offset (must equal `0x20 + effect_count * 4`)
- `0x1C` (4B): Runtime next pointer in loaded-SEDS list
- `0x20`: Channel script-offset table ($2 \times \text{uint16}$ offsets per effect: channel 0 and channel 1)
- **Volume Table**: Array of $1 \times \text{uint8}$ volume byte per effect immediately following script offsets.
- **State Excluded from SEDS**: SEDS contains no initial reverb mode/depth, reverb RAM, physical voice allocation, or global noise parameters; these are set by game code before triggering effects.

---

### 2.3 SMDS Music Scores (`smds`)
SMDS stores multi-track background music scores.

#### SMDS Header Layout (`0x0000` - `0x0021`)
- `0x00` (4B): Magic ASCII `"smds"` (`0x73646D73`)
- `0x04` (4B): Checksum word
- `0x08` (4B): Total resource byte size
- `0x0C` (2B): Common marker (`0x0101`)
- `0x0E` (2B): Reserved / variant byte
- `0x10` (2B): Opaque sequence tag
- `0x12` (2B): SMDS format marker (`0x0102`, constant across all 63 retail SMDS files)
- `0x14` (1B): Logical track count ($1..16$)
- `0x15` (1B): Sparse percussion patch count
- `0x16` (2B): Default WDS Bank ID
- `0x18` (2B): Initial gain metadata (0x007F)
- `0x1A` (1B): Reverb Mode ($0..9$, mode 4 in all retail SMDS)
- `0x1B` (1B): Initial Reverb Depth
- `0x1C` (1B): Reverb Delay
- `0x1D` (1B): Reverb Feedback
- `0x1E` (2B): Resource-relative offset to NUL-terminated ASCII internal score name
- `0x20` (2B): Resource-relative offset to sparse percussion patch table
- `0x22`: Track script offset table ($1 \times \text{uint16}$ offset per track)
  - Followed by a 2-byte trailer slot (`0x22 + track_count * 2`) and internal score name string (e.g., `"battle1"`, `"lahan"`, `"world"`).
- **Sparse Percussion Patch Record (5 bytes per patch)**:
  `[0: Mapping index (0..95), 1: WDS preset index, 2: Replacement note, 3: Authoring gain (0x78), 4: Pan]`
  - Expanded in driver RAM to 4 bytes (`preset`, `note`, `ignored`, `pan`).

---

## 3. Sequence Bytecode & Opcode Essentials

Tracks execute sequence bytecode. Byte values `0x00..0x7F` represent timed notes; `0x80..0xFF` are control commands.

### 3.1 Note Encoding (`0x00..0x7F`)
A note instruction consists of 2 or 3 bytes:
- **Byte 0**: Note Velocity ($0x00..0x7F$)
- **Byte 1**: Selector $= \text{semitone} \times 19 + \text{duration\_index}$
- **Byte 2**: Explicit duration byte (present **only** if $\text{duration\_index} == 0$)

$$\text{semitone} = \lfloor\text{selector} / 19\rfloor, \quad \text{duration\_index} = \text{selector} \bmod 19$$
$$\text{note\_pitch\_q8} = (\text{track\_octave} + \text{semitone}) \times 256$$

#### 19-Entry Duration Lookup Table
| Index | Ticks | Index | Ticks | Index | Ticks | Index | Ticks |
|---:|---:|---:|---:|---:|---:|---:|---:|
| **0** | *Explicit byte* | **5** | 64 | **10** | 18 | **15** | 6 |
| **1** | 192 | **6** | 48 | **11** | 16 | **16** | 4 |
| **2** | 144 | **7** | 36 | **12** | 12 | **17** | 3 |
| **3** | 96 | **8** | 32 | **13** | 9 | **18** | 2 |
| **4** | 72 | **9** | 24 | **14** | 8 | | |

#### Gate & Tie Rules
- Persistent note hold or pending tie: $\text{gate} = 0x7FFF$ (no key-off).
- Gate Mode `0x0F`: $\text{gate} = \max(1, \text{duration} - 1)$
- Gate Mode `0x10`: $\text{gate} = \text{duration}$
- Other Gate Modes: $\text{gate} = \max(1, \lfloor\text{duration} \times \text{mode} / 16\rfloor)$
- **Lookahead**: If the next timed command is another note, the driver applies fast linear release rate 6 one tick prior to note boundary.

---

### 3.2 Key Opcode Reference (`0x80..0xFF`)

| Opcode | Bytes | Description |
|---:|---:|---|
| `0x80` | 2 | Rest for $N$ ticks; immediately sends key-off to active voice |
| `0x81` | 2 | Tie / wait for $N$ ticks without key-off or re-trigger |
| `0x90` | 1 | Jump to saved repeat loop point (from `0x91`); ends track if none set |
| `0x91` | 1 | Save current PC and octave as song repeat point |
| `0x94` | 2 | Set base octave to $\text{operand} \times 12$ semitones |
| `0x95` / `0x96` | 1 | Raise / Lower octave by 12 semitones |
| `0x98` | 2 | Begin counted loop (count operand; nesting depth up to 4) |
| `0x99` | 1 | Repeat or terminate counted loop |
| `0x9A` | 1 | Final-iteration break / alternate loop branch |
| `0xA0` | 2 | Set track tempo immediately |
| `0xA2` | 3 | Tempo slide `[duration, target_tempo]` |
| `0xA6` | 2 | Set track manager volume ($\text{operand} \ll 24$) |
| `0xA9` | 2 | Set gate mode ($0x00..0x10$) |
| `0xAC` | 2 | Select and load preset from currently selected WDS |
| `0xAD` | 2 | Add signed duration adjustment (0 resets) |
| `0xAE` / `0xAF` | 1 | Enable / Disable sparse percussion patch mapping |
| `0xB0` / `0xB1` | 1 | Enable / Disable persistent note hold |
| `0xB2` / `0xB3` | 1 | Enable / Disable SPU Pitch Modulation (FM) on paired voice ($v-1 \to v$) |
| `0xB4` | 2 | Set global SPU noise clock ($0..63$) and enable noise for track |
| `0xB5` | 2 | Add to global SPU noise clock mod 64 and enable noise |
| `0xB6` / `0xB7` | 1 | Enable / Disable noise source without changing clock |
| `0xB8` | 4 | Set global reverb depth, delay, and feedback |
| `0xBA` / `0xBB` | 1 | Enable / Disable global SPU reverb send for track voice |
| `0xC0` | 1 | Reload current preset parameters from selected WDS |
| `0xC2` | 2 | Override Attack rate (ADSR bits `0..6`) |
| `0xC3` | 2 | Override Decay rate (ADSR bits `8..11`) |
| `0xC4` | 2 | Override Sustain rate (ADSR bits `16..22`) |
| `0xC5` | 2 | Override Release rate (ADSR bits `24..28`) |
| `0xC6` | 2 | Override Sustain level (ADSR bits `12..15`) |
| `0xC7` | 3 | Override Decay rate and Sustain level together |
| `0xD0` / `0xD1` | 2 | Set / Add signed pitch offset in $1/8$-semitone steps ($\text{operand} \times 32$ Q8 units) |
| `0xD2` | 2 | Add signed pitch offset in $1/32$-semitone steps ($\text{operand} \times 8$ Q8 units) |
| `0xD3` | 3 | Add 16-bit signed Q8 pitch delta |
| `0xD4` | 3 | Relative pitch slide `[duration, signed_semitones]` |
| `0xE0` / `0xE1` | 2 | Set / Add track volume delta |
| `0xE2` | 3 | Volume slide `[duration, target_vol]` |
| `0xE8` / `0xE9` | 2 | Set / Add track pan delta |
| `0xEA` | 3 | Pan slide `[duration, target_pan]` |
| `0xFC` | 3 | Select WDS ID and preset index, then load instrument parameters immediately |
| `0xFD` | 2 | Set tempo scale factor ($\text{operand} \ll 8$) |
| `0xFE` | 2 | Change selected WDS ID **without** loading preset parameters |

#### Instrument Lifetime & WDS Distinction
The driver maintains separate **Selected WDS ID** and **Loaded WDS ID** state per track:
- `0xFE wds_id`: Updates Selected WDS ID only. Existing notes continue playing using the previously loaded preset.
- `0xAC preset`: Loads instrument parameters from the newly Selected WDS ID.
- `0xFC wds_id, preset`: Sets Selected WDS ID and loads instrument parameters immediately.

---

### 3.3 Track Modulators
Each sequence track owns 4 independent LFO modulator slots evaluated on every 240Hz callback (~4.167ms):
- **Destinations**: Slot 0 = Pitch, Slot 1 = Volume attenuation, Slot 2 = Pan.
- **Period Conversion**: $\text{period\_callbacks} = \text{val} + \lfloor\text{val}^2 / 64\rfloor$
- **Waveforms ($0..7$)**:
  0. Pulse (alternate 0 and positive amplitude)
  1. Square (bipolar positive/negative amplitude)
  2. Triangle (linear ramp with direction reversal)
  3. Asymmetric triangle
  4. Sawtooth (rising ramp reset at period boundary)
  5. Sawtooth variant
  6. Unipolar PRNG noise (uses dedicated 32-bit xorshift generator)
  7. Bipolar PRNG noise

---

## 4. SPU Register Write Pattern (Driver Commit Path)

During each 240Hz callback frame $N$, the sound driver executes a strict, 4-step register commit sequence to flush staged voice changes to SPU MMIO registers (`0x1F801C00` - `0x1F801DAF`).

```
  [Callback Frame N]
        │
        ├── 1. CommitPendingSpuVoiceKeyOffs (0x8003EB5C)
        │      ├── Write ADSR High = linear release 6 (0x1F801C0A + v*10h)
        │      └── Write Key Off Low/High (0x1F801D8C / 0x1F801D8E)
        │
        ├── 2. Interpret Sequence Tracks & Evaluate Modulators
        │      └── Stage parameters for Frame N+1 (set dirty flags)
        │
        └── 3. CommitPendingSpuVoiceWrites (0x8003E900)
               ├── Voice 0..23 dirty field updates:
               │   ├── Vol L/R     (0x1F801C00 / 0x1F801C02)
               │   ├── Pitch       (0x1F801C04)
               │   ├── Start Addr  (0x1F801C06, byte_addr >> 3)
               │   ├── ADSR L/H    (0x1F801C08 / 0x1F801C0A)
               │   └── Repeat Addr (0x1F801C0E, byte_addr >> 3)
               ├── Write Global Feature Masks:
               │   ├── PMON Low/High (0x1F801D90 / 0x1F801D92)
               │   ├── NON  Low/High (0x1F801D94 / 0x1F801D96)
               │   └── EON  Low/High (0x1F801D98 / 0x1F801D9A)
               └── Write Key On Low/High (0x1F801D88 / 0x1F801D8A)
```

### Detailed Write Sequence & Register Map
1. **Key Off Commit (`0x8003EB5C`)**:
   - For voices with pending release: writes `(adsr_high & 0xFFC0) | 0x0006` to `0x1F801C0A + v * 0x10`.
   - `0x1F801D8C`: Key Off Low (voices 0..15)
   - `0x1F801D8E`: Key Off High (voices 16..23)
2. **Per-Voice Parameter Commit (`0x8003E900`)**:
   - Iterates $v = 0..23$. Checks per-voice dirty bitmask `a3`:
     - Bit 0 (`0x0001`): `0x1F801C00 + v*10h` = Volume Left, `0x1F801C02 + v*10h` = Volume Right
     - Bit 2 (`0x0004`): `0x1F801C04 + v*10h` = Pitch ($0x1000 = 44.1\text{ kHz}$)
     - Bit 3 (`0x0008`): `0x1F801C06 + v*10h` = Start Address ($\text{byte\_addr} / 8$)
     - Bit 4 (`0x0010`): `0x1F801C08 + v*10h` = ADSR Low
     - Bit 5 (`0x0020`): `0x1F801C0A + v*10h` = ADSR High
     - Bit 15 (`0x8000`): `0x1F801C0E + v*10h` = Repeat Address ($\text{byte\_addr} / 8$)
3. **Global Control Mask Commit (`0x8003E900`)**:
   - `0x1F801D90` / `0x1F801D92`: Pitch Modulation Enable Low/High (PMON)
   - `0x1F801D94` / `0x1F801D96`: Noise Enable Low/High (NON)
   - `0x1F801D98` / `0x1F801D9A`: Reverb Enable Low/High (EON)
4. **Key On Trigger Commit (`0x8003E900`)**:
   - `0x1F801D88`: Key On Low (voices 0..15)
   - `0x1F801D8A`: Key On High (voices 16..23)

### Auxiliary & Global Driver Register Operations
- **Master Volume**: `0x1F801D80` (Left), `0x1F801D82` (Right)
- **Reverb Master Volume**: `0x1F801D84` (Left), `0x1F801D86` (Right)
- **CD Audio Volume**: `0x1F801DB0` (Left), `0x1F801DB2` (Right)
- **External Volume**: `0x1F801DB4` (Left), `0x1F801DB6` (Right)
- **SPU Control / Status**:
  - `0x1F801DAA` (`SPUCNT`): Bit 15 = SPU Enable/Unmute, Bit 6 = IRQ Enable, Bit 7 = Reverb Enable, Bits 4-5 = DMA Transfer Mode.
  - `0x1F801DAC` (`SPUDAC`): Sound RAM Data Transfer Control (`0x0004`).
  - `0x1F801DAE` (`SPUSTAT`): SPU Status readback (reflects lower 6 bits of `SPUCNT` + DMA/IRQ flags).
- **SPU Transfer**:
  - `0x1F801DA6`: SPU RAM Transfer Start Address ($\text{byte\_addr} / 8$).
  - `0x1F801DA8`: SPUDATA FIFO (16-bit manual transfer port).
- **Reverb Setup**:
  - `0x1F801DA2`: SPU RAM Reverb Work Area Start Address ($\text{byte\_addr} / 8$).
  - `0x1F801DC0` - `0x1F801DFE`: 16 pairs / 32 words of hardware reverb DSP parameters (vIIN, vCOMB, vWALL, vAPF, mLSAME, mRSAME, etc.).
- **SPU IRQ**:
  - `0x1F801DA4`: SPU IRQ Byte Address ($\text{byte\_addr} / 8$).

---

## 5. Audit of `hle_spu.c` Coverage vs Driver Writes

### 5.1 Confirmed Harness & Module Facts
1. **512KB SPU RAM**: Fully allocated and modeled (`g_spu.ram[524288]`).
2. **SPUCNT & Transfer Port**: `0x1F801DAA`, `0x1F801DAC`, `0x1F801DA6`, and `0x1F801DA8` are correctly intercepted and updated.
3. **Channel 4 DMA Feeds**: Verified in `run.log`. A $152,576\text{ B}$ sound-bank upload successfully tiles SPU RAM `0x00000`-`0x25400` in $2048\text{ B}$ chunks via `hle_spu_dma_write()`.
4. **Silent Dummy Loop Blocks**: Dummy silent ADPCM loop blocks at SPU `0x0000` and `0x0400` initialized on reset match live driver mute loop expectations.

---

### 5.2 SPU Register Audit Matrix

| Address | Hardware Register Name | Driver Usage | `hle_spu.c` Status | Audit Finding |
|---|---|---|---|---|
| `0x1F801C00 + v*10` | Voice $v$ Volume Left | Written in commit | **HANDLED** (`voice->vol_l`) | Exact match |
| `0x1F801C02 + v*10` | Voice $v$ Volume Right | Written in commit | **HANDLED** (`voice->vol_r`) | Exact match |
| `0x1F801C04 + v*10` | Voice $v$ Pitch / Sample Rate | Written in commit | **HANDLED** (`voice->pitch`) | Exact match |
| `0x1F801C06 + v*10` | Voice $v$ Start Address | Written in commit | **HANDLED** (`start_addr = v*8`) | Exact match |
| `0x1F801C08 + v*10` | Voice $v$ ADSR Low | Written in commit | **HANDLED** (`voice->adsr_low`) | Exact match |
| `0x1F801C0A + v*10` | Voice $v$ ADSR High | Written in commit | **HANDLED** (`voice->adsr_high`) | Exact match |
| `0x1F801C0C + v*10` | Voice $v$ Current ADSR Level | Written on reset | **HANDLED** (`voice->adsr_level`) | Read/write mapped |
| `0x1F801C0E + v*10` | Voice $v$ Repeat Address | Written in commit | **HANDLED** (`repeat_addr = v*8`) | Exact match |
| `0x1F801D80` | Main Volume Left | Written in init/fade | **HANDLED** (`g_spu.mvol_l`) | Exact match |
| `0x1F801D82` | Main Volume Right | Written in init/fade | **HANDLED** (`g_spu.mvol_r`) | Exact match |
| `0x1F801D84` | Reverb Volume Left | Written in init/reverb | **HANDLED** (`g_spu.svol_l`) | Exact match |
| `0x1F801D86` | Reverb Volume Right | Written in init/reverb | **HANDLED** (`g_spu.svol_r`) | Exact match |
| `0x1F801D88` | Key On Low (0..15) | Written in commit | **HANDLED** (`spu_voice_key_on`) | Triggers attack phase & start_addr |
| `0x1F801D8A` | Key On High (16..23) | Written in commit | **HANDLED** (`spu_voice_key_on`) | Triggers attack phase & start_addr |
| `0x1F801D8C` | Key Off Low (0..15) | Written in commit | **HANDLED** (`spu_voice_key_off`) | Triggers release phase |
| `0x1F801D8E` | Key Off High (16..23) | Written in commit | **HANDLED** (`spu_voice_key_off`) | Triggers release phase |
| `0x1F801D90/92` | Pitch Modulation (PMON) | Written in commit | **PARTIAL** (`g_spu.pmon_flags`) | Register saved; FM synthesis not implemented |
| `0x1F801D94/96` | Noise Enable (NON) | Written in commit | **PARTIAL** (`g_spu.non_flags`) | Register saved; Noise generator not implemented |
| `0x1F801D98/9A` | Reverb Enable (EON) | Written in commit | **PARTIAL** (`g_spu.eon_flags`) | Register saved; Reverb send not implemented |
| `0x1F801D9C/9E` | Voice End Flags (ENDX) | Read by driver | **HANDLED** (`g_spu.endx_flags`) | Set on loop end flag; cleared on write/key-on |
| `0x1F801DA2` | Reverb Work Base Addr | Written in reverb setup | **GAP (IGNORED)** | Dropped to `default: break` |
| `0x1F801DA4` | SPU IRQ Byte Address | Written in init/stream | **PARTIAL** (`g_spu.irq_addr`) | Register saved; IRQ comparison/trigger missing |
| `0x1F801DA6` | Transfer Start Address | Written on DMA/FIFO | **HANDLED** (`g_spu.transfer_addr`) | Exact match |
| `0x1F801DA8` | SPUDATA Transfer FIFO | Written on manual transfer | **HANDLED** (RAM write + autoincrement) | Exact match |
| `0x1F801DAA` | SPU Control (`SPUCNT`) | Written in init/mode | **HANDLED** (`g_spu.spucnt`) | Reflected in SPUSTAT |
| `0x1F801DAC` | SPU Data Control (`SPUDAC`)| Written in init | **HANDLED** (`g_spu.spudac`) | Stored |
| `0x1F801DAE` | SPU Status (`SPUSTAT`) | Read by driver | **HANDLED** (`g_spu.spustat`) | Returns status flags |
| `0x1F801DB0/B2` | CD Volume Left / Right | Written in init/XA | **HANDLED** (`g_spu.cd_vol_l/r`) | Stored |
| `0x1F801DB4/B6` | Ext Volume Left / Right | Written in init | **HANDLED** (`g_spu.ext_vol_l/r`) | Stored |
| `0x1F801DC0..DFE`| Reverb DSP Registers (32W)| Written in reverb setup | **GAP (IGNORED)** | Dropped to `default: break` |
| `0x1F801E00..E5F`| Voice Current Volume | Read by driver | **HANDLED** (`0x0200..0x025F`) | Envelope $\times$ volume readback |

---

### 5.3 SPU IRQ Expectations (`SoundSpuIRQHandler` Context)
When the SPU playback or transfer position reaches `irq_addr` (`0x1F801DA4`) and `SPUCNT` bit 6 (`0x0040`) is set:
1. The hardware sets `SPUSTAT` bit 6 (`0x0040`).
2. System raises PS1 interrupt INT9 $\to$ invokes `SoundSpuIRQHandler` (`0x8003BFA0`).
3. `SoundSpuIRQHandler`:
   - Sets bit `0x0004` in driver status cell `0x8006957C`.
   - Increments `g_SoundSpuIRQCount` (`0x80069514`).
   - Invokes `g_SoundSpuIrqCallbackFn` (`0x8006950C`) if non-zero.
   - Clears bit `0x0004` in `0x8006957C` and returns.

**Runtime Requirement**: For full IRQ streaming support, `hle_spu_generate()` must check if any active voice's `current_addr` matches `irq_addr`, set `SPUSTAT` bit 6, and expose an IRQ pending flag so `runtime.c` can fire `SoundSpuIRQHandler`.

---

## 6. Top 3 Coverage Gaps & Runtime Digest Verification

### 6.1 Three Biggest Coverage Gaps in `hle_spu.c`
1. **Reverb DSP Registers & Work Base Address (`0x1F801DA2`, `0x1F801DC0` - `0x1F801DFE`)**:
   - *Impact*: Writes to `0x1F801DA2` (Reverb Work Area Base Address) and `0x1F801DC0`..`0x1F801DFE` (32 hardware reverb parameter registers) are currently dropped in `hle_spu_port_write()`. While dry ADPCM audio renders correctly, wet reverb sends (`EON`) produce no reverberation.
   - *Fix*: Add register storage for `reverb_work_addr` (`0x01A2`) and `reverb_regs[32]` (`0x01C0`..`0x01FE`), and model a basic comb/allpass delay buffer in `hle_spu_generate()`.
2. **SPU Hardware IRQ Triggering (`0x1F801DA4` / `SoundSpuIRQHandler`)**:
   - *Impact*: `hle_spu.c` stores `irq_addr`, but `hle_spu_generate()` does not compare voice sample playback addresses against `irq_addr` or trigger SPU IRQs. Streaming audio callbacks that rely on SPU IRQ timing will stall waiting for `g_SoundSpuIRQCount`.
   - *Fix*: Add IRQ address checking inside `hle_spu_generate()` when `spucnt & 0x0040` is true, setting `spustat |= 0x0040` and returning an IRQ trigger flag to `runtime.c`.
3. **Pitch Modulation (FM) & Noise Generator Logic (`PMON` / `NON`)**:
   - *Impact*: `g_spu.pmon_flags` and `g_spu.non_flags` are stored on write, but `hle_spu_generate()` does not apply frequency modulation ($v-1 \to v$) or LFSR noise generation. Sound effects using FM or white noise (e.g., explosions, wind, engine rumble) play back as standard ADPCM pitches or silent blocks.
   - *Fix*: In `hle_spu_generate()`, when voice $i$ has bit $i$ set in `pmon_flags`, multiply voice $i$'s step size by $(1 + \text{pcm}_{i-1} / 32768)$. When bit $i$ is set in `non_flags`, substitute SPU LFSR noise counter samples for decoded ADPCM.

---

### 6.2 What to Watch in Runtime Digests
To verify driver behavior and sound bank loading during recompiled execution, inspect these lines in `run.log`:

1. **`=SPUDMA=` Digest (Async Sound-Bank Uploads)**:
   ```text
   [spu-dma] ch4 start addr 0x80067210, len 2048B -> spu_ram 0x0
   [hle-spu] dma feed 2048B @spu 0x0 (total 2048B)
   ```
   - *What to verify*: Confirm that sound bank uploads tile SPU RAM starting from `0x00000` up to `0x25400` in $2048\text{ B}$ chunks via Channel 4 DMA. Verify that `SPUCNT` bit 7 and `0x1F801DA6` update appropriately.
2. **`=SPURAM=` Digest (SPU RAM State & Mute Loop)**:
   ```text
   [hle-spu] ram snapshot 524288B -> spu_ram.bin | dma total 152576B last pos 0x25400
   ```
   - *What to verify*: Check that `spu_ram.bin` matches the $152,576\text{ B}$ WDS payload. Verify that SPU RAM addresses `0x0000` and `0x0400` maintain the silent dummy ADPCM block (`0x00 0x07 0x00...`) used by the driver's mute loop.
3. **Voice Commit Writes (`[spu]` / `[hle-spu]` Register Log)**:
   ```text
   [spu] write 0x1F801C00 = 0x3FFF  (Voice 0 Vol L)
   [spu] write 0x1F801C04 = 0x1000  (Voice 0 Pitch 44.1kHz)
   [spu] write 0x1F801D88 = 0x0001  (Key On Low: Voice 0)
   ```
   - *What to verify*: Observe the key-off $\to$ voice parameter staging $\to$ key-on sequence during 240Hz callbacks when music or sound effects begin playing.
