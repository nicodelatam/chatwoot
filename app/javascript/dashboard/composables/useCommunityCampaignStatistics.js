import {
  computed,
  reactive,
  ref,
  watch,
  onMounted,
  onUnmounted,
  onActivated,
  onDeactivated,
} from 'vue';
import { watchDebounced } from '@vueuse/core';
import { format, subDays } from 'date-fns';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import StatisticsAPI from 'dashboard/api/communityCampaignStatistics';

export function useCommunityCampaignStatistics() {
  const route = useRoute();
  const router = useRouter();
  const { accountId } = useAccount();
  const { run, abort, isPending } = useAbortableRequest();
  const data = ref(null);
  const error = ref('');
  const autoRefresh = ref(true);
  let active = false;
  let syncingRoute = false;
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const filters = reactive({
    from: route.query.from || format(subDays(new Date(), 29), 'yyyy-MM-dd'),
    to: route.query.to || format(new Date(), 'yyyy-MM-dd'),
    campaignId: Number(route.params.campaignId || route.query.campaign) || '',
    labelIds: [].concat(route.query.labels || []).map(Number),
    status: route.query.status || 'all',
    query: route.query.q || '',
    page: Number(route.query.page) || 1,
  });
  const filterKey = computed(() =>
    JSON.stringify([
      accountId.value,
      filters.from,
      filters.to,
      filters.campaignId,
      filters.labelIds,
      filters.status,
      filters.query,
    ])
  );
  const load = async () => {
    if (!accountId.value) return;
    error.value = '';
    try {
      await run(async signal => {
        const response = await StatisticsAPI.get(
          accountId.value,
          {
            from: filters.from,
            to: filters.to,
            timezone,
            campaign_id: filters.campaignId || undefined,
            label_ids: filters.labelIds,
            status: filters.status,
            query: filters.query,
            page: filters.page,
          },
          signal
        );
        if (!signal.aborted) data.value = response.data;
      });
    } catch (exception) {
      error.value = exception.response?.data?.error || 'load_error';
    }
  };
  const updateURL = () => {
    router.replace({
      name: 'campaigns_whatsapp_statistics',
      params: { accountId: accountId.value },
      query: {
        from: filters.from,
        to: filters.to,
        campaign: filters.campaignId || undefined,
        labels: filters.labelIds.map(String),
        status: filters.status === 'all' ? undefined : filters.status,
        q: filters.query || undefined,
        page: filters.page > 1 ? filters.page : undefined,
      },
    });
  };
  watch(accountId, () => {
    data.value = null;
    filters.campaignId = '';
    filters.labelIds = [];
  });
  watch(
    filterKey,
    () => {
      if (syncingRoute) return;
      abort();
      filters.page = 1;
    },
    { flush: 'sync' }
  );
  watchDebounced(
    () => [filterKey.value, filters.page],
    () => {
      if (!active) return;
      updateURL();
      load();
    },
    { debounce: 250, maxWait: 1000 }
  );
  let timer;
  const activate = () => {
    if (active) return;
    active = true;
    syncingRoute = true;
    filters.from =
      route.query.from || format(subDays(new Date(), 29), 'yyyy-MM-dd');
    filters.to = route.query.to || format(new Date(), 'yyyy-MM-dd');
    filters.campaignId =
      Number(route.params.campaignId || route.query.campaign) || '';
    filters.labelIds = [].concat(route.query.labels || []).map(Number);
    filters.status = route.query.status || 'all';
    filters.query = route.query.q || '';
    filters.page = Number(route.query.page) || 1;
    syncingRoute = false;
    load();
    timer = window.setInterval(() => {
      if (autoRefresh.value && !document.hidden && !isPending.value) load();
    }, 30000);
  };
  const deactivate = () => {
    active = false;
    window.clearInterval(timer);
    abort();
  };
  onMounted(activate);
  onActivated(activate);
  onDeactivated(deactivate);
  onUnmounted(deactivate);
  return { data, filters, error, autoRefresh, timezone, isPending, load };
}
