class_name RoadsideGame
extends PlugGame
## The little skill games for the roadside fixes with no game of their own in the shed, run like
## the plug kit's (see PlugGame: find the spot along a strip, then hold the tool steady on it as
## it drifts). How steadily it was held is quality(); under Roadside's 0.25 it didn't take.
##   fuse    sweep the test lamp along the fuse box under the seat: it glows by the blown one;
##           then push the new fuse in square.
##   chain   find the split link's open end on the spare chain's run; then press its clip on.
##   lever   find the pivot hole by feel; then hold the new lever on it while the bolt goes in.

const KINDS := {
	"fuse": {"find": "FIND THE BLOWN FUSE", "fix": "PUSH THE NEW FUSE IN",
		"find_hint": "Sweep the test lamp along the fuse box with the {aim}: hold it where it glows",
		"fix_hint": "Keep the fuse square on its socket with the {aim}", "tool": "test lamp", "score": "fuse"},
	"chain": {"find": "FIND THE SPLIT LINK", "fix": "PRESS THE CLIP ON",
		"find_hint": "Run the pliers along the chain with the {aim}: hold them where the link's open",
		"fix_hint": "Keep the pliers on the clip with the {aim}", "tool": "pliers", "score": "clip"},
	"lever": {"find": "LINE UP THE PIVOT", "fix": "HOLD IT WHILE THE BOLT GOES IN",
		"find_hint": "Feel for the pivot hole with the {aim}: hold the lever where it drops in",
		"fix_hint": "Keep the lever on the pivot with the {aim}", "tool": "lever", "score": "fit"},
}

var kind := "fuse"


func _init(seed_value := 0, game_kind := "fuse") -> void:
	super(seed_value)
	kind = game_kind if KINDS.has(game_kind) else "fuse"


func label(key: String) -> String:
	return str(KINDS[kind].get(key, ""))


## The Roadside fault a game kind is for, and back.
static func for_fault(fault: String) -> String:
	return {"chain_snap": "chain", "lever": "lever", "fuse": "fuse"}.get(fault, "")
