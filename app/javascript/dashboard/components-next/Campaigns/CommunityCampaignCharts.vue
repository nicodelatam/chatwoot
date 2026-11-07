<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { DonutChart, LineChart, BarChart } from '@chatwoot/viz';
import Button from 'dashboard/components-next/button/Button.vue';
import { campaignStatisticsLabels } from 'dashboard/helper/communityCampaignStatistics';
import { useWindowSize } from '@vueuse/core';
import { format, startOfWeek, startOfMonth } from 'date-fns';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({ report: { type: Object, required: true } });
const emit = defineEmits(['status', 'campaign']);
const { t } = useI18n();
const labels = computed(() => campaignStatisticsLabels(t));
const chartType = ref('line');
const period = ref('auto');
const { width } = useWindowSize();
const periodOptions = computed(() => [
  { value: 'auto', label: t('COMMUNITY_CAMPAIGNS.PERIOD_AUTO') },
  { value: 'day', label: t('COMMUNITY_CAMPAIGNS.PERIOD_DAY') },
  { value: 'week', label: t('COMMUNITY_CAMPAIGNS.PERIOD_WEEK') },
  { value: 'month', label: t('COMMUNITY_CAMPAIGNS.PERIOD_MONTH') },
]);
const colors = {
  pending: 'rgb(var(--slate-6))',
  sent: 'rgb(var(--blue-9))',
  delivered: 'rgb(var(--teal-9))',
  read: 'rgb(var(--iris-9))',
  failed: 'rgb(var(--ruby-9))',
  unconfirmed: 'rgb(var(--amber-9))',
};
const formatCount = value => Number(value).toLocaleString('es-CO');
const states = ['sent', 'delivered', 'read', 'failed'];
const series = rows =>
  states.map(state => ({
    id: state,
    label: labels.value.metrics.find(metric => metric.key === state).label,
    color: colors[state],
    data: rows.map(row => ({
      value: row[state] || 0,
      description: row.description,
    })),
  }));
const distribution = computed(() => ({
  total: props.report.summary.total,
  segments: Object.entries(colors).map(([state, color]) => ({
    id: state,
    label: labels.value.statuses[state],
    value: props.report.distribution[state] || 0,
    color,
  })),
}));
const activity = computed(() => {
  let grouping = period.value || 'auto';
  if (grouping === 'auto') {
    grouping = 'day';
    if (
      props.report.timeline.length > 20 ||
      (width.value < 640 && props.report.timeline.length > 7)
    )
      grouping = 'week';
    if (props.report.timeline.length > 90) grouping = 'month';
  }
  const buckets = new Map();
  props.report.timeline.forEach(row => {
    const date = new Date(`${row.date}T12:00:00`);
    let start = date;
    if (grouping === 'week') start = startOfWeek(date, { weekStartsOn: 1 });
    if (grouping === 'month') start = startOfMonth(date);
    const key = format(start, 'yyyy-MM-dd');
    if (!buckets.has(key))
      buckets.set(key, {
        start: date,
        end: date,
        sent: 0,
        delivered: 0,
        read: 0,
        failed: 0,
      });
    const bucket = buckets.get(key);
    bucket.end = date;
    states.forEach(state => {
      bucket[state] += row[state] || 0;
    });
  });
  const dateLabel = date =>
    new Intl.DateTimeFormat('es-CO', { day: 'numeric', month: 'short' }).format(
      date
    );
  const rows = [...buckets.values()].map(bucket => ({
    ...bucket,
    description: `${new Intl.DateTimeFormat('es-CO', { dateStyle: 'medium' }).format(bucket.start)} – ${new Intl.DateTimeFormat('es-CO', { dateStyle: 'medium' }).format(bucket.end)}`,
  }));
  return {
    categories: rows.map(row => {
      if (grouping === 'day') return format(row.start, 'dd');
      if (grouping === 'month')
        return new Intl.DateTimeFormat('es-CO', { month: 'short' }).format(
          row.start
        );
      return `${format(row.start, 'd')}–${dateLabel(row.end)}`;
    }),
    series: series(rows),
  };
});
const rankedCampaigns = computed(() =>
  [...props.report.campaigns]
    .sort((a, b) => b.metrics.delivered - a.metrics.delivered)
    .slice(0, 10)
);
const comparison = computed(() => ({
  categories: rankedCampaigns.value.map(campaign => campaign.title),
  series: series(rankedCampaigns.value.map(campaign => campaign.metrics)),
}));
const selectCampaign = item => {
  const campaign = rankedCampaigns.value[item.categoryIndex];
  if (campaign) emit('campaign', campaign.id);
};
</script>

<template>
  <div class="grid grid-cols-1 gap-5 xl:grid-cols-3">
    <section class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1 p-5">
      <h2 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('COMMUNITY_CAMPAIGNS.DISTRIBUTION') }}
      </h2>
      <p class="mb-5 mt-2 text-sm text-n-slate-11">
        {{ t('COMMUNITY_CAMPAIGNS.DISTRIBUTION_HINT') }}
      </p>
      <DonutChart
        v-if="report.summary.total"
        :data="distribution"
        :diameter="180"
        :thickness="24"
        show-tooltip
        :format-value="formatCount"
        :aria-label="t('COMMUNITY_CAMPAIGNS.DISTRIBUTION')"
        :on-item-click="item => emit('status', item.id)"
        class="[--cw-viz-donut-tooltip-background:rgb(var(--solid-2))] [--cw-viz-donut-tooltip-color:rgb(var(--slate-12))] [--cw-viz-donut-tooltip-label-color:rgb(var(--slate-11))] [--cw-viz-donut-tooltip-border-color:rgb(var(--border-strong))]"
      />
      <p v-else class="py-12 text-center text-sm text-n-slate-11">
        {{ t('COMMUNITY_CAMPAIGNS.NO_RATE') }}
      </p>
    </section>
    <section
      class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1 p-5 xl:col-span-2"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t('COMMUNITY_CAMPAIGNS.ACTIVITY') }}
        </h2>
        <div class="flex flex-wrap items-center gap-2">
          <div class="w-36">
            <ComboBox v-model="period" :options="periodOptions" />
          </div>
          <Button
            xs
            slate
            :outline="chartType === 'line'"
            :ghost="chartType !== 'line'"
            :label="t('COMMUNITY_CAMPAIGNS.LINE')"
            @click="chartType = 'line'"
          />
          <Button
            xs
            slate
            :outline="chartType === 'bar'"
            :ghost="chartType !== 'bar'"
            :label="t('COMMUNITY_CAMPAIGNS.BARS')"
            @click="chartType = 'bar'"
          />
        </div>
      </div>
      <p class="mb-5 mt-2 text-sm text-n-slate-11">
        {{ t('COMMUNITY_CAMPAIGNS.ACTIVITY_HINT') }}
      </p>
      <component
        :is="chartType === 'line' ? LineChart : BarChart"
        :data="activity"
        :height="260"
        :point-radius="3"
        :show-values="false"
        show-tooltip
        :format-value="formatCount"
        :aria-label="t('COMMUNITY_CAMPAIGNS.ACTIVITY')"
        class="[--cw-viz-line-label-color:rgb(var(--slate-11))] [--cw-viz-line-axis-color:rgb(var(--slate-4))] [--cw-viz-line-tooltip-background:rgb(var(--solid-2))] [--cw-viz-line-tooltip-color:rgb(var(--slate-12))] [--cw-viz-line-tooltip-label-color:rgb(var(--slate-11))] [--cw-viz-line-tooltip-border-color:rgb(var(--border-strong))] [--cw-viz-bar-label-color:rgb(var(--slate-11))] [--cw-viz-bar-axis-color:rgb(var(--slate-4))] [--cw-viz-bar-tooltip-background:rgb(var(--solid-2))] [--cw-viz-bar-tooltip-color:rgb(var(--slate-12))] [--cw-viz-bar-tooltip-label-color:rgb(var(--slate-11))] [--cw-viz-bar-tooltip-border-color:rgb(var(--border-strong))]"
      />
      <div
        class="mt-3 flex flex-wrap justify-center gap-4 text-xs text-n-slate-11"
      >
        <span
          v-for="state in states"
          :key="state"
          class="flex items-center gap-2"
        >
          <span
            class="size-2 rounded-full"
            :class="{
              'bg-n-blue-9': state === 'sent',
              'bg-n-teal-9': state === 'delivered',
              'bg-n-iris-9': state === 'read',
              'bg-n-ruby-9': state === 'failed',
            }"
          />
          {{ labels.metrics.find(metric => metric.key === state).label }}
        </span>
      </div>
    </section>
  </div>
  <section class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1 p-5">
    <h2 class="m-0 text-base font-semibold text-n-slate-12">
      {{ t('COMMUNITY_CAMPAIGNS.COMPARISON') }}
    </h2>
    <p class="mb-5 mt-2 text-sm text-n-slate-11">
      {{ t('COMMUNITY_CAMPAIGNS.COMPARISON_HINT') }}
    </p>
    <BarChart
      :data="comparison"
      :height="230"
      :show-values="false"
      show-tooltip
      :format-value="formatCount"
      :aria-label="t('COMMUNITY_CAMPAIGNS.COMPARISON')"
      :on-item-click="selectCampaign"
      class="[--cw-viz-bar-label-color:rgb(var(--slate-11))] [--cw-viz-bar-axis-color:rgb(var(--slate-4))] [--cw-viz-bar-tooltip-background:rgb(var(--solid-2))] [--cw-viz-bar-tooltip-color:rgb(var(--slate-12))] [--cw-viz-bar-tooltip-label-color:rgb(var(--slate-11))] [--cw-viz-bar-tooltip-border-color:rgb(var(--border-strong))]"
    />
  </section>
</template>
