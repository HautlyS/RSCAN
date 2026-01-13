# RSCAN - Building Digitalization App Architecture

## Overview

RSCAN is an iOS XR-compatible scanning application (Polycam-style) for complete building digitalization including:
- Interior room scanning with furniture detection
- Exterior building capture
- Roof reconstruction with missing piece completion
- Room segmentation for organized 3D models

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         RSCAN SYSTEM                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    iOS SCANNING APP                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │   │
│  │  │   ARKit     │  │  RoomPlan   │  │   LiDAR Scanner     │  │   │
│  │  │  Session    │  │    API      │  │   (Depth Data)      │  │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │   │
│  │         │                │                     │             │   │
│  │         └────────────────┼─────────────────────┘             │   │
│  │                          ▼                                   │   │
│  │              ┌───────────────────────┐                       │   │
│  │              │   Point Cloud Buffer  │                       │   │
│  │              │   + RGB Textures      │                       │   │
│  │              └───────────┬───────────┘                       │   │
│  │                          │                                   │   │
│  │                          ▼                                   │   │
│  │              ┌───────────────────────┐                       │   │
│  │              │   Export: PLY/USD/E57 │                       │   │
│  │              └───────────────────────┘                       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              TAURI DESKTOP COMPANION (Rust + Vue.js)         │   │
│  │  ┌─────────────────────────────────────────────────────────┐│   │
│  │  │                 PROCESSING PIPELINE                      ││   │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ ││   │
│  │  │  │  Import  │→ │  Clean   │→ │  Mesh    │→ │  Segment │ ││   │
│  │  │  │  Point   │  │  Filter  │  │  Recon   │  │  Rooms   │ ││   │
│  │  │  │  Cloud   │  │  Denoise │  │  struct  │  │          │ ││   │
│  │  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘ ││   │
│  │  │                                              │           ││   │
│  │  │                                              ▼           ││   │
│  │  │                              ┌──────────────────────────┐││   │
│  │  │                              │   Roof Reconstruction    │││   │
│  │  │                              │   + Missing Completion   │││   │
│  │  │                              └──────────────────────────┘││   │
│  │  └─────────────────────────────────────────────────────────┘│   │
│  │                                                              │   │
│  │  ┌─────────────────────────────────────────────────────────┐│   │
│  │  │                    VUE.JS 3 FRONTEND                     ││   │
│  │  │  • 3D Viewer (Three.js)  • Room Navigator               ││   │
│  │  │  • Export Options        • Processing Controls          ││   │
│  │  └─────────────────────────────────────────────────────────┘│   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Technology Stack

### iOS App (Swift)
| Component | Technology | Purpose |
|-----------|------------|---------|
| AR Framework | ARKit | World tracking, plane detection |
| Room Scanning | RoomPlan API | Parametric room models |
| Depth Capture | LiDAR Scanner | Dense point clouds |
| 3D Export | ModelIO, RealityKit | USD/USDZ/PLY export |

### Desktop App (Tauri v2)
| Component | Technology | Purpose |
|-----------|------------|---------|
| Backend | Rust | Point cloud processing, algorithms |
| Frontend | Vue.js 3 + TypeScript | UI, 3D visualization |
| 3D Rendering | Three.js | WebGL point cloud/mesh viewer |
| IPC | Tauri Commands | Rust ↔ Frontend communication |

### Processing Libraries (Rust)
| Library | Purpose |
|---------|---------|
| `nalgebra` | Linear algebra, transformations |
| `kiss3d` / `three-d` | 3D rendering |
| `ply-rs` | PLY file parsing |
| `rayon` | Parallel processing |
| Custom | Poisson reconstruction, RANSAC |

---

## References

- [Apple RoomPlan](https://developer.apple.com/augmented-reality/roomplan/)
- [ARKit Documentation](https://developer.apple.com/documentation/arkit)
- [Tauri v2 Mobile](https://v2.tauri.app/develop/plugins/develop-mobile/)
- [Open3D Surface Reconstruction](https://www.open3d.org/docs/latest/tutorial/Advanced/surface_reconstruction.html)
- [RoofDiffusion Paper](https://arxiv.org/abs/2404.09290)
