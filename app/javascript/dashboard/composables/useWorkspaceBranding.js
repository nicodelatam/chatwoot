import { watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { applyWorkspaceTokens } from 'shared/helpers/workspaceBranding';

export function useWorkspaceBranding() {
  const config = useMapGetter('globalConfig/get');
  watch(
    config,
    value => {
      applyWorkspaceTokens(value.workspaceBranding?.color);
      document.title = value.installationName;
      const favicon = document.getElementById('workspace-favicon');
      if (favicon) favicon.href = value.logoThumbnail;
      const themeColor = document.querySelector('meta[name="theme-color"]');
      if (themeColor) themeColor.content = value.workspaceBranding?.color;
    },
    { immediate: true }
  );
}
