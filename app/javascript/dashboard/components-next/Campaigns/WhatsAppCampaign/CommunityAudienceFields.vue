<script setup>
import { computed, ref, watch, onActivated, onDeactivated } from 'vue';
import { watchDebounced } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import AudienceAPI from 'dashboard/api/communityCampaignAudience';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inboxId: { type: Number, required: true },
  campaignId: { type: [Number, String], default: null },
  labelIds: { type: Array, default: () => [] },
  scheduledAt: { type: String, default: '' },
});
const mode = defineModel('mode', { type: String, default: 'labels' });
const sourceId = defineModel('sourceId', {
  type: [Number, String],
  default: '',
});
const errorCodes = defineModel('errorCodes', {
  type: Array,
  default: () => [],
});
const { t } = useI18n();
const route = useRoute();
const { run, abort, isPending } = useAbortableRequest();
const data = ref(null);
const error = ref('');
const currentKey = ref('');
let requestedKey = '';
let active = true;
const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
const selectionKey = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.inboxId,
    props.campaignId,
    props.labelIds,
    props.scheduledAt,
    mode.value,
    sourceId.value,
    errorCodes.value,
  ])
);
const valid = computed(
  () =>
    !isPending.value &&
    !error.value &&
    currentKey.value === selectionKey.value &&
    data.value?.total > 0 &&
    (mode.value !== 'failed' || !!sourceId.value)
);
const modeOptions = computed(() => [
  { value: 'labels', label: t('COMMUNITY_AUDIENCE.BY_LABELS') },
  { value: 'failed', label: t('COMMUNITY_AUDIENCE.BY_FAILURES') },
]);
const campaignOptions = computed(() =>
  (data.value?.campaigns || []).map(item => ({
    value: item.id,
    label: item.title,
  }))
);
const errorOptions = computed(() =>
  (data.value?.errors || [])
    .filter(item => item.code)
    .map(item => ({
      value: item.code,
      label: t('COMMUNITY_AUDIENCE.ERROR_OPTION', item),
    }))
);
const refresh = async scheduledAt => {
  error.value = '';
  const key = selectionKey.value;
  requestedKey = key;
  const needsSource = mode.value === 'failed' && !sourceId.value;
  const selection = {
    mode: needsSource ? 'labels' : mode.value,
    label_ids: mode.value === 'labels' ? props.labelIds : [],
  };
  if (mode.value === 'failed' && sourceId.value) {
    selection.source_campaign_id = Number(sourceId.value);
    selection.error_codes = errorCodes.value;
  }
  try {
    const response = await run(signal =>
      AudienceAPI.preview(
        Number(route.params.accountId),
        {
          inbox_id: props.inboxId,
          exclude_campaign_id: props.campaignId
            ? Number(props.campaignId)
            : undefined,
          audience: selection,
          timezone,
          scheduled_at:
            scheduledAt ||
            (props.scheduledAt
              ? new Date(props.scheduledAt).toISOString()
              : undefined),
        },
        signal
      )
    );
    if (!response || key !== selectionKey.value) return null;
    data.value = response.data;
    if (needsSource) data.value.total = 0;
    currentKey.value = key;
    return data.value;
  } catch (exception) {
    error.value =
      exception.response?.data?.error || t('COMMUNITY_AUDIENCE.LOAD_ERROR');
    return null;
  }
};
watch(selectionKey, abort, { flush: 'sync' });
watchDebounced(
  selectionKey,
  () => {
    if (active && !(isPending.value && requestedKey === selectionKey.value))
      refresh();
  },
  {
    immediate: true,
    debounce: 250,
  }
);
watch(sourceId, () => {
  errorCodes.value = [];
});
onActivated(() => {
  active = true;
  refresh();
});
onDeactivated(() => {
  active = false;
  abort();
});
defineExpose({ valid, refresh, data });
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-col gap-1">
      <label
        for="community-audience-mode"
        class="mb-0 text-heading-3 text-n-slate-12"
      >
        {{ t('COMMUNITY_AUDIENCE.TYPE') }}
      </label>
      <ComboBox
        id="community-audience-mode"
        v-model="mode"
        :options="modeOptions"
      />
    </div>
    <template v-if="mode === 'failed'">
      <p class="m-0 text-sm text-n-slate-11">
        {{ t('COMMUNITY_AUDIENCE.FAILURES_HELP') }}
      </p>
      <div class="flex flex-col gap-1">
        <label
          for="community-audience-source"
          class="mb-0 text-heading-3 text-n-slate-12"
        >
          {{ t('COMMUNITY_AUDIENCE.SOURCE') }}
        </label>
        <ComboBox
          id="community-audience-source"
          v-model="sourceId"
          :options="campaignOptions"
          :placeholder="t('COMMUNITY_AUDIENCE.SOURCE_PLACEHOLDER')"
          :empty-state="t('COMMUNITY_AUDIENCE.NO_SOURCES')"
        />
      </div>
      <div v-if="sourceId" class="flex flex-col gap-1">
        <label
          for="community-audience-errors"
          class="mb-0 text-heading-3 text-n-slate-12"
        >
          {{ t('COMMUNITY_AUDIENCE.ERRORS') }}
        </label>
        <TagMultiSelectComboBox
          id="community-audience-errors"
          v-model="errorCodes"
          :options="errorOptions"
          :placeholder="t('COMMUNITY_AUDIENCE.ALL_ERRORS')"
        />
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('COMMUNITY_AUDIENCE.ERRORS_HELP') }}
        </p>
      </div>
    </template>
    <slot v-else />
    <div
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
    >
      <p class="mb-2">{{ error }}</p>
      <Button
        size="sm"
        variant="outline"
        color="slate"
        :label="t('COMMUNITY_AUDIENCE.REFRESH')"
        @click="refresh()"
      />
    </div>
    <p v-else class="mb-0 text-sm font-medium text-n-slate-12" role="status">
      {{
        isPending || currentKey !== selectionKey
          ? t('COMMUNITY_AUDIENCE.CHECKING')
          : t('COMMUNITY_AUDIENCE.TOTAL', { count: data?.total || 0 })
      }}
    </p>
    <div
      v-if="data?.sent_today.length || data?.scheduled.length"
      role="status"
      class="flex flex-col gap-2 rounded-lg border border-n-amber-6 bg-n-amber-2 p-4 text-sm text-n-slate-12"
    >
      <p class="m-0 font-medium">
        {{ t('COMMUNITY_AUDIENCE.ACTIVITY_TITLE') }}
      </p>
      <p v-if="data.sent_today.length" class="m-0">
        {{
          t('COMMUNITY_AUDIENCE.SENT_TODAY', {
            count: data.sent_today.length,
            timezone: data.timezone,
          })
        }}
      </p>
      <ul v-if="data.sent_today.length" class="m-0 ps-5">
        <li v-for="item in data.sent_today" :key="item.id">{{ item.title }}</li>
      </ul>
      <p v-if="data.overlap_today" class="m-0">
        {{ t('COMMUNITY_AUDIENCE.OVERLAP', { count: data.overlap_today }) }}
      </p>
      <p v-if="data.scheduled.length" class="m-0">
        {{
          t('COMMUNITY_AUDIENCE.SCHEDULED', {
            count: data.scheduled.length,
            day: data.scheduled_day,
          })
        }}
      </p>
      <ul v-if="data.scheduled.length" class="m-0 ps-5">
        <li v-for="item in data.scheduled" :key="item.id">{{ item.title }}</li>
      </ul>
      <p class="m-0 text-xs text-n-slate-11">
        {{ t('COMMUNITY_AUDIENCE.ACTIVITY_HELP') }}
      </p>
    </div>
  </div>
</template>
