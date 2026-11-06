// Ni.CO foundations from GENESIS, expressed as Chatwoot design tokens.
export const defaultBranding = {
  name: 'Ni.CO',
  color: '#E30613',
  website_url: 'https://nicodelatam.com',
  logo_url: '/branding/nico-mark.svg',
};

const rgb = hex => hex.match(/[a-f\d]{2}/gi).map(value => parseInt(value, 16));
const mix = (a, b, weight) =>
  a.map((value, index) => Math.round(value + (b[index] - value) * weight));
const luminance = values =>
  values.reduce((sum, value, index) => {
    const channel = value / 255;
    return (
      sum +
      (channel <= 0.04045
        ? channel / 12.92
        : ((channel + 0.055) / 1.055) ** 2.4) *
        [0.2126, 0.7152, 0.0722][index]
    );
  }, 0);

export function workspaceTokens(color = defaultBranding.color, dark = false) {
  const brand = rgb(
    /^#[a-f\d]{6}$/i.test(color) ? color : defaultBranding.color
  );
  // Keep white button labels readable, including for very light workspace colors.
  let primary = brand;
  while (1.05 / (luminance(primary) + 0.05) < 4.5)
    primary = mix(primary, [0, 0, 0], 0.06);
  const canvas = rgb(dark ? '#191919' : '#FAF8F6');
  const card = rgb(dark ? '#222222' : '#FFFFFF');
  const muted = rgb(dark ? '#2C2C2C' : '#F2EFEC');
  const border = rgb(dark ? '#3D3D3D' : '#E3DDDA');
  const text = rgb(dark ? '#F5F5F5' : '#241F1E');
  const secondary = rgb(dark ? '#B6B6B6' : '#6F6561');
  const variables = {
    '--workspace-brand': primary,
    '--background-color': canvas,
    '--surface-1': card,
    '--surface-2': card,
    '--surface-active': muted,
    '--solid-1': card,
    '--solid-2': card,
    '--solid-3': muted,
    '--solid-active': muted,
    '--card-color': card,
    '--button-color': card,
    '--border-container': border,
    '--border-weak': border,
    '--border-strong': border,
    '--label-background': muted,
  };
  const slate = [
    canvas,
    card,
    muted,
    mix(muted, border, 0.4),
    border,
    border,
    border,
    rgb(dark ? '#858585' : '#8E8581'),
    secondary,
    secondary,
    secondary,
    text,
  ];
  const blue = [0.015, 0.035, 0.075, 0.12, 0.19, 0.27, 0.36, 0.48].map(weight =>
    mix(canvas, brand, weight)
  );
  blue.push(
    primary,
    mix(primary, [0, 0, 0], 0.12),
    dark ? mix(brand, [255, 255, 255], 0.65) : primary,
    dark ? mix(brand, [255, 255, 255], 0.78) : mix(primary, [0, 0, 0], 0.3)
  );
  slate.forEach((value, i) => {
    variables[`--slate-${i + 1}`] = value;
  });
  blue.forEach((value, i) => {
    variables[`--blue-${i + 1}`] = value;
  });
  variables['--solid-blue'] = blue[3];
  variables['--solid-blue-2'] = blue[1];
  return Object.fromEntries(
    Object.entries(variables).map(([key, value]) => [key, value.join(' ')])
  );
}
