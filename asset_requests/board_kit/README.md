# Map decoration kit

Small pieces of art that the game (and the map editor) arranges into each map's board, instead of one painted picture per map. Replace a placeholder by saving your art over the same file at the same size. Each piece has its own description file in this folder.

## How the board is built

1. **Fields** (`assets/board_kit/fields/`, 32x32 seamless): painted over the board in the map editor on a 4 px grid, in any shape (not tied to properties).
2. **Lines** (`assets/board_kit/lines/`): roads, rails, creeks, fences and tree lines run along property borders. Each line type has 3 pieces: `_straight` (16x8, left-right, repeats), `_corner` (8x8, right edge to bottom edge) and `_cross` (8x8, all four edges). The game rotates them for other directions.
3. **Props** (`assets/board_kit/props/`): buildings, trees, animals and vehicles placed on top. Flat props (ponds, corrals, arenas) go down first; standing props are sorted so lower ones overlap higher ones.
4. The game then draws property borders, owner tints, drill holes, derricks and pipelines on top.

## Drawing rules for every piece

- View: top-down with a slight 3/4 tilt (you see roofs and a sliver of the south-facing wall), like the farm buildings on a 1970s board game. Light from the top-left; draw a soft shadow down-right inside the canvas (semi-transparent dark brown). Crisp pixels, no anti-aliasing, warm dusty mid-century palette.
- Scale: one drill-site cell is 12x12 px (10x10 on 5-6 player maps). A small house is about one cell.
- Props stand on the bottom-center of their canvas. Keep their base inside the listed footprint: the map keeps drill sites out of the footprint, but roofs, tree crowns and towers may rise above it.
- Never draw an oil derrick or pump jack: derricks are game pieces, and decoration must not look like one.
- No readable text on signs (the fonts are drawn by the game).

## Fields (32x32)

| File | What |
|---|---|
| `fields/dirt.png` | Bare dirt |
| `fields/plowed_h.png` | Plowed rows (east-west) |
| `fields/plowed_v.png` | Plowed rows (north-south) |
| `fields/wheat.png` | Wheat |
| `fields/cotton.png` | Cotton |
| `fields/corn.png` | Corn |
| `fields/pasture.png` | Green pasture |
| `fields/hay_meadow.png` | Hay meadow |
| `fields/dry_grass.png` | Dry grass |
| `fields/scrub.png` | Scrub land |
| `fields/caliche.png` | Caliche |
| `fields/red_clay.png` | Red clay |
| `fields/sand.png` | Sand |
| `fields/cracked_mud.png` | Cracked mud |
| `fields/mud.png` | Wet mud |
| `fields/marsh.png` | Marsh grass |
| `fields/rice_paddy.png` | Rice paddy |
| `fields/pine_floor.png` | Pine clearing |
| `fields/orchard.png` | Orchard |
| `fields/town_lot.png` | Town lot |

## Lines (each: `_straight` 16x8, `_corner` 8x8, `_cross` 8x8)

| Files | What |
|---|---|
| `lines/dirt_road_*.png` | Dirt road |
| `lines/shell_road_*.png` | Shell road |
| `lines/paved_road_*.png` | Paved road |
| `lines/railroad_*.png` | Railroad |
| `lines/creek_*.png` | Creek |
| `lines/fence_*.png` | Barbed-wire fence |
| `lines/tree_line_*.png` | Tree line |

## Props

| File | Size | Footprint | Group | What |
|---|---|---|---|---|
| `props/farmhouse.png` | 16x16 | 14x10 | farm | Farmhouse |
| `props/small_house.png` | 12x12 | 10x8 | farm | Small house |
| `props/shack.png` | 8x8 | 8x6 | farm | Shack |
| `props/abandoned_house.png` | 12x12 | 10x8 | farm | Abandoned house |
| `props/barn_red.png` | 16x16 | 16x10 | farm | Red barn |
| `props/barn_grey.png` | 16x16 | 16x10 | farm | Weathered barn |
| `props/silo.png` | 8x16 | 8x6 | farm | Silo |
| `props/grain_bins.png` | 16x12 | 16x8 | farm | Grain bins |
| `props/windmill.png` | 12x20 | 6x4 | farm | Windmill |
| `props/chicken_coop.png` | 8x8 | 8x6 | farm | Chicken coop |
| `props/outhouse.png` | 4x8 | 4x4 | farm | Outhouse |
| `props/haystack.png` | 8x8 | 8x6 | farm | Haystack |
| `props/hay_bales.png` | 12x8 | 12x6 | farm | Hay bales |
| `props/stock_tank.png` | 8x8 | 8x8 | farm | Stock tank |
| `props/water_trough.png` | 8x4 | 8x4 | farm | Water trough |
| `props/garden.png` | 12x8 | 12x8 | farm | Vegetable garden |
| `props/corral.png` | 24x16 | 24x16 | farm | Corral |
| `props/pond_small.png` | 16x12 | 16x12 | farm | Small pond |
| `props/pond_large.png` | 24x16 | 24x16 | farm | Large pond |
| `props/tractor.png` | 8x8 | 8x6 | vehicle | Tractor |
| `props/pickup_truck.png` | 12x8 | 12x6 | vehicle | Pickup truck |
| `props/wagon.png` | 8x8 | 8x6 | vehicle | Wagon |
| `props/sedan_black.png` | 12x8 | 12x6 | vehicle | Black sedan |
| `props/horse_trailer.png` | 12x8 | 12x6 | vehicle | Horse trailer |
| `props/longhorn.png` | 8x4 | 8x4 | animal | Longhorn |
| `props/cattle_herd.png` | 16x8 | 16x8 | animal | Cattle herd |
| `props/horses.png` | 12x8 | 12x8 | animal | Horses |
| `props/oak_tree.png` | 12x12 | 4x4 | plant | Live oak |
| `props/cottonwood.png` | 12x16 | 4x4 | plant | Cottonwood |
| `props/dead_tree.png` | 8x12 | 4x4 | plant | Dead tree |
| `props/pine_tree.png` | 8x16 | 4x4 | plant | Pine tree |
| `props/pine_cluster.png` | 16x16 | 12x6 | plant | Pine stand |
| `props/mesquite.png` | 8x8 | 6x4 | plant | Mesquite bush |
| `props/sagebrush.png` | 4x4 | 4x4 | plant | Sagebrush |
| `props/prickly_pear.png` | 8x8 | 6x4 | plant | Prickly pear |
| `props/palm_tree.png` | 8x16 | 4x4 | plant | Palm tree |
| `props/bent_palm.png` | 12x16 | 4x4 | plant | Storm-bent palm |
| `props/reeds.png` | 8x8 | 6x4 | plant | Reeds |
| `props/tumbleweed.png` | 4x4 | 4x4 | plant | Tumbleweed |
| `props/rocks.png` | 8x4 | 8x4 | plant | Rocks |
| `props/boulder.png` | 8x8 | 8x6 | plant | Boulder |
| `props/stumps.png` | 8x4 | 8x4 | plant | Stumps |
| `props/dune.png` | 16x8 | 16x8 | plant | Sand dune |
| `props/bones.png` | 8x4 | 8x4 | plant | Cattle skull |
| `props/general_store.png` | 16x16 | 16x10 | town | General store |
| `props/saloon.png` | 16x16 | 16x10 | town | Saloon |
| `props/church.png` | 12x20 | 12x10 | town | Church |
| `props/courthouse.png` | 32x24 | 32x16 | town | Courthouse |
| `props/bank_building.png` | 16x16 | 16x10 | town | Bank |
| `props/rail_depot.png` | 24x12 | 24x8 | town | Rail depot |
| `props/water_tower.png` | 12x20 | 8x4 | town | Water tower |
| `props/gas_station.png` | 16x12 | 16x8 | town | Gas station |
| `props/house_row.png` | 24x12 | 24x8 | town | Row of houses |
| `props/tent.png` | 8x8 | 8x6 | town | Tent |
| `props/tent_camp.png` | 16x12 | 16x8 | town | Tent camp |
| `props/street_lamp.png` | 4x12 | 4x4 | town | Street lamp |
| `props/fair_tent.png` | 16x12 | 16x8 | town | Fair tent |
| `props/ferris_wheel.png` | 24x24 | 12x6 | town | Ferris wheel |
| `props/billboard.png` | 12x8 | 12x4 | town | Billboard |
| `props/storage_tank.png` | 12x12 | 12x10 | industry | Oil storage tank |
| `props/tank_farm.png` | 24x16 | 24x14 | industry | Tank farm |
| `props/pipe_rack.png` | 12x8 | 12x6 | industry | Pipe stack |
| `props/sawmill.png` | 24x16 | 24x10 | industry | Sawmill |
| `props/log_pile.png` | 12x8 | 12x6 | industry | Log pile |
| `props/refinery_unit.png` | 16x24 | 16x10 | industry | Refinery unit |
| `props/flare_stack.png` | 4x16 | 4x4 | industry | Flare stack |
| `props/warehouse.png` | 24x16 | 24x12 | industry | Warehouse |
| `props/pump_station.png` | 16x12 | 16x8 | industry | Pumping station |
| `props/rodeo_arena.png` | 32x24 | 32x24 | rodeo | Rodeo arena |
| `props/bucking_chutes.png` | 16x8 | 16x6 | rodeo | Bucking chutes |
| `props/bleachers.png` | 16x8 | 16x6 | rodeo | Bleachers |
| `props/bayou_inlet.png` | 24x16 | 24x16 | coast | Bayou inlet |
| `props/shrimp_boat.png` | 16x8 | 16x6 | coast | Shrimp boat |
| `props/dock.png` | 24x8 | 24x8 | coast | Dock |
| `props/fish_camp.png` | 12x12 | 10x8 | coast | Fish camp |
| `props/beached_boat.png` | 12x8 | 12x6 | coast | Beached boat |
| `props/debris.png` | 8x8 | 8x6 | coast | Storm debris |

## Themes

Each campaign level uses a theme (`board_theme` in `data/campaign.json`) that picks its fields, lines, building groups and scattered props. The map editor's Auto-fill uses the same themes.

- **Farm country** (`farm`): fields wheat, cotton, corn, plowed_h, plowed_v, pasture, orchard, hay_meadow; groups farmstead, small_farm, pond.
- **Boomtown edge** (`boomtown_edge`): fields dry_grass, dirt, plowed_h, hay_meadow, scrub; groups homestead, farmstead, oil_camp.
- **Dry creek** (`dry_creek`): fields cracked_mud, dry_grass, dirt, scrub; groups abandoned, homestead.
- **Cattle ranch** (`ranch`): fields pasture, hay_meadow, dry_grass, pasture; groups ranch, pond.
- **Boomtown** (`boomtown`): fields town_lot, town_lot, mud, dirt; groups town_block, church_lot, depot, oil_camp, tank_farm.
- **Wildcat camp vs. ranch** (`split`): fields scrub, dirt, pasture, hay_meadow; groups oil_camp, ranch.
- **Piney woods** (`piney`): fields pine_floor, red_clay, pine_floor, pasture; groups sawmill, small_farm.
- **County seat** (`county_seat`): fields cotton, corn, town_lot, pasture, plowed_v; groups courthouse, town_block, church_lot, small_farm.
- **Rail spur farms** (`rail_farms`): fields cotton, corn, pasture, plowed_h, wheat; groups depot, farmstead, small_farm, tank_farm.
- **Rainy farms** (`rainy_farms`): fields mud, pasture, plowed_h, corn; groups small_farm, pond.
- **Old farm county** (`old_farm`): fields wheat, cotton, corn, plowed_h, plowed_v, orchard, pasture, hay_meadow; groups farmstead, small_farm, big_pond, pond.
- **West Texas flats** (`west_texas`): fields caliche, scrub, dry_grass, scrub; groups homestead, oil_camp, rodeo.
- **Rodeo country** (`rodeo`): fields dry_grass, pasture, dirt, hay_meadow; groups rodeo, ranch.
- **Caprock** (`caprock`): fields caliche, red_clay, scrub, red_clay; groups homestead, oil_camp.
- **Pipeline country** (`pipeline_country`): fields scrub, dirt, dry_grass, caliche; groups tank_farm, oil_camp.
- **Sandstorm** (`sandstorm`): fields sand, sand, scrub, dirt; groups abandoned, homestead.
- **Gulf coast farms** (`gulf_farms`): fields rice_paddy, marsh, pasture, sand, rice_paddy; groups fish_camp, small_farm, pond.
- **Industrial port** (`port`): fields town_lot, town_lot, marsh, dirt; groups refinery, tank_farm, bank, fish_camp.
- **Flooded plain** (`flood`): fields mud, marsh, mud, rice_paddy; groups storm_wreck, fish_camp, big_pond.
- **All of Texas** (`quilt`): fields pasture, pine_floor, scrub, marsh, wheat, caliche, cotton, red_clay; groups farmstead, ranch, sawmill, oil_camp, fish_camp, tank_farm.
- **City edge** (`city_edge`): fields town_lot, pasture, wheat, orchard, town_lot; groups fair, refinery, gas_station, town_block, bank.
