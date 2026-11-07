<script setup>
import { computed, onActivated, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import { isWhatsAppComplete } from '@chatwoot/utils';
import { CAMPAIGN_TYPES } from 'shared/constants/campaign';
import { CAMPAIGNS_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { useAlert, useTrack } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import {
  COMPONENT_TYPES,
  buildTemplateParameters,
  normalizeTemplateParameters,
  DEFAULT_CATEGORY,
  DEFAULT_LANGUAGE,
  findComponentByType,
  getTemplateKey,
  isValidTemplateMediaUrl,
  renderTemplatePreview,
} from 'dashboard/helper/templateHelper';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import InboxHealthAPI from 'dashboard/api/inboxHealth';
import { useConfig } from 'dashboard/composables/useConfig';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CommunityAudienceFields from 'dashboard/components-next/Campaigns/WhatsAppCampaign/CommunityAudienceFields.vue';

import Breadcrumb from 'dashboard/components-next/breadcrumb/Breadcrumb.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SectionCard from 'dashboard/components-next/Campaigns/WhatsAppCampaign/SectionCard.vue';
import BasicSettingsFields from 'dashboard/components-next/Campaigns/WhatsAppCampaign/BasicSettingsFields.vue';
import AudienceFields from 'dashboard/components-next/Campaigns/WhatsAppCampaign/AudienceFields.vue';
import TemplateFields from 'dashboard/components-next/Campaigns/WhatsAppCampaign/TemplateFields.vue';
import AccountInformationCard from 'dashboard/components-next/Campaigns/WhatsAppCampaign/AccountInformationCard.vue';
import MessagePreviewCard from 'dashboard/components-next/Campaigns/WhatsAppCampaign/MessagePreviewCard.vue';
import SchedulePopover from 'dashboard/components-next/Campaigns/WhatsAppCampaign/SchedulePopover.vue';

const SECTION_FIELDS = {
  basic: ['title', 'inboxId'],
  audience: [
    'audienceIds',
    'audienceMode',
    'retryCampaignId',
    'retryErrorCodes',
  ],
  template: ['templateId', 'processedParams'],
};

const { t, te, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { isEnterprise } = useConfig();
const audienceRef = ref(null);
const activityDialog = ref(null);
const activityCheck = ref(null);
const pendingScheduleAction = ref(null);
const isCheckingAudience = ref(false);

const campaigns = useMapGetter('campaigns/getWhatsAppCampaigns');
const labels = useMapGetter('labels/getLabels');
const whatsAppInboxes = useMapGetter('inboxes/getWhatsAppInboxes');
const whatsAppTemplates = useMapGetter('inboxes/getFilteredWhatsAppTemplates');
const uiFlags = useMapGetter('campaigns/getUIFlags');

const buildState = () => ({
  title: '',
  inboxId: null,
  templateId: null,
  processedParams: {},
  audienceIds: [],
  audienceMode: 'labels',
  retryCampaignId: '',
  retryErrorCodes: [],
  scheduledAt: '',
});

const snapshot = value => JSON.parse(JSON.stringify(value));

const state = reactive(buildState());
const savedState = ref(buildState());
const hydratedId = ref(null);
const healthData = ref(null);

const campaignId = computed(() => route.params.campaignId);
const isEditMode = computed(() => Boolean(campaignId.value));
const communityAudienceEnabled = computed(
  () =>
    !isEnterprise &&
    whatsAppInboxes.value.find(item => item.id === state.inboxId)?.provider ===
      'whatsapp_cloud'
);
const isAudienceComplete = computed(() =>
  communityAudienceEnabled.value
    ? audienceRef.value?.valid
    : state.audienceIds.length > 0
);

const campaign = computed(() =>
  campaigns.value.find(record => String(record.id) === String(campaignId.value))
);

const templatesFor = inboxId => whatsAppTemplates.value(inboxId);

const templates = computed(() => templatesFor(state.inboxId));

const selectedTemplate = computed(
  () =>
    templates.value.find(item => getTemplateKey(item) === state.templateId) ??
    null
);

const toDateTimeInput = seconds => {
  const date = new Date(seconds * 1000);
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
};

const applyCampaign = record => {
  const {
    name,
    language,
    processed_params: params,
  } = record.template_params ?? {};
  const template = templatesFor(record.inbox.id).find(
    item => item.name === name && item.language === language
  );

  Object.assign(state, {
    title: record.title,
    inboxId: record.inbox.id,
    templateId: template ? getTemplateKey(template) : null,
    processedParams: snapshot({
      ...(template ? buildTemplateParameters(template) : {}),
      ...normalizeTemplateParameters(params ?? {}),
    }),
    audienceIds: (record.audience ?? [])
      .filter(item => item.type === 'Label')
      .map(item => item.id),
    audienceMode: record.trigger_rules?.community_audience?.mode || 'labels',
    retryCampaignId:
      record.trigger_rules?.community_audience?.source_campaign_id || '',
    retryErrorCodes:
      record.trigger_rules?.community_audience?.error_codes || [],
    scheduledAt: toDateTimeInput(record.scheduled_at),
  });
  savedState.value = snapshot(state);
};

const resetForm = () => {
  Object.assign(state, buildState());
  savedState.value = buildState();
  hydratedId.value = null;
};

// Campaign and inbox records land at different times, so hydrate once both are
// available and never again for the same campaign, to avoid clobbering edits.
watch(
  [
    () => route.name,
    campaignId,
    campaign,
    () => whatsAppInboxes.value.length,
    () => uiFlags.value.hasFetched,
    () => uiFlags.value.isFetching,
  ],
  () => {
    if (
      !['campaigns_whatsapp_new', 'campaigns_whatsapp_edit'].includes(
        route.name
      )
    )
      return;
    const record = campaign.value;
    if (!record) {
      if (hydratedId.value !== null) resetForm();
      if (
        isEditMode.value &&
        uiFlags.value.hasFetched &&
        !uiFlags.value.isFetching
      ) {
        router.replace({ name: 'campaigns_whatsapp_index' });
      }
      return;
    }
    if (['processing', 'completed'].includes(record.campaign_status)) {
      router.replace({ name: 'campaigns_whatsapp_index' });
      return;
    }
    if (!whatsAppInboxes.value.length || hydratedId.value === record.id) return;
    hydratedId.value = record.id;
    applyCampaign(record);
  },
  { immediate: true }
);

const { run: runHealthRequest, abort: abortHealthRequest } =
  useAbortableRequest();

watch(
  () => state.inboxId,
  async inboxId => {
    if (!isEditMode.value) {
      state.templateId = null;
      state.processedParams = {};
      state.retryCampaignId = '';
      state.retryErrorCodes = [];
    }
    abortHealthRequest();
    healthData.value = null;
    if (!inboxId) return;
    try {
      await runHealthRequest(async signal => {
        const { data } = await InboxHealthAPI.getHealthStatus(inboxId, {
          signal,
        });
        if (!signal.aborted) healthData.value = data;
      });
    } catch {
      healthData.value = null;
    }
  },
  { immediate: true }
);

const messagingTier = computed(() => {
  const tier = healthData.value?.messaging_limit_tier;
  const key = `INBOX_MGMT.ACCOUNT_HEALTH.VALUES.TIERS.${tier}`;
  return tier !== 'UNKNOWN' && te(key) ? t(key) : '';
});

const breadcrumbItems = computed(() => [
  {
    label: t('CAMPAIGN.WHATSAPP.HEADER_TITLE'),
    routeName: 'campaigns_whatsapp_index',
  },
  {
    label: isEditMode.value
      ? campaign.value?.title
      : t('CAMPAIGN.WHATSAPP.FORM.CREATE_TITLE'),
  },
]);

const isTemplateComplete = computed(
  () =>
    !!selectedTemplate.value &&
    isWhatsAppComplete(selectedTemplate.value, state.processedParams) &&
    (state.processedParams.buttons ?? []).every(
      button => !button || !!button.parameter
    ) &&
    isValidTemplateMediaUrl(state.processedParams.header?.media_url)
);

const isValid = computed(
  () =>
    !!state.title &&
    !!state.inboxId &&
    isAudienceComplete.value &&
    isTemplateComplete.value
);

const isSectionDirty = section =>
  SECTION_FIELDS[section].some(
    field =>
      JSON.stringify(state[field]) !== JSON.stringify(savedState.value[field])
  );

const commitSection = (section, submitted) => {
  const saved = snapshot(savedState.value);
  SECTION_FIELDS[section].forEach(field => {
    saved[field] = submitted[field];
  });
  savedState.value = saved;
};

const audiencePayload = computed(() =>
  state.audienceMode === 'failed' && communityAudienceEnabled.value
    ? []
    : state.audienceIds.map(id => ({ id, type: 'Label' }))
);
const audienceRulesPayload = computed(() =>
  communityAudienceEnabled.value
    ? {
        trigger_rules: {
          ...campaign.value?.trigger_rules,
          community_audience:
            state.audienceMode === 'failed'
              ? {
                  mode: 'failed',
                  source_campaign_id: Number(state.retryCampaignId),
                  error_codes: state.retryErrorCodes,
                }
              : { mode: 'labels' },
        },
      }
    : {}
);

const templatePayload = computed(() => {
  const template = selectedTemplate.value;
  const bodyText =
    findComponentByType(template, COMPONENT_TYPES.BODY)?.text ?? '';

  return {
    message: renderTemplatePreview(bodyText, state.processedParams.body ?? {}),
    template_params: {
      name: template.name,
      namespace: template.namespace ?? '',
      category: template.category ?? DEFAULT_CATEGORY,
      language: template.language ?? DEFAULT_LANGUAGE,
      processed_params: state.processedParams,
    },
  };
});

const sectionPayloads = {
  basic: () => ({ title: state.title, inbox_id: state.inboxId }),
  audience: () => ({
    audience: audiencePayload.value,
    ...audienceRulesPayload.value,
  }),
  template: () => templatePayload.value,
};

const scheduleButtonLabel = computed(() => {
  if (!isEditMode.value || !state.scheduledAt)
    return t('CAMPAIGN.WHATSAPP.FORM.SCHEDULE');

  const date = new Intl.DateTimeFormat(locale.value, {
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
  })
    .formatToParts(new Date(state.scheduledAt))
    .filter(part => part.type !== 'literal')
    .map(part => part.value)
    .join(' / ');

  return t('CAMPAIGN.WHATSAPP.FORM.SCHEDULED_FOR', { date });
});

const isScheduleDirty = computed(
  () => state.scheduledAt !== savedState.value.scheduledAt
);

const isScheduleInPast = computed(
  () => state.scheduledAt < toDateTimeInput(Date.now() / 1000)
);

onActivated(() => {
  if (!isEditMode.value) resetForm();
});

const handleBreadcrumbClick = ({ routeName }) =>
  router.push({ name: routeName });

const handleDiscard = section => {
  SECTION_FIELDS[section].forEach(field => {
    state[field] = snapshot(savedState.value[field]);
  });
};

const handleUpdate = async payload => {
  try {
    await store.dispatch('campaigns/update', {
      id: campaign.value.id,
      ...payload,
    });
    useAlert(t('CAMPAIGN.WHATSAPP.FORM.API.UPDATE_SUCCESS'));
    return true;
  } catch {
    useAlert(t('CAMPAIGN.WHATSAPP.FORM.API.UPDATE_ERROR'));
    return false;
  }
};

// A campaign that does not exist yet has nothing to persist, so saving a
// section only confirms its values until the campaign is scheduled.
const handleSectionSave = async section => {
  const submitted = snapshot(state);
  const payload = snapshot(sectionPayloads[section]());
  if (isEditMode.value && !(await handleUpdate(payload))) return;
  commitSection(section, submitted);
};

const handleCreate = async scheduledAt => {
  try {
    await store.dispatch('campaigns/create', {
      title: state.title,
      inbox_id: state.inboxId,
      audience: audiencePayload.value,
      ...audienceRulesPayload.value,
      scheduled_at: scheduledAt,
      ...templatePayload.value,
    });
    useTrack(CAMPAIGNS_EVENTS.CREATE_CAMPAIGN, {
      type: CAMPAIGN_TYPES.ONE_OFF,
    });
    useAlert(t('CAMPAIGN.WHATSAPP.FORM.API.CREATE_SUCCESS'));
    resetForm();
    router.push({ name: 'campaigns_whatsapp_index' });
  } catch {
    useAlert(t('CAMPAIGN.WHATSAPP.FORM.API.CREATE_ERROR'));
  }
};

const checkSchedule = async action => {
  if (!communityAudienceEnabled.value) {
    await action();
    return;
  }
  if (isCheckingAudience.value) return;
  isCheckingAudience.value = true;
  try {
    const data = await audienceRef.value.refresh(
      new Date(state.scheduledAt).toISOString()
    );
    if (!data) return;
    if (!data.total) {
      useAlert(t('COMMUNITY_AUDIENCE.EMPTY'));
      return;
    }
    const sameDay = data.scheduled_day === data.today;
    if (
      (sameDay && (data.sent_today.length || data.overlap_today)) ||
      data.scheduled.length
    ) {
      activityCheck.value = data;
      pendingScheduleAction.value = action;
      activityDialog.value.open();
      return;
    }
    await action();
  } finally {
    isCheckingAudience.value = false;
  }
};
const confirmSchedule = async () => {
  const action = pendingScheduleAction.value;
  if (!action || isCheckingAudience.value) return;
  activityDialog.value.close();
  isCheckingAudience.value = true;
  try {
    await action();
  } finally {
    isCheckingAudience.value = false;
  }
};
const handleSchedule = () =>
  checkSchedule(() => handleCreate(new Date(state.scheduledAt).toISOString()));

const handleCancelReschedule = () => {
  state.scheduledAt = savedState.value.scheduledAt;
};

const persistReschedule = async () => {
  const scheduledAt = state.scheduledAt;
  if (await handleUpdate({ scheduled_at: new Date(scheduledAt).toISOString() }))
    savedState.value = { ...savedState.value, scheduledAt };
};
const handleReschedule = () => {
  if (communityAudienceEnabled.value && isSectionDirty('audience')) {
    useAlert(t('COMMUNITY_AUDIENCE.SAVE_BEFORE_RESCHEDULE'));
    return undefined;
  }
  return checkSchedule(persistReschedule);
};
</script>

<template>
  <div class="w-full h-full px-6 overflow-y-auto bg-n-surface-1">
    <header
      class="flex items-center justify-between w-full h-20 max-w-5xl gap-3 mx-auto"
    >
      <Breadcrumb :items="breadcrumbItems" @click="handleBreadcrumbClick" />
      <div class="flex items-center gap-2">
        <span v-tooltip.top="t('CAMPAIGN.WHATSAPP.FORM.LIVE_TEST_TOOLTIP')">
          <Button
            variant="faded"
            color="slate"
            size="sm"
            disabled
            :label="t('CAMPAIGN.WHATSAPP.FORM.LIVE_TEST')"
          />
        </span>
        <SchedulePopover
          v-model="state.scheduledAt"
          :button-label="scheduleButtonLabel"
          :confirm-label="t('CAMPAIGN.WHATSAPP.FORM.SCHEDULE_POPOVER.CREATE')"
          :variant="isEditMode ? 'outline' : 'solid'"
          :color="isEditMode ? 'slate' : 'blue'"
          :show-actions="!isEditMode"
          :is-disabled="!isValid"
          :is-loading="uiFlags.isCreating || isCheckingAudience"
          @confirm="handleSchedule"
        />
        <template v-if="isEditMode">
          <Button
            variant="faded"
            color="slate"
            size="sm"
            :label="t('CAMPAIGN.WHATSAPP.FORM.SCHEDULE_POPOVER.CANCEL')"
            :disabled="!isScheduleDirty"
            @click="handleCancelReschedule"
          />
          <Button
            size="sm"
            :label="t('CAMPAIGN.WHATSAPP.FORM.RESCHEDULE')"
            :is-loading="uiFlags.isUpdating || isCheckingAudience"
            :disabled="
              !isScheduleDirty ||
              isScheduleInPast ||
              uiFlags.isUpdating ||
              isCheckingAudience ||
              !isAudienceComplete ||
              (communityAudienceEnabled && isSectionDirty('audience'))
            "
            @click="handleReschedule"
          />
        </template>
      </div>
    </header>

    <div
      class="grid items-start w-full max-w-5xl grid-cols-1 gap-6 pb-6 mx-auto lg:grid-cols-[minmax(0,1.25fr)_minmax(0,1fr)]"
    >
      <div class="flex flex-col gap-6">
        <SectionCard
          :title="t('CAMPAIGN.WHATSAPP.FORM.BASIC_SETTINGS.TITLE')"
          :is-dirty="isSectionDirty('basic')"
          :is-saving="uiFlags.isUpdating"
          :is-save-disabled="!state.title || !state.inboxId"
          @discard="handleDiscard('basic')"
          @save="handleSectionSave('basic')"
        >
          <BasicSettingsFields
            v-model:title="state.title"
            v-model:inbox-id="state.inboxId"
            :inboxes="whatsAppInboxes"
            :is-inbox-disabled="isEditMode"
          />
        </SectionCard>

        <SectionCard
          :title="t('CAMPAIGN.WHATSAPP.FORM.AUDIENCE.TITLE')"
          :is-dirty="isSectionDirty('audience')"
          :is-saving="uiFlags.isUpdating"
          :is-save-disabled="!isAudienceComplete"
          @discard="handleDiscard('audience')"
          @save="handleSectionSave('audience')"
        >
          <CommunityAudienceFields
            v-if="communityAudienceEnabled"
            ref="audienceRef"
            v-model:mode="state.audienceMode"
            v-model:source-id="state.retryCampaignId"
            v-model:error-codes="state.retryErrorCodes"
            :inbox-id="state.inboxId"
            :campaign-id="campaignId"
            :label-ids="state.audienceIds"
            :scheduled-at="state.scheduledAt"
          >
            <AudienceFields
              v-model="state.audienceIds"
              :labels="labels"
              :messaging-tier="messagingTier"
            />
          </CommunityAudienceFields>
          <AudienceFields
            v-else
            v-model="state.audienceIds"
            :labels="labels"
            :messaging-tier="messagingTier"
          />
          <p
            v-if="
              isEditMode &&
              communityAudienceEnabled &&
              isSectionDirty('audience')
            "
            class="m-0 text-sm text-n-amber-11"
            role="status"
          >
            {{ t('COMMUNITY_AUDIENCE.SAVE_BEFORE_RESCHEDULE') }}
          </p>
        </SectionCard>

        <SectionCard
          :title="t('CAMPAIGN.WHATSAPP.FORM.TEMPLATE.TITLE')"
          :is-dirty="isSectionDirty('template')"
          :is-saving="uiFlags.isUpdating"
          :is-save-disabled="!isTemplateComplete"
          @discard="handleDiscard('template')"
          @save="handleSectionSave('template')"
        >
          <TemplateFields
            v-model:template-id="state.templateId"
            v-model:processed-params="state.processedParams"
            :templates="templates"
            :has-inbox="!!state.inboxId"
          />
        </SectionCard>
      </div>

      <div class="flex flex-col gap-6">
        <AccountInformationCard :health-data="healthData" />
        <MessagePreviewCard
          :template="selectedTemplate"
          :processed-params="state.processedParams"
        />
      </div>
    </div>
    <Dialog
      ref="activityDialog"
      type="alert"
      :title="t('COMMUNITY_AUDIENCE.CONFIRM_TITLE')"
      :description="t('COMMUNITY_AUDIENCE.CONFIRM_HELP')"
      :confirm-button-label="t('COMMUNITY_AUDIENCE.CONFIRM')"
      :cancel-button-label="t('COMMUNITY_AUDIENCE.CANCEL')"
      :is-loading="isCheckingAudience"
      @confirm="confirmSchedule"
      @close="pendingScheduleAction = null"
    >
      <div
        v-if="activityCheck"
        class="flex flex-col gap-3 text-sm text-n-slate-12"
      >
        <p
          v-if="
            activityCheck.scheduled_day === activityCheck.today &&
            activityCheck.sent_today.length
          "
          class="m-0"
        >
          {{
            t('COMMUNITY_AUDIENCE.SENT_TODAY', {
              count: activityCheck.sent_today.length,
              timezone: activityCheck.timezone,
            })
          }}
        </p>
        <ul
          v-if="
            activityCheck.scheduled_day === activityCheck.today &&
            activityCheck.sent_today.length
          "
          class="m-0 ps-5"
        >
          <li v-for="item in activityCheck.sent_today" :key="item.id">
            {{ item.title }}
          </li>
        </ul>
        <p
          v-if="
            activityCheck.scheduled_day === activityCheck.today &&
            activityCheck.overlap_today
          "
          class="m-0"
        >
          {{
            t('COMMUNITY_AUDIENCE.OVERLAP', {
              count: activityCheck.overlap_today,
            })
          }}
        </p>
        <p v-if="activityCheck.scheduled.length" class="m-0">
          {{
            t('COMMUNITY_AUDIENCE.SCHEDULED', {
              count: activityCheck.scheduled.length,
              day: activityCheck.scheduled_day,
            })
          }}
        </p>
        <ul v-if="activityCheck.scheduled.length" class="m-0 ps-5">
          <li v-for="item in activityCheck.scheduled" :key="item.id">
            {{ item.title }}
          </li>
        </ul>
      </div>
    </Dialog>
  </div>
</template>
