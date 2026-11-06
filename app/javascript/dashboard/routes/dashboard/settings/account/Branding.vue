<script setup>
import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import BrandingAPI from 'dashboard/api/workspaceBranding';
import Button from 'dashboard/components-next/button/Button.vue';
import { applyWorkspaceTokens } from 'shared/helpers/workspaceBranding';
import { defaultBranding } from '../../../../../../../theme/workspaceBranding';

const { t } = useI18n();
const store = useStore();
const form = reactive({ ...defaultBranding });
const loading = ref(true);
const loadFailed = ref(false);
const saving = ref(false);
const error = ref('');
const logo = ref(null);
const removeLogo = ref(false);
const previewURL = ref('');
const loginURL = ref('');
const resetConfirmation = ref(false);
const fileInput = ref(null);
const previewLogo = computed(() => previewURL.value || form.logo_url);
const validColor = computed(() => /^#[a-f\d]{6}$/i.test(form.color));
const swatches = [
  '#E30613',
  '#2563EB',
  '#0F766E',
  '#7C3AED',
  '#B45309',
  '#334155',
];
const releasePreview = () => {
  if (previewURL.value) URL.revokeObjectURL(previewURL.value);
  previewURL.value = '';
};
const hydrate = data => {
  Object.assign(form, data);
  loginURL.value = data.login_url;
  logo.value = null;
  removeLogo.value = false;
  releasePreview();
  if (fileInput.value) fileInput.value.value = '';
};
watch(
  () => form.color,
  color => {
    if (validColor.value)
      applyWorkspaceTokens(color, '#workspace-brand-preview');
  },
  { immediate: true }
);
onMounted(async () => {
  try {
    hydrate((await BrandingAPI.get()).data);
  } catch {
    loadFailed.value = true;
    error.value = t('WORKSPACE_BRANDING.LOAD_ERROR');
  } finally {
    loading.value = false;
  }
});
onUnmounted(releasePreview);
function selectLogo(event) {
  const file = event.target.files[0];
  if (!file) return;
  if (
    !['image/png', 'image/jpeg', 'image/webp'].includes(file.type) ||
    file.size > 2 * 1024 * 1024
  ) {
    error.value = t('WORKSPACE_BRANDING.LOGO_HELP');
    event.target.value = '';
    return;
  }
  error.value = '';
  releasePreview();
  previewURL.value = URL.createObjectURL(file);
  logo.value = file;
  removeLogo.value = false;
}
function clearLogo() {
  releasePreview();
  logo.value = null;
  removeLogo.value = true;
  form.logo_url = defaultBranding.logo_url;
  if (fileInput.value) fileInput.value.value = '';
}
async function persist(reset = false) {
  saving.value = true;
  error.value = '';
  try {
    const payload = new FormData();
    ['name', 'color', 'website_url'].forEach(key =>
      payload.append(key, form[key])
    );
    if (logo.value) payload.append('logo', logo.value);
    if (removeLogo.value) payload.append('remove_logo', '1');
    const response = reset
      ? await BrandingAPI.delete('')
      : await BrandingAPI.update('', payload);
    hydrate(response.data);
    await store.dispatch('accounts/get');
    resetConfirmation.value = false;
    useAlert(t('WORKSPACE_BRANDING.SAVED'));
  } catch (e) {
    error.value = e.response?.data?.error || t('WORKSPACE_BRANDING.SAVE_ERROR');
  } finally {
    saving.value = false;
  }
}
async function copyLink() {
  try {
    await navigator.clipboard.writeText(loginURL.value);
    useAlert(t('WORKSPACE_BRANDING.COPIED'));
  } catch {
    error.value = t('WORKSPACE_BRANDING.COPY_ERROR');
  }
}
</script>

<template>
  <div class="w-full pt-5 pb-20 text-n-slate-12 md:pb-5">
    <header class="mb-8 flex flex-wrap items-start justify-between gap-4">
      <div class="max-w-xl">
        <h1 class="text-2xl font-semibold tracking-tight">
          {{ t('WORKSPACE_BRANDING.TITLE') }}
        </h1>
        <p class="mt-2 text-sm leading-6 text-n-slate-11">
          {{ t('WORKSPACE_BRANDING.DESCRIPTION') }}
        </p>
      </div>
      <span
        class="flex items-center gap-2 rounded-full bg-n-blue-3 px-3 py-1.5 text-xs font-medium text-n-blue-11"
      >
        <span class="i-lucide-building-2 size-3.5" />{{
          t('WORKSPACE_BRANDING.WORKSPACE_ONLY')
        }}
      </span>
    </header>
    <p v-if="loading" role="status" class="py-12 text-center text-n-slate-11">
      {{ t('WORKSPACE_BRANDING.LOADING') }}
    </p>
    <p v-if="error" role="alert" class="mb-5 text-sm text-n-ruby-11">
      {{ error }}
    </p>
    <form
      v-if="!loading && !loadFailed"
      class="grid gap-8 lg:grid-cols-2"
      @submit.prevent="persist()"
    >
      <div class="space-y-7">
        <section class="rounded-2xl border border-n-weak bg-n-solid-1 p-6">
          <h2 class="text-base font-semibold">
            {{ t('WORKSPACE_BRANDING.IDENTITY') }}
          </h2>
          <label for="brand-name" class="mt-6 block text-sm font-medium">{{
            t('WORKSPACE_BRANDING.NAME')
          }}</label>
          <input
            id="brand-name"
            v-model="form.name"
            required
            maxlength="80"
            autocomplete="organization"
            class="mt-2 w-full rounded-xl border border-n-strong bg-n-surface-1 text-n-slate-12 px-3 py-2.5 text-base focus:border-n-blue-9 focus:ring-2 focus:ring-n-blue-4 sm:text-sm"
          />
          <label class="mt-6 block text-sm font-medium" for="brand-logo">{{
            t('WORKSPACE_BRANDING.LOGO')
          }}</label>
          <div class="mt-3 flex items-center gap-4">
            <div
              class="grid size-20 shrink-0 place-items-center rounded-2xl border border-n-weak bg-n-background p-3"
            >
              <img
                :src="previewLogo"
                :alt="form.name"
                class="max-h-full max-w-full object-contain"
              />
            </div>
            <div class="min-w-0 space-y-2">
              <input
                id="brand-logo"
                ref="fileInput"
                type="file"
                accept="image/png,image/jpeg,image/webp"
                class="block w-full text-xs text-n-slate-11 file:me-3 file:rounded-lg file:border-0 file:bg-n-slate-3 file:px-3 file:py-2 file:font-medium file:text-n-slate-12"
                @change="selectLogo"
              />
              <button
                type="button"
                class="text-xs text-n-blue-11 hover:underline"
                @click="clearLogo"
              >
                {{ t('WORKSPACE_BRANDING.REMOVE_LOGO') }}
              </button>
            </div>
          </div>
          <p class="mt-3 text-xs leading-5 text-n-slate-11">
            {{ t('WORKSPACE_BRANDING.LOGO_HELP') }}
          </p>
          <label for="brand-website" class="mt-6 block text-sm font-medium">{{
            t('WORKSPACE_BRANDING.WEBSITE')
          }}</label>
          <input
            id="brand-website"
            v-model="form.website_url"
            type="url"
            :placeholder="t('WORKSPACE_BRANDING.WEBSITE_PLACEHOLDER')"
            class="mt-2 w-full rounded-xl border border-n-strong bg-n-surface-1 text-n-slate-12 px-3 py-2.5 text-base focus:border-n-blue-9 focus:ring-2 focus:ring-n-blue-4 sm:text-sm"
          />
          <p class="mt-2 text-xs leading-5 text-n-slate-11">
            {{ t('WORKSPACE_BRANDING.WEBSITE_HELP') }}
          </p>
        </section>
        <section class="rounded-2xl border border-n-weak bg-n-solid-1 p-6">
          <h2 class="text-base font-semibold">
            {{ t('WORKSPACE_BRANDING.COLOR') }}
          </h2>
          <div class="mt-5 flex items-center gap-3">
            <input
              id="brand-color-picker"
              v-model="form.color"
              type="color"
              :aria-label="t('WORKSPACE_BRANDING.COLOR')"
              class="size-11 cursor-pointer rounded-lg border border-n-strong bg-n-surface-1 p-1"
            />
            <input
              id="brand-color"
              v-model="form.color"
              :aria-label="t('WORKSPACE_BRANDING.COLOR_HEX')"
              required
              pattern="#[a-fA-F0-9]{6}"
              maxlength="7"
              class="w-36 rounded-xl border border-n-strong bg-n-surface-1 text-n-slate-12 px-3 py-2.5 font-mono text-sm uppercase focus:border-n-blue-9 focus:ring-2 focus:ring-n-blue-4"
            />
          </div>
          <div class="mt-4 flex gap-2">
            <button
              v-for="(swatch, index) in swatches"
              :key="swatch"
              type="button"
              :aria-label="swatch"
              :aria-pressed="form.color.toUpperCase() === swatch"
              class="grid size-8 place-items-center rounded-full text-white outline-offset-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
              :class="
                [
                  'bg-[#E30613]',
                  'bg-[#2563EB]',
                  'bg-[#0F766E]',
                  'bg-[#7C3AED]',
                  'bg-[#B45309]',
                  'bg-[#334155]',
                ][index]
              "
              @click="form.color = swatch"
            >
              <span
                v-if="form.color.toUpperCase() === swatch"
                class="i-lucide-check size-4"
              />
            </button>
          </div>
          <p class="mt-4 text-xs leading-5 text-n-slate-11">
            {{ t('WORKSPACE_BRANDING.COLOR_HELP') }}
          </p>
        </section>
      </div>
      <div class="space-y-6">
        <section class="lg:sticky lg:top-4">
          <h2 class="mb-3 text-sm font-medium text-n-slate-11">
            {{ t('WORKSPACE_BRANDING.PREVIEW') }}
          </h2>
          <div
            id="workspace-brand-preview"
            class="overflow-hidden rounded-2xl border border-n-weak bg-n-background shadow-sm"
          >
            <div
              class="flex items-center gap-3 border-b border-n-weak bg-n-surface-1 px-5 py-4"
            >
              <img
                :src="previewLogo"
                :alt="form.name"
                class="size-9 object-contain"
              />
              <span class="truncate font-semibold text-n-slate-12">{{
                form.name
              }}</span>
              <span
                class="ms-auto flex items-center gap-1.5 text-xs text-n-slate-11"
              >
                <span class="size-1.5 rounded-full bg-n-teal-9" />
                {{ t('WORKSPACE_BRANDING.ONLINE') }}
              </span>
            </div>
            <div class="space-y-5 p-6">
              <div class="flex items-center gap-2 text-xs text-n-slate-11">
                <span class="i-lucide-message-circle size-4" />{{
                  t('WORKSPACE_BRANDING.CONVERSATION')
                }}
              </div>
              <div
                class="me-8 rounded-2xl rounded-es-sm border border-n-weak bg-n-surface-1 p-4 text-sm text-n-slate-12"
              >
                {{ t('WORKSPACE_BRANDING.MESSAGE') }}
              </div>
              <div
                class="ms-8 rounded-2xl rounded-ee-sm bg-n-brand p-4 text-sm leading-6 text-white"
              >
                {{
                  t('WORKSPACE_BRANDING.REPLY', {
                    name: form.name || defaultBranding.name,
                  })
                }}
              </div>
              <div
                class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-surface-1 px-4 py-3 text-xs text-n-slate-11"
              >
                <span>{{ t('WORKSPACE_BRANDING.COMPOSER') }}</span>
                <span
                  class="ms-auto grid size-7 place-items-center rounded-lg bg-n-brand text-white"
                >
                  <span class="i-lucide-arrow-up size-4" />
                </span>
              </div>
            </div>
            <div
              class="flex items-center justify-center gap-2 border-t border-n-weak bg-n-surface-1 py-3 text-xs text-n-slate-11"
            >
              <img :src="previewLogo" alt="" class="size-4 object-contain" />{{
                form.name
              }}
            </div>
          </div>
          <p class="mt-3 text-xs leading-5 text-n-slate-11">
            {{ t('WORKSPACE_BRANDING.PREVIEW_HELP') }}
          </p>
          <div class="mt-6 rounded-2xl border border-n-weak p-5">
            <span class="i-lucide-link size-5 text-n-blue-11" />
            <h3 class="mt-3 text-sm font-semibold">
              {{ t('WORKSPACE_BRANDING.LOGIN_LINK') }}
            </h3>
            <p class="mt-2 text-xs leading-5 text-n-slate-11">
              {{ t('WORKSPACE_BRANDING.LOGIN_HELP') }}
            </p>
            <div class="mt-4 flex gap-2">
              <input
                :value="loginURL"
                readonly
                :aria-label="t('WORKSPACE_BRANDING.LOGIN_LINK')"
                class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-background px-3 py-2 text-xs"
                @focus="$event.target.select()"
              />
              <Button
                type="button"
                outline
                slate
                icon="i-lucide-copy"
                :aria-label="t('WORKSPACE_BRANDING.COPY')"
                @click="copyLink"
              />
            </div>
          </div>
        </section>
      </div>
      <footer
        class="flex flex-wrap items-center justify-between gap-4 border-t border-n-weak pt-6 lg:col-span-2"
      >
        <div class="flex flex-wrap items-center gap-3">
          <Button
            v-if="!resetConfirmation"
            type="button"
            ghost
            slate
            :label="t('WORKSPACE_BRANDING.RESET')"
            :disabled="saving"
            @click="resetConfirmation = true"
          />
          <template v-else>
            <span class="text-xs text-n-slate-11">{{
              t('WORKSPACE_BRANDING.RESET_CONFIRM')
            }}</span>
            <Button
              type="button"
              outline
              ruby
              :label="t('WORKSPACE_BRANDING.CONFIRM')"
              :disabled="saving"
              @click="persist(true)"
            />
            <Button
              type="button"
              ghost
              slate
              :label="t('WORKSPACE_BRANDING.CANCEL')"
              @click="resetConfirmation = false"
            />
          </template>
        </div>
        <Button
          type="submit"
          icon="i-lucide-check"
          :label="t('WORKSPACE_BRANDING.SAVE')"
          :disabled="saving || !validColor || !form.name.trim()"
          :is-loading="saving"
        />
      </footer>
    </form>
  </div>
</template>
