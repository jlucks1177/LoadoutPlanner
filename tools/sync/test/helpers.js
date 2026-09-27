// Test helpers: make talent strings, and a fake Raider.IO API.

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/**
 * Encode a talent string the way the game does (the inverse of
 * talentString.js): little-endian values, 6 bits per character, LSB first.
 * content: a string of '0'/'1' standing in for the talent records.
 */
export function makeCode({ version = 2, specID, hash = 0, content }) {
  const bits = [];
  const push = (value, width) => {
    for (let i = 0; i < width; i++) bits.push(Math.floor(value / 2 ** i) % 2);
  };
  push(version, 8);
  push(specID, 16);
  for (let i = 0; i < 16; i++) push(i === 0 ? hash : 0, 8); // 128-bit hash
  for (const ch of content) bits.push(ch === '1' ? 1 : 0);
  while (bits.length % 6 !== 0) bits.push(0);
  let code = '';
  for (let i = 0; i < bits.length; i += 6) {
    let value = 0;
    for (let b = 0; b < 6; b++) value += bits[i + b] << b;
    code += ALPHABET[value];
  }
  return code;
}

/**
 * A fake fetch that answers from a routing function:
 *   routes(pathname, searchParams) -> { status, body, headers } | object (200 JSON)
 * Records every URL it was asked for in fake.calls.
 */
export function fakeFetch(routes) {
  const fake = async (url) => {
    fake.calls.push(url);
    const { pathname, searchParams } = new URL(url);
    const result = routes(pathname.replace(/^\/api\/v1/, ''), searchParams);
    const response = result && result.status ? result : { status: 200, body: result };
    return {
      ok: response.status >= 200 && response.status < 300,
      status: response.status,
      headers: { get: (name) => (response.headers || {})[name.toLowerCase()] ?? null },
      json: async () => response.body,
    };
  };
  fake.calls = [];
  return fake;
}
