# Generated asset provenance

The September 6 template upgrade adds five original static images through GPT Image 2. The September 7 Mushies update adds Puff Bomb through GPT Image 2. Its latest built-in image_gen edit gives it a dark charcoal-plum body without limbs, dotted body seams or a belly patch; a second background-extraction pass supplies genuine alpha. Both exact edit prompts are retained in `generation-prompts/puff_bomb.txt`. Sources are kept here and runtime derivatives have explicit dimensions and processing. No localized text is baked into the assets.

| Asset | Source | Runtime | Processing |
| --- | --- | --- | --- |
| title | `title.png` | `assets/template/ui/title.webp` | opaque title plate; resize 1280×854 |
| pause | `pause.png` | `assets/template/ui/pause.webp` | alpha frame; 640×640 nine-slice |
| foreground | `foreground.png` | `assets/template/foregrounds/cabinet_trim.webp` | crop (0,705,1536,1024); 336×70; preserved 84 px end caps |
| cursor | `cursor.png` | `assets/template/ui/cursor.png` | green-key cleanup, silhouette crop, 32×32; hotspot (6,2) |
| aim_cursor | `aim_cursor.png` | `assets/template/ui/aim_cursor.png` | alpha cleanup, silhouette crop, 32×32; hotspot (16,16) |
| puff_bomb | `puff_bomb.png` | `assets/template/bombs/puff_bomb.webp` | alpha bounding-box crop (165, 3, 1180, 1203) with 12 px padding; 433×512 quality-90 WebP; alpha below 20 removed; 52-point alpha silhouette, 0.97 collider inset |

The title, cursor and aim-cursor prompt files use the current Mushies name. They are marked as brand-normalized transcriptions; their exact original generation prompts remain at the Git references recorded in `provenance.json`. Those three images have not been regenerated. Concept-board title edits have separate records in `concepts/provenance.json`.

The eleven original plushies and arcade background are retained from the existing authored game. Their baseline records identify GPT Image 2. The original generation prompts were not stored in that baseline; this revision does not fabricate them. Source masters, normalized crops, original outlines and baseline commit provenance are preserved in `provenance.json`.

The boot icon is a resized PNG derivative of the original chick. Custom pointer/aim cursors are green-key/alpha cleaned, cropped and resized; hotspots are documented above. The pause frame uses real alpha outside its intended linen/velvet panel. The foreground preserves the cushion ends while its plain center padding stretches.

Nunito supplies English body text and Noto Sans SC the Simplified Chinese body text; Cherry Bomb One, Fredoka and ZCOOL KuaiLe supply the logo, headings and large numbers. All are SIL Open Font License 1.1 fonts shipped as subset WOFF2, each beside its `<Family>-OFL.txt` license under `assets/template/fonts/`. The web loader keeps its own separately pinned loader subset. Fonts are not represented as generated illustrations.

New images were visually inspected as generated and in native UI captures. Original plushies retain their silhouette geometry; every tier passes collider/visual tests. Diagnostic contact sheets and native landscape/portrait captures are build outputs, not runtime art.
