/**
 * figma-harness: WCAG Contrast Utilities
 *
 * Paste getLuminance + contrastRatio at the top of any use_figma script
 * that needs to verify contrast before creating or migrating color tokens.
 *
 * Thresholds (WCAG AA):
 *   Text roles:           4.5:1 minimum
 *   UI component edges:   3.0:1 minimum
 *   Large text (18px+):   3.0:1 minimum
 */

function getLuminance(hex) {
  const rgb = [
    parseInt(hex.slice(1, 3), 16) / 255,
    parseInt(hex.slice(3, 5), 16) / 255,
    parseInt(hex.slice(5, 7), 16) / 255,
  ].map(c => c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
  return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
}

function contrastRatio(fg, bg) {
  const L1 = getLuminance(fg);
  const L2 = getLuminance(bg);
  return ((Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05)).toFixed(2);
}

function rgbToHex({ r, g, b }) {
  const toHex = n => Math.round(n * 255).toString(16).padStart(2, '0');
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
}

// Example usage — check a semantic color role in both modes:
// const ratio = contrastRatio('#1A1A1A', '#FFFFFF');
// if (parseFloat(ratio) < 4.5) return `FAIL: ${ratio}:1`;