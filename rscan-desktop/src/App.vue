<script setup lang="ts">
import { ref } from 'vue'
import PointCloudViewer from './components/PointCloudViewer.vue'
import Sidebar from './components/Sidebar.vue'
import { usePointCloudStore } from './stores/pointCloud'

const store = usePointCloudStore()
</script>

<template>
  <div class="app">
    <Sidebar />
    <main class="viewer">
      <PointCloudViewer />
    </main>
  </div>
</template>

<style>
.app {
  display: flex;
  width: 100%;
  height: 100%;
  background: #1a1a1a;
  color: #fff;
}
.viewer {
  flex: 1;
  position: relative;
}
</style>
