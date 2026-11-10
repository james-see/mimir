# Mimir Head Asset Pipeline

How `Assets/Head.usdz` gets made — and how to make a better one. The app runs
without it (SceneKit falls back to the placeholder primitive head
automatically); drop a valid USDZ at `Assets/Head.usdz` and it upgrades on
the next build. `HeadAssetValidationTests` asserts the morph targets the
viseme map requires.

## What the renderer needs

- A head (neck-up is fine) in **USDZ**, roughly life-proportioned, facing +Z.
- An `SCNMorpher` on the face mesh with morph targets named per the ARKit
  blend shape conventions. **Minimum set** the viseme map drives:

  | morph | visemes |
  |---|---|
  | `jawOpen` | all vowels, th, kg, l, r |
  | `mouthClose` | m, b, p |
  | `mouthFunnel` | oh, oo, r |
  | `mouthSmileLeft` / `mouthSmileRight` | ee, sz, l |
  | `tongueOut` | th |
  | `eyeBlinkLeft` / `eyeBlinkRight` | idle blink layer |
  | `browInnerUp` | thinking/listening posture |

  The validator test is the source of truth (`VisemeMorphMap.referencedMorphNames`).

## Route A — Ready Player Me (fastest realistic result, ~15 min)

1. Go to https://readyplayer.me and create an avatar (free account).
   Full-body or half-body both work; we'll keep the head.
2. Download the GLB **with ARKit morphs**. The pattern is:
   `https://models.readyplayer.me/<avatarID>.glb?morphTargets=ARKit&textureAtlas=1024`
   (Get the exact URL from your Hub → 3D preview → "Copy avatar link".)
   Licensing: avatars you create are free to use with attribution
   ("Avatar by Ready Player Me") — keep the credit line in the README.
3. Convert GLB → USDZ with Blender (headless):

   ```sh
   /opt/homebrew/bin/blender -b -P tools/glb-to-usdz.py -- input.glb Assets/Head.usdz
   ```

   `tools/glb-to-usdz.py` (create it when needed): imports GLB, deletes body
   meshes below the neck, keeps all shape keys (Blender imports GLTF
   morphTargets as shape keys; USD export preserves them as blend shapes),
   then `bpy.ops.wm.usd_export(filepath=..., export_blendshapes=True,
   export_textures=True)`.

4. Run the validator: `swift test --package-path MimirCore --filter HeadAssetValidation`.

## Route B — MakeHuman (fully CC0, more manual)

1. `brew install --cask makehuman` — MakeHuman Community Edition (CC0 output).
2. In MakeHuman: pick a face, export glTF (with facial shape keys if the
   plugin offers them) or Collada.
3. In Blender: import, then add the missing blend shapes by hand as shape
   keys (jaw/mouth targets are the minimum) — sculpt mode on a duplicated
   shape per target. This is the time-consuming part (1–2 h).
4. Convert with the same Blender script as Route A.

## Provenance

Record the chosen asset's origin + license here when Head.usdz lands:

- Source:
- License:
- Attribution string for README:
