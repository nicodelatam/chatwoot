<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCommunityWhatsappCalling } from 'dashboard/composables/useCommunityWhatsappCalling';
import CommunityWhatsappCallsAPI from 'dashboard/api/communityWhatsappCalls';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const store = useStore();
const { accountId } = useAccount();
const calling = useCommunityWhatsappCalling();

const isToggling = ref(false);
const callingEnabled = computed(
  () => props.inbox.provider_config?.community_calling_enabled === true
);

const handleToggle = async enabled => {
  if (isToggling.value) return;
  isToggling.value = true;
  try {
    await CommunityWhatsappCallsAPI.configure(accountId.value, {
      inbox_id: props.inbox.id,
      enabled,
    });
    await store.dispatch('inboxes/get', props.inbox.id);
    await calling.syncCalls();
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE')
    );
  } finally {
    isToggling.value = false;
  }
};
</script>

<template>
  <div
    class="relative"
    :class="{ 'pointer-events-none opacity-60': isToggling }"
  >
    <SettingsToggleSection
      :model-value="callingEnabled"
      :header="t('INBOX_MGMT.WHATSAPP_CALLING.ENABLE.LABEL')"
      :description="t('INBOX_MGMT.WHATSAPP_CALLING.ENABLE.DESCRIPTION')"
      :hide-toggle="isToggling"
      @update:model-value="handleToggle"
    >
      <template v-if="isToggling" #hiddenToggle>
        <Spinner class="size-4 text-n-slate-11" />
      </template>
    </SettingsToggleSection>
  </div>
</template>
