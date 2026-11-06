import { workspaceTokens } from '../../../../theme/workspaceBranding';

// Only dynamic token values live here; component styling stays in Tailwind.
export function applyWorkspaceTokens(color, selector = ':root:root') {
  const id =
    selector === ':root:root' ? 'workspace-theme' : 'workspace-preview-theme';
  let element = document.getElementById(id);
  if (!element) {
    element = document.createElement('style');
    element.id = id;
    document.head.appendChild(element);
  }
  const sheet = element.sheet;
  while (sheet.cssRules.length) sheet.deleteRule(0);
  [false, true].forEach(dark => {
    const darkScope =
      selector === ':root:root'
        ? ':root:root.dark, body.dark'
        : `${selector}.dark, .dark ${selector}`;
    const scope = dark ? darkScope : selector;
    const index = sheet.insertRule(`${scope} {}`);
    Object.entries(workspaceTokens(color, dark)).forEach(([key, value]) => {
      sheet.cssRules[index].style.setProperty(key, value);
    });
  });
}
