<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  attribution: { type: Object, required: true },
});

const { t } = useI18n();

const isConfirmed = computed(
  () => props.attribution.confidence === 'confirmed'
);
const sources = computed(() => ({
  button: {
    label: t('COMMUNITY_CAMPAIGNS.REPLY_ATTRIBUTION.SOURCES.BUTTON'),
    hint: t('COMMUNITY_CAMPAIGNS.REPLY_ATTRIBUTION.HINTS.BUTTON'),
  },
  quote: {
    label: t('COMMUNITY_CAMPAIGNS.REPLY_ATTRIBUTION.SOURCES.QUOTE'),
    hint: t('COMMUNITY_CAMPAIGNS.REPLY_ATTRIBUTION.HINTS.QUOTE'),
  },
  window: {
    label: t('COMMUNITY_CAMPAIGNS.REPLY_ATTRIBUTION.SOURCES.WINDOW'),
    hint: t('COMMUNITY_CAMPAIGNS.REPLY_ATTRIBUTION.HINTS.WINDOW'),
  },
}));
const source = computed(() => sources.value[props.attribution.source]);
const detail = computed(() =>
  t('COMMUNITY_CAMPAIGNS.REPLY_ATTRIBUTION.DETAIL', {
    source: source.value.label,
    date: new Intl.DateTimeFormat('es-CO', {
      dateStyle: 'medium',
      timeStyle: 'short',
    }).format(new Date(props.attribution.sentAt)),
  })
);
</script>

<template>
  <div
    class="flex w-full max-w-lg items-start gap-3 rounded-lg border border-n-weak bg-n-alpha-1 p-3"
    data-testid="campaign-reply-attribution"
  >
    <Icon
      icon="i-lucide-megaphone"
      class="mt-0.5 size-4 shrink-0 text-n-slate-11"
    />
    <div class="min-w-0">
      <div class="flex flex-wrap items-center gap-2">
        <span class="text-xs text-n-slate-11">
          {{ t('COMMUNITY_CAMPAIGNS.REPLY_ATTRIBUTION.TITLE') }}
        </span>
        <span
          class="rounded-md px-1.5 py-0.5 text-xs"
          :class="
            isConfirmed
              ? 'bg-n-teal-9/10 text-n-teal-11'
              : 'bg-n-amber-9/10 text-n-amber-11'
          "
          :title="source.hint"
        >
          {{
            isConfirmed
              ? t('COMMUNITY_CAMPAIGNS.REPLY_ATTRIBUTION.CONFIRMED')
              : t('COMMUNITY_CAMPAIGNS.REPLY_ATTRIBUTION.PROBABLE')
          }}
        </span>
      </div>
      <p class="mb-0 mt-1 break-words font-medium text-n-slate-12">
        {{ attribution.title }}
      </p>
      <p class="mb-0 mt-1 text-xs text-n-slate-11">
        {{ detail }}
      </p>
    </div>
  </div>
</template>
