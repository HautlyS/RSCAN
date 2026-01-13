import { defineStore } from 'pinia'
import { invoke } from '@tauri-apps/api/core'

interface LoadResult {
  point_count: number
  has_colors: boolean
  bounds: [[number, number, number], [number, number, number]]
}

interface ProcessOptions {
  voxel_size?: number
  remove_outliers: boolean
  outlier_k?: number
  outlier_std?: number
}

export const usePointCloudStore = defineStore('pointCloud', {
  state: () => ({
    loaded: false,
    pointCount: 0,
    hasColors: false,
    bounds: null as LoadResult['bounds'] | null,
    processing: false,
    status: '',
  }),

  actions: {
    async loadFile(path: string) {
      try {
        const result = await invoke<LoadResult>('load_point_cloud', { path })
        this.loaded = true
        this.pointCount = result.point_count
        this.hasColors = result.has_colors
        this.bounds = result.bounds
      } catch (e) {
        console.error('Failed to load:', e)
        throw e
      }
    },

    async process(options: ProcessOptions) {
      this.processing = true
      this.status = 'Processing...'
      try {
        const count = await invoke<number>('process_point_cloud', { options })
        this.pointCount = count
        this.status = `Done: ${count} points`
      } catch (e) {
        this.status = `Error: ${e}`
      } finally {
        this.processing = false
      }
    },
  },
})
