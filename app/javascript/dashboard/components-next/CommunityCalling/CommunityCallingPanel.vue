<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAccount } from 'dashboard/composables/useAccount';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useCommunityWhatsappCalling } from 'dashboard/composables/useCommunityWhatsappCalling';

const { accountId } = useAccount();
const { isAdmin } = useAdmin();
const { t } = useI18n();
const calling = useCommunityWhatsappCalling();

const displayedCall = computed(
  () => calling.activeCall.value || calling.incomingCall.value
);
const visible = computed(
  () => calling.panelOpen.value || !!displayedCall.value
);
const hasInboxes = computed(() => calling.inboxes.value.length > 0);
const accountIdentifier = computed(() => accountId.value);
const ringtone = new Audio('/audio/dashboard/ringtone.mp3');
ringtone.loop = true;
const ringingAudioBlocked = ref(false);

const callStatus = computed(() => {
  if (!calling.activeCall.value) return t('COMMUNITY_CALLING.STATUS_INCOMING');
  if (calling.activeCall.value.status === 'active') {
    return t('COMMUNITY_CALLING.STATUS_ACTIVE');
  }
  if (calling.activeCall.value.status === 'connecting') {
    return t('COMMUNITY_CALLING.STATUS_CONNECTING');
  }
  if (calling.activeCall.value.direction === 'outgoing') {
    return t('COMMUNITY_CALLING.STATUS_OUTGOING');
  }
  return t('COMMUNITY_CALLING.STATUS_CONNECTING');
});
const displayError = computed(() => {
  const message = calling.error.value;
  if (!message) return '';
  const messages = {
    'COMMUNITY_CALLING.ERRORS.MICROPHONE_DENIED': t(
      'COMMUNITY_CALLING.ERRORS.MICROPHONE_DENIED'
    ),
    'COMMUNITY_CALLING.ERRORS.MICROPHONE_MISSING': t(
      'COMMUNITY_CALLING.ERRORS.MICROPHONE_MISSING'
    ),
    'COMMUNITY_CALLING.ERRORS.BROWSER_UNSUPPORTED': t(
      'COMMUNITY_CALLING.ERRORS.BROWSER_UNSUPPORTED'
    ),
    'COMMUNITY_CALLING.ERRORS.SDP_GATHERING': t(
      'COMMUNITY_CALLING.ERRORS.SDP_GATHERING'
    ),
    'COMMUNITY_CALLING.ERRORS.CONNECTION_FAILED': t(
      'COMMUNITY_CALLING.ERRORS.CONNECTION_FAILED'
    ),
    'COMMUNITY_CALLING.ERRORS.CONNECTION_TIMEOUT': t(
      'COMMUNITY_CALLING.ERRORS.CONNECTION_TIMEOUT'
    ),
    'COMMUNITY_CALLING.ERRORS.RING_TIMEOUT': t(
      'COMMUNITY_CALLING.ERRORS.RING_TIMEOUT'
    ),
    'COMMUNITY_CALLING.ERRORS.ACCOUNT_CHANGED': t(
      'COMMUNITY_CALLING.ERRORS.ACCOUNT_CHANGED'
    ),
    'COMMUNITY_CALLING.ERRORS.GENERIC': t('COMMUNITY_CALLING.ERRORS.GENERIC'),
    'COMMUNITY_CALLING.ERRORS.PERMISSION_REQUIRED': t(
      'COMMUNITY_CALLING.ERRORS.PERMISSION_REQUIRED'
    ),
    'COMMUNITY_CALLING.ERRORS.PERMISSION_PERMANENT': t(
      'COMMUNITY_CALLING.ERRORS.PERMISSION_PERMANENT'
    ),
    'COMMUNITY_CALLING.ERRORS.PERMISSION_TEMPORARY': t(
      'COMMUNITY_CALLING.ERRORS.PERMISSION_TEMPORARY'
    ),
    'COMMUNITY_CALLING.ERRORS.PERMISSION_REQUESTED': t(
      'COMMUNITY_CALLING.ERRORS.PERMISSION_REQUESTED'
    ),
  };
  return messages[message] || message;
});

onMounted(() => calling.start(accountIdentifier.value));
watch(accountIdentifier, id => calling.start(id));
const stopRingtone = () => {
  ringtone.pause();
  ringtone.currentTime = 0;
};
const playRingtone = async () => {
  if (!calling.incomingCall.value || calling.busy.value) return;
  try {
    await ringtone.play();
    ringingAudioBlocked.value = false;
  } catch {
    ringingAudioBlocked.value = true;
  }
};
watch(
  () => calling.incomingCall.value,
  call => {
    if (call) playRingtone();
    else {
      stopRingtone();
      ringingAudioBlocked.value = false;
    }
  },
  { immediate: true }
);
watch(
  () => calling.busy.value,
  busy => {
    if (busy) stopRingtone();
    else if (calling.incomingCall.value) playRingtone();
  }
);
onBeforeUnmount(() => {
  stopRingtone();
  calling.stop();
});

const toggleInbox = async inbox => {
  await calling.configureInbox(inbox.id, !inbox.enabled);
};

const askForPermission = async () => {
  const conversationId = calling.permissionConversationId.value;
  if (conversationId) await calling.requestPermission(conversationId);
};
</script>

<template>
  <div class="fixed bottom-4 end-4 z-50 flex flex-col items-end gap-2">
    <section
      v-if="visible"
      class="w-[22rem] max-w-[calc(100vw-2rem)] overflow-hidden rounded-2xl border border-n-weak bg-n-surface-1 shadow-xl"
      :aria-label="t('COMMUNITY_CALLING.PANEL_TITLE')"
    >
      <div
        class="flex items-center justify-between border-b border-n-weak px-4 py-3"
      >
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t('COMMUNITY_CALLING.PANEL_TITLE') }}
        </h2>
        <NextButton
          icon="i-lucide-x"
          slate
          ghost
          xs
          :aria-label="t('COMMUNITY_CALLING.CLOSE')"
          @click="calling.panelOpen.value = false"
        />
      </div>

      <div v-if="displayedCall" class="flex flex-col gap-3 p-4">
        <div class="flex items-center gap-3">
          <span
            class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-teal-9/10 text-n-teal-11"
          >
            <Icon icon="i-lucide-phone" class="size-5" />
          </span>
          <div class="min-w-0">
            <p class="m-0 truncate text-sm font-medium text-n-slate-12">
              {{ displayedCall.contact_name }}
            </p>
            <p class="m-0 text-sm text-n-slate-11">
              {{ callStatus }}
            </p>
            <p
              v-if="ringingAudioBlocked && calling.incomingCall.value"
              class="m-0 text-xs text-n-amber-11"
            >
              {{ t('COMMUNITY_CALLING.ERRORS.RING_BLOCKED') }}
            </p>
          </div>
        </div>
        <div class="flex justify-end gap-2">
          <template
            v-if="calling.incomingCall.value && !calling.activeCall.value"
          >
            <NextButton
              :label="t('COMMUNITY_CALLING.REJECT')"
              ruby
              :disabled="calling.busy.value"
              @click="calling.rejectIncomingCall(calling.incomingCall.value)"
            />
            <NextButton
              :label="t('COMMUNITY_CALLING.ANSWER')"
              teal
              :is-loading="calling.busy.value"
              :disabled="calling.busy.value"
              @click="calling.acceptIncomingCall(calling.incomingCall.value)"
            />
          </template>
          <template v-else-if="calling.activeCall.value">
            <NextButton
              v-if="calling.activeCall.value.status === 'active'"
              :label="
                calling.muted.value
                  ? t('COMMUNITY_CALLING.UNMUTE')
                  : t('COMMUNITY_CALLING.MUTE')
              "
              slate
              :icon="calling.muted.value ? 'i-lucide-mic-off' : 'i-lucide-mic'"
              @click="calling.toggleMute"
            />
            <NextButton
              :label="t('COMMUNITY_CALLING.HANG_UP')"
              ruby
              :is-loading="calling.busy.value"
              :disabled="calling.busy.value"
              @click="calling.terminateCall"
            />
          </template>
        </div>
      </div>

      <div v-else class="flex flex-col gap-3 p-4">
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('COMMUNITY_CALLING.SETUP_DESCRIPTION') }}
        </p>
        <ul v-if="isAdmin" class="m-0 flex list-none flex-col gap-2 p-0">
          <li
            v-for="inbox in calling.inboxes.value"
            :key="inbox.id"
            class="flex items-center justify-between gap-3"
          >
            <span class="truncate text-sm text-n-slate-12">{{
              inbox.name
            }}</span>
            <button
              type="button"
              class="relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors disabled:cursor-not-allowed disabled:opacity-50"
              :class="inbox.enabled ? 'bg-n-teal-9' : 'bg-n-slate-5'"
              :aria-pressed="inbox.enabled"
              :aria-label="
                t('COMMUNITY_CALLING.TOGGLE_INBOX', { name: inbox.name })
              "
              :disabled="!inbox.can_manage || calling.busy.value"
              @click="toggleInbox(inbox)"
            >
              <span
                class="inline-block size-4 rounded-full bg-white transition-transform"
                :class="inbox.enabled ? 'translate-x-6' : 'translate-x-1'"
              />
            </button>
          </li>
        </ul>
        <p v-else class="m-0 text-sm text-n-slate-11">
          {{ t('COMMUNITY_CALLING.ADMIN_SETUP') }}
        </p>
      </div>

      <div
        v-if="calling.error.value"
        class="flex flex-col gap-2 border-t border-n-weak px-4 py-3"
      >
        <p class="m-0 text-sm text-n-ruby-11">{{ displayError }}</p>
        <NextButton
          v-if="
            calling.permissionConversationId.value &&
            calling.canRequestPermission.value
          "
          :label="t('COMMUNITY_CALLING.REQUEST_PERMISSION')"
          sm
          outline
          ruby
          :is-loading="calling.busy.value"
          :disabled="calling.busy.value"
          @click="askForPermission"
        />
      </div>
    </section>

    <NextButton
      v-if="!visible && hasInboxes"
      :label="t('COMMUNITY_CALLING.PANEL_TITLE')"
      icon="i-ri-whatsapp-fill"
      slate
      class="shadow-lg"
      :aria-expanded="visible"
      @click="calling.panelOpen.value = !calling.panelOpen.value"
    />
  </div>
</template>
