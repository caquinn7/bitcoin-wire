export function native_length(hex) {
  return hex.length;
}

const HEX_DIGITS = /^[0-9A-Fa-f]*$/;

export function has_only_hex_digits(hex) {
  return HEX_DIGITS.test(hex);
}
