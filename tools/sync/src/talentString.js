// talentString.js
// Reading WoW talent import strings ("loadouts") without the game.
//
// Format (confirmed in Blizzard's ExportUtil.lua and
// Blizzard_ClassTalentImportExport.lua):
//   * base64 alphabet A-Z a-z 0-9 + /  - each character holds 6 bits
//   * bits are read LEAST significant first, and multi-bit values are
//     assembled little-endian (first bit read = lowest bit of the value)
//   * header: 8 bits version, 16 bits spec ID, 128 bits tree hash
//   * then one small record per talent node (the actual build)
//
// We need two things from it:
//   1. the spec ID, to file each player's build under the right spec
//   2. a "content key": the build WITHOUT the header. Two players on the
//      same talents can export different strings if their game had a
//      different tree hash (e.g. before/after a small patch), so we group
//      by content, not by the raw string.

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const VALUE = new Map([...ALPHABET].map((ch, i) => [ch, i]));

const VERSION_BITS = 8;
const SPEC_BITS = 16;
const HASH_BITS = 128;
const HEADER_BITS = VERSION_BITS + SPEC_BITS + HASH_BITS;

/** Decode to an array of bits (0/1), in the order the game reads them. */
export function toBits(code) {
  const bits = [];
  for (const ch of code) {
    const value = VALUE.get(ch);
    if (value === undefined) return null; // not a talent string
    for (let i = 0; i < 6; i++) bits.push((value >> i) & 1);
  }
  return bits;
}

/** Read `width` bits starting at `offset` as a little-endian number. */
function readValue(bits, offset, width) {
  let value = 0;
  for (let i = 0; i < width; i++) value += bits[offset + i] * 2 ** i;
  return value;
}

/**
 * Parse a talent string. Returns null if it isn't one.
 * { version, specID, contentKey }
 */
export function parseTalentString(code) {
  if (typeof code !== 'string') return null;
  const trimmed = code.trim();
  if (trimmed.length < 26) return null; // shorter than the header alone
  const bits = toBits(trimmed);
  if (!bits || bits.length <= HEADER_BITS) return null;

  const version = readValue(bits, 0, VERSION_BITS);
  const specID = readValue(bits, VERSION_BITS, SPEC_BITS);

  // Content key: everything after the header, with trailing zero bits
  // removed (they're just padding to a whole base64 character).
  let content = bits.slice(HEADER_BITS).join('');
  content = content.replace(/0+$/, '');
  return { version, specID, contentKey: `${version}:${specID}:${content}` };
}
