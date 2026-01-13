<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { usePointCloudStore } from '../stores/pointCloud'

const container = ref<HTMLDivElement>()
const store = usePointCloudStore()

let scene: THREE.Scene
let camera: THREE.PerspectiveCamera
let renderer: THREE.WebGLRenderer
let controls: OrbitControls
let points: THREE.Points | null = null

onMounted(() => {
  if (!container.value) return

  scene = new THREE.Scene()
  scene.background = new THREE.Color(0x1a1a1a)

  camera = new THREE.PerspectiveCamera(60, container.value.clientWidth / container.value.clientHeight, 0.1, 1000)
  camera.position.set(5, 5, 5)

  renderer = new THREE.WebGLRenderer({ antialias: true })
  renderer.setSize(container.value.clientWidth, container.value.clientHeight)
  container.value.appendChild(renderer.domElement)

  controls = new OrbitControls(camera, renderer.domElement)
  controls.enableDamping = true

  // Grid helper
  scene.add(new THREE.GridHelper(10, 10, 0x444444, 0x222222))

  // Axes helper
  scene.add(new THREE.AxesHelper(2))

  animate()

  window.addEventListener('resize', onResize)
})

function animate() {
  requestAnimationFrame(animate)
  controls.update()
  renderer.render(scene, camera)
}

function onResize() {
  if (!container.value) return
  camera.aspect = container.value.clientWidth / container.value.clientHeight
  camera.updateProjectionMatrix()
  renderer.setSize(container.value.clientWidth, container.value.clientHeight)
}

// Watch for bounds changes to center camera
watch(() => store.bounds, (bounds) => {
  if (!bounds) return
  const center = new THREE.Vector3(
    (bounds[0][0] + bounds[1][0]) / 2,
    (bounds[0][1] + bounds[1][1]) / 2,
    (bounds[0][2] + bounds[1][2]) / 2,
  )
  controls.target.copy(center)
  const size = Math.max(
    bounds[1][0] - bounds[0][0],
    bounds[1][1] - bounds[0][1],
    bounds[1][2] - bounds[0][2],
  )
  camera.position.copy(center).add(new THREE.Vector3(size, size, size))
})
</script>

<template>
  <div ref="container" class="viewer-container">
    <div v-if="!store.loaded" class="placeholder">
      <p>Open a point cloud file to begin</p>
    </div>
  </div>
</template>

<style scoped>
.viewer-container {
  width: 100%;
  height: 100%;
  position: relative;
}
.placeholder {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #666;
  font-size: 1.2rem;
}
</style>
