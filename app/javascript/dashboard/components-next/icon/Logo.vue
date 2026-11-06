<script setup>
import { useMapGetter } from 'dashboard/composables/store';
const globalConfig = useMapGetter('globalConfig/get');
</script>

<template>
  <img
    :src="globalConfig.logoThumbnail || '/branding/nico-mark.svg'"
    :alt="globalConfig.installationName"
    class="object-contain"
  />
</template>
