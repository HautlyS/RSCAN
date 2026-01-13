<script setup lang="ts">
import { ref } from 'vue'
import { open } from '@tauri-apps/plugin-dialog'
import { usePointCloudStore } from '../stores/pointCloud'

const store = usePointCloudStore()
const voxelSize = ref(0.01)

async function openFile() {
  const path = await open({
    filters: [{ name: 'Point Cloud', extensions: ['ply', 'e57'] }],
  })
  if (path) await store.loadFile(path as string)
}

function processCloud() {
  store.process({
    voxel_size: voxelSize.value,
    remove_outliers: true,
    outlier_k: 20,
    outlier_std: 2.0,
  })
}
</script>

<template>
  <aside class="sidebar">
    <h2>RSCAN</h2>
    
    <section>
      <button @click="openFile">Open Point Cloud</button>
      <div v-if="store.loaded" class="info">
        <p>Points: {{ store.pointCount.toLocaleString() }}</p>
        <p>Colors: {{ store.hasColors ? 'Yes' : 'No' }}</p>
      </div>
    </section>

    <section v-if="store.loaded">
      <h3>Process</h3>
      <label>
        Voxel Size
        <input type="number" v-model.number="voxelSize" step="0.001" min="0.001" />
      </label>
      <button @click="processCloud" :disabled="store.processing">
        {{ store.processing ? 'Processing...' : 'Process' }}
      </button>
      <p class="status">{{ store.status }}</p>
    </section>
  </aside>
</template>

<style scoped>
.sidebar {
  width: 280px;
  padding: 16px;
  background: #252525;
  border-right: 1px solid #333;
  display: flex;
  flex-direction: column;
  gap: 16px;
}
h2 { font-size: 1.5rem; color: #4fc3f7; }
h3 { font-size: 1rem; margin-bottom: 8px; }
section { display: flex; flex-direction: column; gap: 8px; }
button {
  padding: 10px;
  background: #4fc3f7;
  color: #000;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-weight: bold;
}
button:disabled { opacity: 0.5; cursor: not-allowed; }
button:hover:not(:disabled) { background: #81d4fa; }
label { display: flex; flex-direction: column; gap: 4px; font-size: 0.9rem; }
input {
  padding: 8px;
  background: #333;
  border: 1px solid #444;
  border-radius: 4px;
  color: #fff;
}
.info { font-size: 0.85rem; color: #aaa; }
.status { font-size: 0.8rem; color: #888; }
</style>
