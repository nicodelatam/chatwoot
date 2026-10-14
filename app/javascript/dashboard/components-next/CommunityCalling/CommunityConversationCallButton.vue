<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useCommunityWhatsappCalling } from 'dashboard/composables/useCommunityWhatsappCalling';

const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
  chat: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const calling = useCommunityWhatsappCalling();
const isCommunityWhatsapp = computed(
  () =>
    props.inbox?.channel_type === 'Channel::Whatsapp' &&
    props.inbox?.provider === 'whatsapp_cloud'
);
const isEnabled = computed(() =>
  calling.configuredInboxIds.value.has(props.inbox?.id)
);
const isVisible = computed(() => isCommunityWhatsapp.value && isEnabled.value);

const startCall = async () => {
  calling.panelOpen.value = true;
  await calling.startOutgoingCall(props.chat.id);
};
</script>

<template>
  <div class="contents">
    <NextButton
      v-if="isVisible"
      v-tooltip.bottom="t('COMMUNITY_CALLING.CALL')"
      sm
      ghost
      slate
      icon="i-lucide-phone"
      :is-loading="calling.busy.value"
      :disabled="calling.busy.value || calling.isActive.value"
      :aria-label="t('COMMUNITY_CALLING.CALL')"
      @click="startCall"
    />
  </div>
</template>
