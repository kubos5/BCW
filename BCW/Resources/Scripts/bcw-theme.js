// Colori dinamici di BCW: la stessa generazione della versione web (js/theme.js), eseguita con
// JavaScriptCore sopra `material-color-utilities.js` (che espone `MCU`). Restituisce JSON con
// i ruoli di Material 3 per il tema chiaro e quello scuro, così l'app nativa e il sito hanno
// esattamente gli stessi colori per lo stesso colore d'accento, stile e contrasto.

var BCWTheme = (function () {
  var m = MCU;

  var schemeClass = {
    tonalSpot: 'SchemeTonalSpot', vibrant: 'SchemeVibrant', expressive: 'SchemeExpressive', fidelity: 'SchemeFidelity',
    neutral: 'SchemeNeutral', rainbow: 'SchemeRainbow', fruitSalad: 'SchemeFruitSalad',
  };
  var contrastLevel = { standard: 0, medium: 0.5, high: 1 };

  var ROLES = [
    'primary', 'on-primary', 'primary-container', 'on-primary-container',
    'secondary', 'on-secondary', 'secondary-container', 'on-secondary-container',
    'tertiary', 'on-tertiary', 'tertiary-container', 'on-tertiary-container',
    'error', 'on-error', 'error-container', 'on-error-container',
    'surface', 'surface-dim', 'surface-bright',
    'surface-container-lowest', 'surface-container-low', 'surface-container', 'surface-container-high', 'surface-container-highest',
    'on-surface', 'on-surface-variant', 'outline', 'outline-variant',
    'inverse-surface', 'inverse-on-surface', 'inverse-primary',
  ];

  function mixWhite(value, amount) {
    var n = parseInt(value.slice(1), 16);
    var parts = [16, 8, 0].map(function (shift) {
      var c = (n >> shift) & 255;
      var v = Math.min(Math.round(c + (255 - c) * amount), 254);
      var s = v.toString(16);
      return s.length < 2 ? '0' + s : s;
    });
    return '#' + parts.join('');
  }

  function build(accent, style, contrast) {
    var seed = m.Hct.fromInt(m.argbFromHex(accent));
    var level = contrastLevel[contrast] || 0;
    var Scheme = m[schemeClass[style] || 'SchemeTonalSpot'];
    var colors = new m.MaterialDynamicColors().allColors.filter(Boolean);
    var hex = function (argb) { return m.hexFromArgb(argb); };
    var tone = function (palette, t) { return hex(palette.tone(t)); };
    var toneOf = function (value) { return m.Hct.fromInt(m.argbFromHex(value)).tone; };

    function make(dark) {
      var scheme = new Scheme(seed, dark, level, '2025', 'phone');
      var legacy = new Scheme(seed, dark, level, '2021', 'phone');
      var values = {};
      colors.forEach(function (color) { values[color.name.replace(/_/g, '-')] = hex(color.getArgb(scheme)); });
      colors.forEach(function (color) {
        var name = color.name.replace(/_/g, '-');
        if (name === 'inverse-surface' || name === 'inverse-on-surface') values[name] = hex(color.getArgb(legacy));
      });
      var neutral = scheme.neutralPalette;
      values['surface-container-lowest'] = dark ? tone(neutral, 3) : mixWhite(values.surface, 0.6);
      if (level === 0) {
        values['outline-variant'] = tone(scheme.neutralVariantPalette, dark ? 26 : 84);
        if (dark) {
          [['primary', scheme.primaryPalette], ['secondary', scheme.secondaryPalette], ['tertiary', scheme.tertiaryPalette]].forEach(function (pair) {
            var role = pair[0];
            if (toneOf(values[role + '-container']) > 50) {
              values[role + '-container'] = tone(pair[1], 35);
              values['on-' + role + '-container'] = tone(pair[1], 90);
            }
          });
          values['on-secondary-container'] = tone(scheme.secondaryPalette, 85);
          values['on-error-container'] = tone(scheme.errorPalette, 80);
        }
      }
      return { values: values, scheme: scheme };
    }

    var light = make(false);
    var dark = make(true);
    dark.values['inverse-primary'] = light.values.primary;

    var seedPalette = m.TonalPalette.fromHct(seed);
    function brand(isDark) {
      return isDark ? hex(m.Hct.from(seed.hue, seed.chroma * 0.8, 64).toInt()) : tone(seedPalette, 40);
    }

    function block(part, isDark) {
      var out = {};
      ROLES.forEach(function (role) { out[role] = part.values[role]; });
      out.brand = brand(isDark);
      out.shadow = tone(part.scheme.neutralPalette, isDark ? 2 : 6);
      return out;
    }

    return JSON.stringify({ light: block(light, false), dark: block(dark, true) });
  }

  /** Anteprima di un colore d'accento (come i campioni di Android): primario, secondario e terziario. */
  function swatch(accent, style, dark) {
    var Scheme = m[schemeClass[style] || 'SchemeTonalSpot'];
    var scheme = new Scheme(m.Hct.fromInt(m.argbFromHex(accent)), dark, 0, '2025', 'phone');
    var hex = function (palette, t) { return m.hexFromArgb(palette.tone(t)); };
    return JSON.stringify(dark
      ? [hex(scheme.primaryPalette, 80), hex(scheme.secondaryPalette, 70), hex(scheme.tertiaryPalette, 75)]
      : [hex(scheme.primaryPalette, 45), hex(scheme.secondaryPalette, 80), hex(scheme.tertiaryPalette, 70)]);
  }

  return { build: build, swatch: swatch };
})();
