<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { format, subDays } from 'date-fns';
import { useCommunityCampaignStatistics } from 'dashboard/composables/useCommunityCampaignStatistics';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import DatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import CommunityCampaignCharts from 'dashboard/components-next/Campaigns/CommunityCampaignCharts.vue';
import { campaignStatisticsLabels } from 'dashboard/helper/communityCampaignStatistics';

const { t } = useI18n();
const router = useRouter();
const labels = computed(() => campaignStatisticsLabels(t));
const { data, filters, error, autoRefresh, timezone, isPending, load } =
  useCommunityCampaignStatistics();
const rangeType = ref('last30days');
const dates = computed(() => [
  new Date(`${filters.from}T00:00:00`),
  new Date(`${filters.to}T00:00:00`),
]);
const campaignOptions = computed(() =>
  (data.value?.options.campaigns || []).map(item => ({
    value: item.id,
    label: item.title,
  }))
);
const labelOptions = computed(() =>
  (data.value?.options.labels || []).map(item => ({
    value: item.id,
    label: item.title,
  }))
);
const statusOptions = computed(() => [
  { value: 'all', label: t('COMMUNITY_CAMPAIGNS.ALL_STATUSES') },
  ...[
    'pending',
    'sent',
    'delivered',
    'read',
    'failed',
    'unconfirmed',
    'awaiting',
    'accepted',
    'delivered_all',
    'replied',
  ].map(value => ({
    value,
    label: labels.value.statuses[value],
  })),
]);
const cards = computed(() =>
  labels.value.metrics.map(metric => ({
    ...metric,
    value: data.value?.summary[metric.key] || 0,
  }))
);
const number = value => Number(value || 0).toLocaleString('es-CO');
const rate = (numerator, denominator) =>
  denominator
    ? `${((numerator / denominator) * 100).toLocaleString('es-CO', { maximumFractionDigits: 1 })}%`
    : t('COMMUNITY_CAMPAIGNS.NO_RATE');
const time = value =>
  value
    ? new Intl.DateTimeFormat('es-CO', {
        dateStyle: 'medium',
        timeStyle: 'short',
        timeZone: timezone,
      }).format(new Date(value))
    : '—';
const duration = campaign => {
  if (!campaign.started_at) return t('COMMUNITY_CAMPAIGNS.NOT_STARTED');
  if (!campaign.completed_at) return t('COMMUNITY_CAMPAIGNS.IN_PROGRESS');
  const seconds = Math.max(
    0,
    Math.round(
      (new Date(campaign.completed_at) - new Date(campaign.started_at)) / 1000
    )
  );
  return t('COMMUNITY_CAMPAIGNS.DURATION_VALUE', {
    minutes: Math.floor(seconds / 60),
    seconds: seconds % 60,
  });
};
const badgeClasses = {
  pending: 'bg-n-slate-3 text-n-slate-11',
  sent: 'bg-n-blue-9/10 text-n-blue-11',
  delivered: 'bg-n-teal-9/10 text-n-teal-11',
  read: 'bg-n-iris-9/10 text-n-iris-11',
  failed: 'bg-n-ruby-9/10 text-n-ruby-11',
  unconfirmed: 'bg-n-amber-9/10 text-n-amber-11',
};
const replyBadge = recipient =>
  ['button', 'quote'].includes(recipient.reply_source)
    ? t('COMMUNITY_CAMPAIGNS.RECIPIENT_REPLY_CONFIRMED')
    : t('COMMUNITY_CAMPAIGNS.RECIPIENT_REPLY_PROBABLE');
const changeDates = ([from, to, type]) => {
  filters.from = format(from, 'yyyy-MM-dd');
  filters.to = format(to, 'yyyy-MM-dd');
  rangeType.value = type;
};
const reset = () => {
  filters.from = format(subDays(new Date(), 29), 'yyyy-MM-dd');
  filters.to = format(new Date(), 'yyyy-MM-dd');
  filters.campaignId = '';
  filters.labelIds = [];
  filters.status = 'all';
  filters.query = '';
  rangeType.value = 'last30days';
};
</script>

<template>
  <section
    class="flex h-full w-full flex-col overflow-hidden bg-n-surface-1"
    :aria-busy="isPending"
  >
    <header
      class="z-20 flex shrink-0 flex-wrap items-center justify-between gap-4 border-b border-n-weak bg-n-surface-1 px-6 py-4"
    >
      <div class="min-w-0">
        <Button
          ghost
          slate
          xs
          icon="i-lucide-arrow-left"
          :label="t('COMMUNITY_CAMPAIGNS.BACK')"
          @click="router.push({ name: 'campaigns_whatsapp_index' })"
        />
        <h1 class="mb-0 mt-2 text-heading-1 text-n-slate-12">
          {{ t('COMMUNITY_CAMPAIGNS.TITLE') }}
        </h1>
        <p class="mb-0 mt-1 text-sm text-n-slate-11">
          {{ t('COMMUNITY_CAMPAIGNS.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex items-center gap-3">
        <Switch
          v-model="autoRefresh"
          :aria-label="t('COMMUNITY_CAMPAIGNS.AUTO_REFRESH')"
        />
        <span class="text-xs text-n-slate-11">
          {{ t('COMMUNITY_CAMPAIGNS.AUTO_REFRESH') }}
        </span>
        <Button
          sm
          slate
          outline
          icon="i-lucide-refresh-cw"
          :label="t('COMMUNITY_CAMPAIGNS.REFRESH')"
          :is-loading="isPending"
          :disabled="isPending"
          @click="load"
        />
      </div>
    </header>
    <main class="flex-1 overflow-y-auto px-4 py-5 md:px-6">
      <div class="mx-auto flex max-w-7xl flex-col gap-5">
        <section
          class="relative z-10 grid grid-cols-1 items-end gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-4 md:grid-cols-2 xl:grid-cols-4"
        >
          <div class="flex min-w-0 flex-col gap-2">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('COMMUNITY_CAMPAIGNS.DATE_RANGE') }}
            </label>
            <DatePicker
              v-model:range-type="rangeType"
              :date-range="dates"
              @date-range-changed="changeDates"
            />
          </div>
          <div class="flex min-w-0 flex-col gap-2">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('COMMUNITY_CAMPAIGNS.CAMPAIGN') }}
            </label>
            <ComboBox
              v-model="filters.campaignId"
              :options="campaignOptions"
              :placeholder="t('COMMUNITY_CAMPAIGNS.ALL_CAMPAIGNS')"
            />
          </div>
          <div
            class="flex min-w-0 flex-col gap-2"
            :title="t('COMMUNITY_CAMPAIGNS.LABELS_HINT')"
          >
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('COMMUNITY_CAMPAIGNS.LABELS') }}
            </label>
            <TagMultiSelectComboBox
              v-model="filters.labelIds"
              :options="labelOptions"
              :placeholder="t('COMMUNITY_CAMPAIGNS.ALL_LABELS')"
            />
          </div>
          <Button
            sm
            slate
            ghost
            icon="i-lucide-filter-x"
            :label="t('COMMUNITY_CAMPAIGNS.RESET')"
            @click="reset"
          />
        </section>
        <div
          class="flex flex-wrap items-center justify-between gap-2 text-xs text-n-slate-11"
          aria-live="polite"
        >
          <span>
            {{
              t('COMMUNITY_CAMPAIGNS.CONTEXT', {
                count: data?.summary.campaigns || 0,
                timezone,
              })
            }}
          </span>
          <span v-if="data">
            {{
              t('COMMUNITY_CAMPAIGNS.UPDATED', {
                time: time(data.generated_at),
              })
            }}
          </span>
        </div>
        <div
          v-if="error"
          role="alert"
          class="rounded-lg border border-n-ruby-6 bg-n-ruby-9/10 p-4 text-sm text-n-ruby-11"
        >
          {{
            error === 'load_error' ? t('COMMUNITY_CAMPAIGNS.LOAD_ERROR') : error
          }}
        </div>
        <div
          v-if="!data && isPending"
          class="flex items-center justify-center gap-3 py-16 text-n-slate-11"
        >
          <Spinner />
          {{ t('COMMUNITY_CAMPAIGNS.LOADING') }}
        </div>
        <template v-if="data">
          <div
            v-if="!data.summary.campaigns"
            class="rounded-xl border border-dashed border-n-weak py-16 text-center text-sm text-n-slate-11"
          >
            {{ t('COMMUNITY_CAMPAIGNS.EMPTY') }}
          </div>
          <template v-else>
            <div class="grid grid-cols-2 gap-3 lg:grid-cols-3 2xl:grid-cols-6">
              <button
                v-for="card in cards"
                :key="card.key"
                type="button"
                class="flex min-w-0 flex-col gap-3 rounded-xl border bg-n-solid-1 p-4 text-start transition-colors hover:border-n-brand"
                :class="
                  filters.status === card.status
                    ? 'border-n-brand'
                    : 'border-n-weak'
                "
                :title="card.hint"
                :aria-pressed="filters.status === card.status"
                @click="filters.status = card.status"
              >
                <span
                  class="flex items-center justify-between gap-2 text-sm text-n-slate-11"
                >
                  {{ card.label }}
                  <Icon icon="i-lucide-info" class="size-3 shrink-0" />
                </span>
                <strong
                  class="text-3xl font-semibold tabular-nums text-n-slate-12"
                >
                  {{ number(card.value) }}
                </strong>
              </button>
            </div>
            <div
              class="flex flex-wrap gap-6 rounded-xl border border-n-weak bg-n-solid-1 px-5 py-4"
            >
              <div :title="t('COMMUNITY_CAMPAIGNS.RATE_DELIVERY_HINT')">
                <span class="text-sm text-n-slate-11">
                  {{ t('COMMUNITY_CAMPAIGNS.DELIVERY_RATE') }}
                </span>
                <strong class="ms-3 text-xl tabular-nums text-n-teal-11">
                  {{ rate(data.summary.delivered, data.summary.sent) }}
                </strong>
              </div>
              <div :title="t('COMMUNITY_CAMPAIGNS.RATE_READ_HINT')">
                <span class="text-sm text-n-slate-11">
                  {{ t('COMMUNITY_CAMPAIGNS.READ_RATE') }}
                </span>
                <strong class="ms-3 text-xl tabular-nums text-n-iris-11">
                  {{ rate(data.summary.read, data.summary.delivered) }}
                </strong>
              </div>
              <button
                type="button"
                class="text-start"
                :title="t('COMMUNITY_CAMPAIGNS.RATE_REPLY_HINT')"
                @click="filters.status = 'replied'"
              >
                <span class="text-sm text-n-slate-11">
                  {{ t('COMMUNITY_CAMPAIGNS.REPLY_RATE') }}
                </span>
                <strong class="ms-3 text-xl tabular-nums text-n-blue-11">
                  {{ rate(data.summary.replied, data.summary.delivered) }}
                </strong>
                <span class="ms-2 text-xs text-n-slate-11">
                  {{
                    t('COMMUNITY_CAMPAIGNS.REPLY_DETAIL', {
                      replied: number(data.summary.replied),
                      confirmed: number(data.summary.replied_confirmed),
                    })
                  }}
                </span>
              </button>
            </div>
            <p
              v-if="data.summary.historical"
              class="m-0 rounded-lg bg-n-alpha-2 p-3 text-xs text-n-slate-11"
            >
              {{
                t('COMMUNITY_CAMPAIGNS.HISTORICAL', {
                  count: number(data.summary.historical),
                })
              }}
            </p>
            <p
              v-if="data.summary.untracked_campaigns"
              class="m-0 rounded-lg bg-n-amber-9/10 p-3 text-xs text-n-amber-11"
            >
              {{
                t('COMMUNITY_CAMPAIGNS.NO_TRACKING', {
                  count: data.summary.untracked_campaigns,
                })
              }}
            </p>
            <CommunityCampaignCharts
              :report="data"
              @status="filters.status = $event"
              @campaign="filters.campaignId = $event"
            />
            <section
              class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
            >
              <div class="max-h-80 overflow-auto">
                <table class="w-full text-start text-sm">
                  <thead
                    class="sticky top-0 bg-n-solid-2 text-xs text-n-slate-11"
                  >
                    <tr>
                      <th class="p-4 text-start">
                        {{ t('COMMUNITY_CAMPAIGNS.CAMPAIGN') }}
                      </th>
                      <th class="p-4 text-start">
                        {{ t('COMMUNITY_CAMPAIGNS.STATUS') }}
                      </th>
                      <th class="p-4 text-end">
                        {{ t('COMMUNITY_CAMPAIGNS.TOTAL') }}
                      </th>
                      <th class="p-4 text-end">
                        {{ t('COMMUNITY_CAMPAIGNS.DELIVERED') }}
                      </th>
                      <th class="p-4 text-end">
                        {{ t('COMMUNITY_CAMPAIGNS.READ') }}
                      </th>
                      <th class="p-4 text-end">
                        {{ t('COMMUNITY_CAMPAIGNS.FAILED') }}
                      </th>
                      <th
                        class="p-4 text-end"
                        :title="t('COMMUNITY_CAMPAIGNS.RATE_REPLY_HINT')"
                      >
                        {{ t('COMMUNITY_CAMPAIGNS.REPLIES') }}
                      </th>
                      <th
                        class="p-4 text-end"
                        :title="t('COMMUNITY_CAMPAIGNS.DURATION_HINT')"
                      >
                        {{ t('COMMUNITY_CAMPAIGNS.DURATION') }}
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-n-weak">
                    <tr
                      v-for="campaign in data.campaigns"
                      :key="campaign.id"
                      class="hover:bg-n-alpha-2"
                    >
                      <td class="p-4">
                        <button
                          type="button"
                          class="font-medium text-n-blue-11 hover:underline"
                          @click="filters.campaignId = campaign.id"
                        >
                          {{ campaign.title }}
                        </button>
                        <p class="mb-0 mt-1 text-xs text-n-slate-11">
                          {{
                            t('COMMUNITY_CAMPAIGNS.CAMPAIGN_CONTEXT', {
                              inbox: campaign.inbox_name,
                              date: time(campaign.scheduled_at),
                            })
                          }}
                        </p>
                        <div class="mt-2 flex flex-wrap gap-1">
                          <span
                            v-for="label in campaign.labels"
                            :key="label.id"
                            class="rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-11"
                          >
                            {{ label.title }}
                          </span>
                        </div>
                      </td>
                      <td class="p-4 text-n-slate-11">
                        {{ labels.campaignStatuses[campaign.status] }}
                      </td>
                      <td class="p-4 text-end tabular-nums">
                        {{ number(campaign.metrics.total) }}
                      </td>
                      <td class="p-4 text-end tabular-nums">
                        {{ number(campaign.metrics.delivered) }}
                      </td>
                      <td class="p-4 text-end tabular-nums">
                        {{ number(campaign.metrics.read) }}
                      </td>
                      <td class="p-4 text-end tabular-nums">
                        {{ number(campaign.metrics.failed) }}
                      </td>
                      <td
                        class="p-4 text-end tabular-nums"
                        :title="
                          t('COMMUNITY_CAMPAIGNS.REPLY_DETAIL', {
                            replied: number(campaign.metrics.replied),
                            confirmed: number(
                              campaign.metrics.replied_confirmed
                            ),
                          })
                        "
                      >
                        {{ number(campaign.metrics.replied) }}
                      </td>
                      <td
                        class="whitespace-nowrap p-4 text-end text-n-slate-11"
                      >
                        {{ duration(campaign) }}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>
            <section class="rounded-xl border border-n-weak bg-n-solid-1 p-5">
              <h2 class="mb-4 mt-0 text-base font-semibold text-n-slate-12">
                {{ t('COMMUNITY_CAMPAIGNS.ERRORS') }}
              </h2>
              <p v-if="!data.errors.length" class="m-0 text-sm text-n-slate-11">
                {{ t('COMMUNITY_CAMPAIGNS.NO_ERRORS') }}
              </p>
              <ul v-else class="m-0 flex list-none flex-col gap-3 p-0">
                <li
                  v-for="(failure, index) in data.errors"
                  :key="index"
                  class="flex items-start justify-between gap-4 border-b border-n-weak pb-3 last:border-0 last:pb-0"
                >
                  <div>
                    <span class="font-mono text-xs text-n-ruby-11">
                      {{
                        failure.code || t('COMMUNITY_CAMPAIGNS.UNKNOWN_CODE')
                      }}
                    </span>
                    <p class="mb-0 mt-1 text-sm text-n-slate-11">
                      {{
                        failure.message ||
                        t('COMMUNITY_CAMPAIGNS.NO_ERROR_DETAILS')
                      }}
                    </p>
                  </div>
                  <strong
                    class="rounded-lg bg-n-ruby-9/10 px-3 py-1 text-sm tabular-nums text-n-ruby-11"
                  >
                    {{ number(failure.count) }}
                  </strong>
                </li>
              </ul>
            </section>
            <section
              class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
            >
              <div
                class="flex flex-wrap items-center justify-between gap-4 p-5"
              >
                <h2 class="m-0 text-base font-semibold text-n-slate-12">
                  {{ t('COMMUNITY_CAMPAIGNS.RECIPIENTS') }}
                </h2>
                <div class="flex w-full flex-col gap-3 md:w-auto md:flex-row">
                  <input
                    v-model="filters.query"
                    type="search"
                    maxlength="100"
                    class="m-0 h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm text-n-slate-12"
                    :aria-label="t('COMMUNITY_CAMPAIGNS.SEARCH')"
                    :placeholder="t('COMMUNITY_CAMPAIGNS.SEARCH')"
                  />
                  <div class="w-full md:w-52">
                    <ComboBox
                      v-model="filters.status"
                      :options="statusOptions"
                      :placeholder="t('COMMUNITY_CAMPAIGNS.ALL_STATUSES')"
                    />
                  </div>
                </div>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-sm">
                  <thead
                    class="border-y border-n-weak bg-n-solid-2 text-xs text-n-slate-11"
                  >
                    <tr>
                      <th class="p-4 text-start">
                        {{ t('COMMUNITY_CAMPAIGNS.CONTACT') }}
                      </th>
                      <th class="p-4 text-start">
                        {{ t('COMMUNITY_CAMPAIGNS.CAMPAIGN') }}
                      </th>
                      <th class="p-4 text-start">
                        {{ t('COMMUNITY_CAMPAIGNS.STATUS') }}
                      </th>
                      <th class="p-4 text-start">
                        {{ t('COMMUNITY_CAMPAIGNS.LAST_EVENT') }}
                      </th>
                      <th class="p-4 text-start">
                        {{ t('COMMUNITY_CAMPAIGNS.ERROR') }}
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-n-weak">
                    <tr
                      v-for="recipient in data.recipients"
                      :key="recipient.id"
                      class="hover:bg-n-alpha-2"
                    >
                      <td class="p-4">
                        <span class="font-medium text-n-slate-12">
                          {{
                            recipient.contact.name ||
                            t('COMMUNITY_CAMPAIGNS.DELETED_CONTACT')
                          }}
                        </span>
                        <p class="mb-0 mt-1 text-xs text-n-slate-11">
                          {{ recipient.contact.phone_number }}
                        </p>
                      </td>
                      <td class="p-4 text-n-slate-11">
                        {{ recipient.campaign_title }}
                      </td>
                      <td class="p-4">
                        <span
                          class="whitespace-nowrap rounded-md px-2 py-1 text-xs"
                          :class="badgeClasses[recipient.status]"
                        >
                          {{ labels.statuses[recipient.status] }}
                        </span>
                        <span
                          v-if="recipient.replied_at"
                          class="ms-1 whitespace-nowrap rounded-md bg-n-blue-9/10 px-2 py-1 text-xs text-n-blue-11"
                          :title="time(recipient.replied_at)"
                        >
                          {{ replyBadge(recipient) }}
                        </span>
                      </td>
                      <td
                        class="whitespace-nowrap p-4 text-xs text-n-slate-11"
                        :title="`${t('COMMUNITY_CAMPAIGNS.SENT')}: ${time(recipient.sent_at)} · ${t('COMMUNITY_CAMPAIGNS.DELIVERED')}: ${time(recipient.delivered_at)} · ${t('COMMUNITY_CAMPAIGNS.READ')}: ${time(recipient.read_at)}`"
                      >
                        {{ time(recipient.last_event_at) }}
                      </td>
                      <td class="max-w-80 p-4 text-xs text-n-slate-11">
                        <span
                          v-if="recipient.error_code"
                          class="me-2 font-mono text-n-ruby-11"
                        >
                          {{ recipient.error_code }}
                        </span>
                        {{ recipient.error_message || '—' }}
                      </td>
                    </tr>
                    <tr v-if="!data.recipients.length">
                      <td colspan="5" class="p-8 text-center text-n-slate-11">
                        {{ t('COMMUNITY_CAMPAIGNS.NO_RECIPIENTS') }}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <footer
                class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak px-5 py-4"
              >
                <span class="text-xs text-n-slate-11">
                  {{
                    t('COMMUNITY_CAMPAIGNS.PAGE', {
                      page: data.pagination.page,
                      pages: Math.max(1, data.pagination.pages),
                      total: number(data.pagination.total),
                    })
                  }}
                </span>
                <div class="flex gap-2">
                  <Button
                    sm
                    slate
                    outline
                    :label="t('COMMUNITY_CAMPAIGNS.PREVIOUS')"
                    :disabled="filters.page <= 1 || isPending"
                    @click="filters.page -= 1"
                  />
                  <Button
                    sm
                    slate
                    outline
                    :label="t('COMMUNITY_CAMPAIGNS.NEXT')"
                    :disabled="
                      filters.page >= data.pagination.pages || isPending
                    "
                    @click="filters.page += 1"
                  />
                </div>
              </footer>
            </section>
          </template>
        </template>
      </div>
    </main>
  </section>
</template>
