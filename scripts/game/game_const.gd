class_name GameConst
extends RefCounted
## Shared constants for the rules engine and presentation.

const MAX_PLAYERS: int = 6

const SITE_OPEN: int = 0
const SITE_OIL: int = 1
const SITE_DRY: int = 2
const SITE_BURNED: int = 3

const DEPTH_SHALLOW: int = 0
const DEPTH_MEDIUM: int = 1
const DEPTH_DEEP: int = 2
const DEPTH_DRY: int = -1

const DEPTH_NAMES: Array[String] = ["Shallow", "Medium", "Deep"]
## Base drilling cost by depth index; dry holes cost the same as deep.
const BASE_DRILL_COST: Array[int] = [2000, 4000, 6000]
const DRY_HOLE_COST: int = 6000

const PHASE_DRAFT: String = "draft"
const PHASE_CARD: String = "card"
const PHASE_ACTIONS: String = "actions"
## A Blowout Fire was drawn: the player must pick which of their wells to cap.
const PHASE_FIRE: String = "fire"
const PHASE_GAME_OVER: String = "game_over"
## Original rules: the bank auctions a bankrupt player's properties one at a time.
const PHASE_AUCTION: String = "auction"

## Plot owner value for land nobody bought at a bankruptcy auction: closed for the rest of the game.
const PLOT_CLOSED: int = -2

## Original-rules numbers (Classic mode), from the 1974 rules booklet.
const ORIG_ROYALTY_PER_DERRICK: Array[int] = [1000, 3000, 5000] # 1, 2 or 3 pipelines into one property
const ORIG_PIPELINE_MAX_FROM_PLOT: int = 3
const ORIG_WELL_VALUE: int = 4000 # producing well, final scoring
const ORIG_NO_SITE_PENALTY: int = 10000 # must drill but no empty holes
const ORIG_BID_STEP: int = 500

const PIPELINE_MAX_LEVEL: int = 3
## Producing wells required on the source plot for pipeline level 1/2/3.
const PIPELINE_WELLS_REQUIRED: Array[int] = [4, 5, 6]
## Royalty multiplier per pipeline level (1/2/3): each upgrade pays much more, like Classic's
## $1k/$3k/$5k per derrick.
const PIPELINE_LEVEL_MULT: Array[int] = [1, 3, 5]

## Company colors, mid-century paint-can palette.
const PLAYER_COLORS: Array[Color] = [
	Color("c8402e"), # Barn red
	Color("2f5d8a"), # Ford blue
	Color("e8dcc0"), # Cream
	Color("e0a826"), # Mustard
	Color("4f7d3a"), # Sage green
	Color("7a4a8c"), # Plum
]
const PLAYER_COLOR_NAMES: Array[String] = ["Red", "Blue", "Cream", "Mustard", "Green", "Plum"]

const AI_EASY: int = 0
const AI_MEDIUM: int = 1
const AI_HARD: int = 2
const AI_LEVEL_NAMES: Array[String] = ["Easy", "Medium", "Hard"]

## Original plot names (Texas-flavored, invented for this game).
const PLOT_NAMES: Array[String] = [
	"Mesquite Flats", "Caddo Bend", "Sabine Draw", "Pecos Hollow", "Red Mule Tract",
	"Bluebonnet Rise", "Cotton Gin Lot", "Dry Creek", "Juniper Ridge", "Longhorn Pasture",
	"Saltgrass Bottom", "Coyote Wells", "Tin Roof Acres", "Harlan Ranch", "Sweetwater Lease",
	"Buzzard Butte", "Prairie Dog Town", "Rattler Gulch", "Widow Pratt's Field", "Windmill Section",
	"Caprock Strip", "Brazos Bottoms", "Copperhead Hill", "Goliad Spread",
]
