# Torque Shed

A co-op motorbike restoration game: walk round the shed with friends, strip rusty project bikes down, clean and restore every part, fit better ones, then ride them out of the roller door.

Current milestone, **The Shed**: a snug first-person workshop with four bike bays, a workbench, a wheeled engine stand, a parts computer that orders parts and equipment, a parts washer, a repair bench, posters, seats and TVs to buy, wall dashboards for every bike and the crew, a radio everyone hears, a wash bay with a pressure washer beside the shed, and the riding map outside. Bikes are made of 41 parts from 35 kinds (stands, headlight, horn, ECU, panniers, top box, fog lights, fairing and mirrors are optional), at least 5 of each and 16 wheels, plus petrol, oil, brake fluid and chain lube, and every part has its own colour, rust, dirt and wear. Everything you do earns XP towards levels, tool upgrades and a skills tree, and a wage; the business buys parts and project bikes, sells parts and bikes, and can borrow from the bank (see Money below), and the garage's money buys upgrades to the shed itself.

### What a bike is made of

| Area | Parts |
| --- | --- |
| Chassis | Frame, front fork, rear suspension (type, travel, bump and rebound damping, adjustability) |
| Wheels | Front and rear wheel (spoked, wire, cast, carbon; 17" to 21"), front and rear tyre (type, compound, width) |
| Brakes, front and rear | Disc (type, diameter), caliper (pistons), pads (compound), master cylinder (axial or radial) |
| Body and controls | Fuel tank (capacity, style), saddle, handlebars (style, width), dashboard, headlight (style, lumens), horn (10 types, from a disc horn to a train horn or a musical one), fog lights |
| Electronics | ECU (stock, remap, ABS, sport with traction control, race with all of it): more power and revs, and rider aids for ABS, traction control, stability and anti-wheelie |
| Tail and front | Tail unit (6 kinds: long classic mudguard, café racer hump, scrambler loop, sport tail tidy, bobber chopped fender, enduro high fender), which carries the rear light, mudguard and number plate; fairing (headlight flyscreen, bikini, half, touring with a tall screen, full race in fibreglass or carbon), which cuts drag for a higher top speed but adds weight; mirrors (round chrome, bar-end, sport stalk, wide touring, fairing-mount) |
| Luggage | Panniers and top boxes; they add drag |
| Stands | Side stand (length, lean), centre stand (lift). Without either, a bike left anywhere but a paddock stand falls over |
| Fluids | Petrol in the tank, oil in the engine, brake fluid in each master cylinder. Each has 3 grades and ages with use |
| Engine, built on the stand | Block (single, twin, parallel twin, V-twin, boxer, two-stroke or inline four; 50 to 1200 cc), cylinder head, fuel system, air filter, oil filter, spark plugs, cooling, gearbox |
| Drivetrain | Exhaust, sprockets, chain (slack and lube matter) |

Engine parts have to suit each other: one carb can't feed a big four, a race head needs a radiator, worn plugs misfire and a poor oil filter lets a tired engine wear faster. The bay screens list anything that doesn't suit.

## Playing

Unzip `TorqueShed-windows.zip` and run `TorqueShed.exe`. No install is needed.

**Saving**: the shed saves itself every minute, when you leave to the title and when you close the game, and the Esc menu has a **Save now** button. Everything is kept: the bikes and every part, where things were left (bikes out on the road included), equipment, the time of day and where you stood. The title screen's solo and host buttons **Continue** the saved shed; **New shed** starts again (after asking). In co-op the host's shed is the one saved. Saves live in `%APPDATA%\Godot\app_userdata\Torque Shed\saves`.

### In the shed

| Action | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Walk / look | W A S D / mouse | Left stick / right stick |
| Run | Shift | Left stick click |
| Crouch (low parts such as stands, oil filter and chain need it) | C or Ctrl | Right stick click |
| Pick a tool (hands, wrench, brush, grinder, spray can, pressure washer, spray gun, stopwatch) | 1-8, Q / E, mouse wheel | LB / RB |
| Work on what you're looking at, or put a held part down anywhere | Hold left mouse | Hold RT or A |
| Spray colour / finish (can or gun) | R or right mouse / T or the mouse back (side) button | X / B |
| Ping what you're looking at for the crew | G or middle mouse | D-pad right |
| Stopwatch start / stop (lap or reset: right mouse with the stopwatch out) | P | D-pad left |
| Name the bike you're looking at | N | |
| Roller door, shed lights (switches by the door); paint shop and storage room lights (switch inside each door) | F | Y |
| Dyno room: its lights and the cooling fan (switches inside its door), put on or hang up the ear defenders | F | Y |
| Sales office lights (switches by the foot of the stairs and at the top) | F | Y |
| Dyno room: strap the bike down (at each of the 4 posts), take the extraction hose off its hook and push it over the exhaust | Hold left mouse | Hold RT or A |
| Sandblaster: put your hands in the gloves / step back | F | Y |
| Sandblaster: blast where you aim / turn the engine | Hold left mouse / W A S D, or hold right mouse and move the mouse | Hold RT / left stick |
| Drain a fluid (holding a drain pan, empty can or bleed bottle); with the wrench at a chain, set its tension | Hold R or right mouse | Hold X |
| Get on a finished bike (tap), or wheel it about on foot (hold) | F | Y |
| Use the parts computer or the dyno desk, switch the radio on or off | F | Y |
| Sell a loose part or a whole bike (parts computer, Sell aisle); send money, take money out, loans (Esc, Money tab) | F at the computer / Esc | Y / Start |
| Talk to a customer waiting at reception (their offer card: Accept, Decline) | F | Y |
| Unpack a delivery box; take hold of or let go of equipment (posters, TVs and the whiteboard hang on the wall you look at) | F | Y |
| Carrying equipment: push it further away / pull it closer | Mouse wheel up / down (or Q / E) | LB / RB |
| Carrying equipment: snapping to walls and corners on or off | R or right mouse | X |
| Turn the part in your hands or the equipment you're carrying before you put it down (a quarter turn a press with snapping on; with it off, hold to turn it freely). Posters turn portrait or landscape | , / . (the < and > keys) | View (turns it right) |
| Scrap the equipment you're carrying or the part in your hands, for good: hold, then press again to confirm | Hold Delete, then Delete | Hold D-pad down, then D-pad down |
| Sit on a seat (tap), or move it (hold) | F | Y |
| Change radio station | Hold left mouse on the radio | Hold RT or A |
| Tyre changer: fit the tyre you're holding (keep the lever on the marker) | Hold left mouse, steer the lever with the mouse | Hold RT or A, steer with the right stick |
| Tyre changer: lever the old tyre off / lift the wheel off, tyre and all | Hold left mouse / hold right mouse | Hold RT or A / hold LT |
| TV or wall screen: next / previous channel | R or right mouse / T | X / B |
| Throw away or recycle a part (hold it, look at a bin) | Hold left mouse | Hold RT or A |
| Whiteboard: draw / rub out; pen colour, eraser, thickness; text; undo; wipe it all | Hold left / right mouse; 1-6, 7, wheel; T; Z; hold X | Hold RT / LT; B colour; LB / RB thickness; D-pad left undo |
| Whiteboard: add a picture from your PC; move a picture (again to put it down); size it; make a poster of the board | U; M; + / - (or the wheel while moving it); K | (no picture upload); D-pad up; LB / RB while moving it; D-pad down |
| Whiteboard: turn a picture (15 degrees a press with snapping on; hold to turn it freely with snapping off) | , / . while moving it or looking at it | View |
| Geometry mode: fit the parts of the bike you're looking at (again, or Esc, to leave) | F2 | |
| Geometry mode: select a part / drag a handle; orbit; pan; zoom | Left mouse; right drag; middle drag; wheel | |
| Geometry mode: move, rotate, scale handles; snap (hold); undo; reset the part | W, E, R; Ctrl; Z; Backspace | |
| Menu (your level, tool upgrades and skills are in its Character tab; change any key in its Key bindings tab) | Esc | Start |
| In menus and on the computers: move, press, back; next / previous tab or aisle | Mouse, Esc | D-pad or left stick, A, B; LB / RB |

**Building from scratch**: hold a frame and look at an empty bay floor (bay 4 is free in a new shed), then hold the work button to stand the frame up in the bay. Fit the fork, wheels, engine and the rest onto it from there. Taking the bare frame off again frees the bay.

Look at any part to see its spec, condition, rust, dirt, wear and colour. With your **hands** you take parts off (once unbolted and once the parts mounted on them are off), carry them, fit them and put them down anywhere: the floor, a bench top, a shelf or an engine stand. The **wrench** bolts and unbolts. The **brush** scrubs off dirt from every part around where it lands; the parts washer does it on its own. The **grinder and welder** restores rust and wear on a repair machine, every part on the machine at once. The **spray can** paints a part in the colour and finish shown above the tool bar (16 colours; gloss, matte, metallic flake, chrome or old patina); the part has to be free of rust first. Painting and chain lube are hand work: hold the button and sweep the can over the whole part. The panel shows how much is covered; missed patches make a patchy job and going over one spot too long leaves runs (or flings lube off), and the part's info shows how good the job was. Hold a part while looking at a bike or engine to see how fitting it would change power, top speed, weight and braking.

Chains stretch and lose their lube as you ride, faster off-road: crouch by the chain with the wrench and hold the second button to set the tension, and spray it with **chain lube** (hold the can, crouch, sweep it along the chain). A slack or dry chain wastes power and the bay screen says so.

**Fluids** come in containers from the parts computer. Hold one and look at a bike's tank, engine or brake master cylinder to pour it in; hold an empty container (jerry can, drain pan, bleed bottle) and hold the alt button to drain it out, then tip old fluid away at the general waste bin. Draining the oil means crouching under the bike. Low or old oil costs power and wears the engine, stale fuel loses power, and old brake fluid makes the brakes spongy. Bikes pick up dirt as they're ridden, more on the dirt road. Wheel a muddy bike into the **wash bay** beside the shed and use the **pressure washer** (tool 6). With your hands, look at a bike with a stand bolted on to put it on its side or centre stand.

### Tail units, fairings and mirrors

Every bike has a **tail unit** behind the seat: the rear light, the mudguard or hugger and the number plate in one part, so swapping it changes the look of the back end and where the rear light sits. It bolts to the frame and is needed to ride. Bikes from older saves get the one that suits them (a hump on a café seat, a tail tidy on a sports bike, a high fender on an enduro, a long mudguard on the rest).

A **fairing** is an extra, like panniers. It goes on over the headlight, so the headlight has to be fitted first and the fairing has to come off before the headlight can. Flyscreens and bikini fairings turn with the bars; the half, touring and race fairings are fixed to the frame. The bigger and sleeker it is, the less drag and the higher the top speed (a cracked or filthy one helps less), but it adds weight; the touring fairing's tall screen is calm but pushes a lot of air. New bikes come with theirs painted to match.

**Mirrors** bolt to the handlebars (take them off before the bars), except fairing-mount mirrors, which need a fairing fitted and have to come off before it. They add a touch of drag. From the saddle the glass is a real mirror finish, catching the sky and what's round you.

All three are ordinary parts: order them at the parts computer (Bike aisle), clean, repair, paint and recycle them (steel guards go in metal recycling, plastic fenders and fairings in plastic, fibreglass and carbon ones and mirrors in general waste), and blueprints and saves keep them.

### Geometry mode and blueprints

The bikes are built from simple shapes, and on some of them a part doesn't sit quite right. **Geometry mode** lets you fix that yourself. Walk up to any bike, look at it and press **F2** (or use the Esc menu's **Geometry mode** button): the mouse is freed and the camera circles the bike. **Click any part** to select it (it glows), and a set of handles appears on it, like in Blender, Unreal or 3ds Max:

- **Move (W)**: red, green and blue arrows. Drag one to slide the part along X (across), Y (up) or Z (along the bike).
- **Rotate (E)**: three rings. Drag one to turn the part about that axis.
- **Scale (R)**: boxes on stalks stretch the part along its own X, Y or Z; the white box in the middle sizes it all over.

Hold **Ctrl** to snap (1 cm, 5 degrees, 5%), or tick "Always snap". **Z** undoes, **Backspace** resets the selected part (Reset all puts every part back). The panel shows exactly how far the part has been moved, turned and stretched. Right-drag orbits the camera round the bike, middle-drag pans and the wheel zooms, so you can see it from every side. Every part can be fitted, engine parts and all.

Changes are only for **that bike**: another bike with the same tank isn't touched. While you work they're a draft; **Save to this bike** keeps them (the host saves them with the shed, and everyone in co-op sees them, riding too). **Save + blueprint** saves them to the bike and also keeps the bike as a **blueprint** with the name you type: its parts, paint, each part's colour and finish, and your fit. Leaving with changes not saved asks whether to save or discard them. If you swap a part, the new one in that slot keeps the slot's fit. It's only looks: power, weight and handling don't change.

**Building from a blueprint**: in the Esc menu press **Build from blueprint** (the **Blueprints** tab, where blueprints can also be renamed and deleted). Pick a blueprint and an empty bay, and a flickering blue **hologram** of the finished bike appears in that bay. The bay screen shows the checklist of every part it needs (fitted, on order or needed, with what the parts still needed cost). **Order missing parts** (in the Blueprints tab, or **Order blueprint parts** on the parts computer) delivers what's still needed in boxes outside the roller door, in the blueprint's colours, each paid for by the business (it stops when the money runs out); if the delivery area fills up, bring boxes in and order again. Then put the frame on the bay's stand as for any scratch build: the bike takes the blueprint's name, paint and fit. Each ghost part vanishes as the real one goes on, and when the last part is on the hologram is gone. A project bike is never delivered into a bay with a hologram in it. Cancel in the Blueprints tab takes a hologram away.

### The sandblaster

A **sandblasting cabinet** (from the equipment page of the parts computer) strips rust and muck off a whole engine at once, its head, carbs and other ancillaries and all. The cabinets are big enough for the biggest engine with everything fitted, with room to turn it right round and tip it over. Take the engine off the stand and put it in the cabinet: it sits up on the turntable's post, drawn close up with its side covers, fins, bolts and float bowls. Look in through the glass and press F to put your hands in the gloves. One hand turns the engine (W A S D, the left stick, or hold right mouse and move the mouse); the other blasts wherever you aim (hold left mouse or RT). Thousands of fine grains of sand roar out of the nozzle, bounce off the engine and rattle down onto the grate, with dust kicking back off the metal. Wherever the jet goes, the rusty, painted surface turns to **satin bare metal** as you blast (aluminium on the castings, bare steel on steel parts), so the bits you've missed stay rusty and are easy to see. The cabinet has no light of its own: you see in by the shed's light.

While you work, a big readout shows a bar for the whole engine across the top and, down the side, each part with how much of it is bare and its **rust, dirt, wear and condition**, which change as you go (the crew sees them change too). When a part comes up bare there's a ding, a flash and "Bare metal!"; when the whole engine is done it says so, and you step back a moment later. Don't linger: blast one spot for too long and it goes dull and pitted, which wears the part. Press F to step back early: each part keeps what you've stripped off it, and pays XP like restoring on the grinder. One person at the gloves at a time; the crew sees the jet, the engine turning and the bare metal coming up.

Filters and spark plugs can be changed with the engine in the frame. Everything else on the engine needs it on the **engine stand**: take the exhaust and chain off, unbolt the engine, carry it to the stand, and work on it there. The **parts computer** orders any part (paid for from the business's account), equipment or a new project bike (also paid for), and its **Sell** aisle sells loose parts and whole bikes (see Money). Equipment comes in several models, with compact ones for a full shed: engine stands, shelving (four or five shelves that take parts anywhere on them), parts washers and repair machines (rated for 1 to 4 parts at full speed, some faster; see below), workbenches, wall posters, seats (stool, creeper, camp chair, bench, sofa) and big wall TVs with channels (see below). Parts marked "light" save weight; the bay screens show power to weight. Deliveries are left in the painted bay outside the roller door: parts come boxed (F unpacks a box, and boxed stock can go straight onto shelves), equipment comes ready to push in. Take hold of equipment with F, walk it where you want it (it turns with you) and press F to let go; whatever is on it goes with it. Posters, TVs and the whiteboard hang flat on whichever wall you look at. Write on a shelving unit's label plate by holding the work button on it. What you're looking at is described in the panel on the right. A bike can be ridden once every slot is filled and bolted up. What the speedo shows depends on the dashboard fitted.

### Placing equipment and parts

**Carrying equipment**: while you hold a piece of equipment, the mouse wheel (or LB / RB on a pad) pushes it further away from you, up to 3 m, or pulls it back in, so you can stand back and see the whole space you're putting it in. It stops short of walls. An outline on the floor shows exactly where it will go. While carrying, the wheel only moves the equipment; it doesn't change tool.

**Snapping** (on by default): equipment you put down turns square to the walls in quarter turns, and when one side comes close to a wall (or another piece of equipment) it slides flush against it; near two walls it goes tight into the corner. The outline turns blue and the panel says "Snapped flush to the wall" or "Snapped into the corner". Posters, TVs and the whiteboard slide into a corner that's close. Press R (right mouse, X on a pad) while carrying to turn snapping off or on; the Esc menu's Settings tab has the same switch. Yard kit outside never snaps.

**Benches, washers, repair machines and shelves take as many parts as fit**: there are no set places any more. Look anywhere on the top of the workbench, a bought bench, a parts washer, a repair machine or any shelf of a shelving unit with a part in your hands and put it down; it goes where you're looking, or the nearest clear spot to it, turned the way you face (and however you've turned it, see below). Each part takes up its real size, so you can line up a row of spark plugs, but a frame won't go in a small washer, and parts can't go on top of one another. The washer cleans everything in it and the grinder restores everything on the machine at once. Each machine works at full speed up to its rated number of parts (shown in its info); pile on more and each one goes a little slower, so a big load saves walking rather than time. Parts left in the old places in an older save stay where they were. Each shelf of a shelving unit works the same way: boxed stock and parts go anywhere along it, side by side, and parts left in a shelf's old numbered places in an older save stay just where they were.

**Turning things before you put them down**: with a part in your hands or a piece of equipment in your arms, press , or . (the < and > keys; View on a pad) to turn it left or right. With snapping on each press is a quarter turn; with snapping off a press nudges it and holding the key turns it smoothly, to any angle. The outline on the floor (or on the bench or shelf) shows where it'll go and which way round, red if it won't fit there, and the panel shows how far it's turned. It's put down that way on the floor, a bench, a washer, a repair machine or a shelf (square to a bench or shelf with snapping on). The next part you pick up starts the way you face.

**Scrapping kit and parts**: anything the bins won't take, or that you just don't want, can be scrapped. Carry a piece of equipment (F) or hold a part, and hold Delete (D-pad down on a pad) for a second: the panel asks if you're sure, and pressing Delete again within a few seconds scraps it for good. Whatever was on a shelf or bench you scrap goes on the floor where it stood, and the parts bolted to an engine or the tyre on a wheel go on the floor in front of you. The shed's own kit (the spray bay, the tyre changer and the whiteboard) can't be scrapped.

**The whiteboard can move**: press F on it to take it down and hang it on any wall, drawing and all. Where it hangs is kept with the shed; an older save has it in its usual place on the front wall.

**Delivery boxes** carry a shipping label from one of several made-up courier firms, with its logo, what's inside and a tracking number, on the lid (reading along the box's longer side) and on the front, so boxed stock on a shelf is easy to read. A box always comes from the same courier.

### The tyre changer

Tyres are changed on the **tyre changer**, built into the shed against the west wall past the end of the workbench. A tyre only goes on a rim it suits: each wheel takes a range of tyre widths and a tyre is made for certain rim sizes (17", 18", 21" and so on). Look at a wheel or tyre, here or on the parts computer, and its info says what it fits; if it doesn't fit, the changer tells you why.

To change one: unbolt the wheel and take it off the bike (any brake disc, caliper and pads on it come off first). The tyre comes off with it. Put the wheel on the changer. With empty hands, hold the work button to break the bead and lever the old tyre off, or hold the alt button to lift the wheel off whole. Then hold the new tyre and hold the work button: a marker runs round the rim, and you keep your tyre lever on it with the mouse (or right stick) until it has gone all the way round. Let go early and the bead slips off. How closely you follow it decides how well the bead is seated. A badly seated bead grips a little less and slowly lets the tyre down as you ride, and the part info and bay screen say so; do it again to put it right. Put the wheel back in the bike and it goes in with its new tyre. Everyone in the crew sees the changer turn while someone works on it, and a wheel left on it is kept with the shed.

The **parts computer** is split into three aisles, **Shed**, **Bike** and **Outdoors**, and has a search box that finds any part or piece of kit by name, kind or spec.

The **paint shop** is through the doorway in the east wall, between the parts computer and the parts washer; it's only reachable from inside the shed. It's a white-walled room with a ceiling of bright white **hexagon LED tiles** and its own light switch just inside the door. Its built-in **downdraft spray bay** has **ten hooks** on two rails, spaced so you can walk right round every part, with a walkway between the bay and the door. Hang parts on its hooks and sweep the **spray gun** over them. Hung parts swing, wire, hook and all, from the rail on the ceiling when you (or a mate) walk into them or spray them, and keep swinging for a few seconds before they settle. The gun's fine mist coats every part it passes, and the bay adds a better finish. With the can or the gun, the wet paint shows on the part as you go, so you can see the patches you've missed, and too much in one place runs. Fluid containers are see-through or have a sight strip, so you can see how full they are. In a shed saved before the paint shop got bigger, parts on the old booth's hooks stay on the same hooks.

The **storage room** is through the doorway in the west wall, by the back corner next to bay 1. It's an empty 8 by 8 metre room with its own lights and a switch just inside the door: room for three or more rows of shelving with aisles to walk between them. Push shelving in (F to take hold of it, F to let go) and line it up however you like.

**Ping** (G or middle mouse) outlines whatever you're pointing at, with your name and what it is, for everyone in the shed. The **stopwatch** is for timing whatever runs you dream up; it keeps running while you ride. Press N while looking at a bike to give it a name. The roller door and the shed lights have switches beside the door; the paint shop and the storage room each have their own light switch just inside their door. With the lights off the shed is properly dark, lit only by its TVs and screens, which light the room in front of them and nothing behind the wall. A day and night cycle runs outside; a whole day takes from 20 minutes up to 6 hours (2 hours by default), or you can fix the time of day, in the Esc menu.

**Bins and recycling**: three wheelie bins stand against the front wall, left of the roller door, under the end of the whiteboard. **General waste** (black) takes anything, and it's where you tip old fluid out of a can. **Plastic** recycling (blue) takes oil and brake fluid bottles, drain pans, bleed bottles, plastic cases and top boxes. **Metal** recycling (green) takes frames, engines, wheels, discs, exhausts, chains, stands, jerry cans and chain lube cans. Every part is made of something (metal, plastic, rubber, carbon fibre, electronics, fabric and so on), and its info panel says which bin it goes in. Tyres are rubber and carbon parts can't be recycled, so they go in general waste. A recycling bin won't take the wrong material, and it tells you why ("That's rubber: general waste."). It also won't take a part still in its box, a container with fluid still in it, or an engine with parts still fitted. Look at a bin while holding a part to see whether it fits. Hold the work button to throw the part in, and it's gone. Recycling earns more XP than binning.

**TVs and channels**: the wall TVs now come in 120" and 128", plus a 136" video wall. The smallest is as big as the screens over the bays and the biggest matches the crew board. Older, smaller TVs in a saved shed come back as the nearest new size. When you hang a big TV near a corner, it slides along the wall until it clears the corner. Every TV, the screen over each bay and the crew board has channels. Look at one and press **R** (right mouse, X on a pad) for the next channel or **T** (B on a pad) to go back one. The channel number and name show in the corner for a moment. The channels are:
- **Live riding**: a chase camera on whoever is out riding. With two or more out, there's a stop for each rider. With nobody out, it shows which bikes are ready to ride.
- **Crew board**: everyone in the shed and what they're doing.
- **XP goals**: everyone's level and XP bar, and your own goals and points.
- **How to play**: the controls and the basics, a page at a time, turning over by itself.
- **My money**: your cash, what you earned and spent this in-game week, bikes you've sold and a chart of your cash day by day.
- **Garage money**: the business's account, what its bikes and loose parts would fetch, money in and out this week, what it owes the bank and a chart of the account day by day.
- **What you can afford**: a project bike and some fancy parts, at what they cost now, and whether your cash would cover them.
- **Contracts**: laid out now; customers' jobs arrive in a later update.

Bay screens start on their bay's bike and the crew board starts on the crew list. The channel each screen is on is kept with the shed, and everyone in co-op sees the same channel. The money pages show your own figures on your own screen.

The **whiteboard** on the front wall, left of the roller door, is for the crew's plans and lists. Walk up and look at it: hold left mouse to draw where you're looking and right mouse to rub out; 1–6 pick the pen colour (black, blue, red, green, orange, purple), 7 the eraser, and the scroll wheel the thickness (fine, medium, thick, marker). T types a line of text at the crosshair (Enter starts the next line under it), Z or Ctrl+Z undoes your own last mark, and holding X wipes the whole board. Everyone sees it as it's drawn, and it's kept with the shed.

**Pictures on the whiteboard**: press U at the board to pick a picture on your PC (PNG, JPEG or WebP). It goes up where you're looking, shrunk to at most 512 pixels across so it's quick to send, and everyone in the shed gets it a piece at a time (a grey card shows where it goes until it arrives). Look at a picture and press M to take hold of it: it follows the crosshair, the scroll wheel or + and - size it, and M or left mouse puts it down. + and - also size a picture you're just looking at. Pictures rub out with the eraser and undo with Z like any other mark. The board holds 12 pictures; they're saved with the shed. While you're moving a picture (or just looking at it), , and . turn it 15 degrees at a time; with snapping off, hold the key to turn it smoothly. Turned pictures rub out and undo like the rest, and stay turned on posters made of the board.

**Posters of the whiteboard**: press K at the board and give it a name, and what's on the board now (pictures and all) is saved as a poster design kept with the shed. The parts computer's **Shed, Wall posters** list then has it under "From the whiteboard": order it and a framed print of that drawing arrives outside the roller door, to hang on any wall. Wiping the board afterwards doesn't change the poster.

**Poster sizes**: every poster in the shop, the whiteboard ones too, comes in **A2**, **A1**, **A0** or as a **large banner** (2.4 m across): pick the size on the poster's page before you order it (A1 is picked to start with). Carrying a poster to hang it, press , or . to turn it a quarter, portrait or landscape. Its size and which way up it hangs are kept with the shed; posters bought before sizes came keep their old size. The shop holds up to 24 designs; past that the oldest one nobody has hung goes.

**Key bindings**: the Esc menu's **Key bindings** tab lists every action with its key or mouse button and its pad button. Click one and press the new key, mouse button or pad button (Esc cancels); Clear takes a binding off and Reset to defaults puts them all back. If one key would do two things in the same place (on foot, riding, with a spray can out, or at the whiteboard), the tab says so in red. Your bindings are saved with your settings and used from the next start too. The spray can's finish moved off the middle mouse button, which is ping's: it's T or the mouse's back side button now.

**Using a controller in menus**: the parts computer, the dyno desk and the Esc menu work with a pad. The d-pad or left stick moves between buttons, A presses (on the parts computer: A picks a kind, A picks a part, A again orders it), B goes back a step and then closes, and LB / RB go to the next aisle or tab.

The **radio** on the shelf above the workbench streams internet radio stations (SomaFM and Radio Paradise). Everyone in the shed hears the same station; each player's PC streams it, so it needs an internet connection. The Esc menu has volume sliders for sound effects and the radio. Stations live in `data/radio.json`.

### Contracts: customers at reception

Customers come to the **sales office reception** (just outside the roller door until the shed has a sales office) every few in-game hours, a couple at most at once; a **bell** rings as each one reaches the counter. Look at them and press **F** to see their offer card: who they are, the job, their bike, what they want, the budget, the pay and the deadline in in-game days. **Accept** and their bike is delivered to a free bay; **Decline** and they leave. Ignore them and they give up after about three in-game hours.

| Job | Unlocks at reputation | What it is |
| --- | --- | --- |
| Maintenance | 0 | A service: oil change, chain lubed and tensioned, brake pads, air and oil filters, spark plugs, brake fluid, a wash (3 to 5 of them). 2-3 days |
| MOT | 2 | The full inspection: tyre tread depth (legal minimum 1 mm), tyre condition and bead, wheels and rims, brake discs (thickness), pads (mm left), calipers, master cylinders, brake fluid level and age, fork and shock leaks, handlebars, chain and sprocket wear and tension, headlight, rear light, number plate (the tail unit), horn, dash, mirrors, exhaust condition and noise (a straight pipe is too loud), frame rust, the tank, the seat, engine oil and everything bolted up. 3-4 days |
| Modifications | 5 | 2 to 4 goals (a top speed, a weight, a style such as cafe racer or scrambler, panniers or a fairing fitted, new pipes, a paint colour) and a parts budget. 5-7 days |
| Bespoke build | 10 | An exclusive customer: a bare frame on a bay, built up to their targets (style, top speed or power, weight, a particular part, colour, condition 95% or better). Big pay, 10-14 days |

The **Contracts** tab in the Esc menu lists every job with its goals ticked off as you meet them, the deadline, the parts spent against the budget and what handing it back now would pay. For an MOT job, **Run MOT test** fills in the pass/fail sheet with what to fix; fix the fails and test again (any work on the bike after a test needs a re-test). When the bike is finished, wheel it round to reception (or just out of the roller door) and press **Hand back**: the customer rides it away and pays. A pass on an MOT issues an **MOT certificate**.

**Pay**: the fee, plus the parts back up to the budget; spending over the budget comes off the fee. Missing goals pays less (an MOT that never passed pays only the test fee), each day late takes 15% off (up to half), and a job done to the letter on time earns a tip, bigger for a bike in great condition. The garage's account gets the parts money and half the labour and tip; the other half is shared out to the players who worked on the bike, by how much each did. Good jobs raise the garage's **reputation** (1 for a service up to 5 for a bespoke build); late or poor ones lower it. The **Contracts** TV channel shows who's waiting, the jobs in progress with their deadlines, and what's done.

### The dyno room

Through the doorway in the back wall, between bays 2 and 3, is the **dyno room**: a rolling road set into the floor with a drum under the rear wheel, a clamp for the front, strap-down posts, a big cooling fan, the dyno desk and a wall screen. The doorway is just wide enough to wheel a bike through. The room has its **own light switch** inside the door, next to the **fan switch**.

Wheel a bike in (hold F on it) and let go of it near the drum: it snaps onto the rig. Before it will run it has to be **strapped down**: hold the work button at each of the four strap posts until the strap is done up (hold it again to undo one). Undo all four and take the hose off before you wheel it out.

- **Extraction hose**: it hangs on its hook on the east wall. Hold the work button at the hook to take it, then at the bike's exhaust to push it on; it stays drawn on the tailpipe. Hold the button on it again to take it off and hang it back up. Run the bike without it and the room fills with exhaust haze, which clears slowly.
- **Cooling fan**: switch it on and it spins up with a roar. Without it the engine heats up run after run and makes less power; the graph shows the engine temperature. The fan cools it down again between runs.
- **Ear defenders**: they hang by the door. Press F to put them on and the shed goes quiet and muffled; the badge in the corner says you're wearing them, and the crew sees them on your head. F at the hook hangs them back up.

Press F at the **dyno desk** to tune the bike on the rig, or any bike within about 10 m. Every change goes through the host, so the whole crew sees the same tune, and riding uses it too:

- **Engine**: fuel map (lean saves petrol but runs hot and wears the engine; a little rich makes the most power and fattens the low end), ignition timing (advance adds power until the petrol pinks: higher octane takes more) and the rev limiter. With no ECU the map and timing only move a little; a remap or race ECU opens them right up and lets the limiter go higher.
- **Suspension**: preload, compression and rebound, front and rear, only where the fork or shock has that adjuster.
- **Tyres and chain**: pressures (off a tyre's best pressure it grips less; soft tyres drag and wear faster, though a knobbly a touch soft finds more grip in the dirt) and chain slack.
- **Gearing**: front and rear sprocket teeth, and with a cassette gearbox (the close-ratio and race boxes) the spacing of the ratios.
- **Weight**: drill and trim parts (frame, wheels, discs, sprockets, seat, bars, exhaust and more) to save weight. Each part can be done once; it costs it some condition and it wears a little faster after.

**Run the dyno** and the bike revs up through the gears on the drum, then sweeps one gear to the limiter. The desk and the wall screen plot power and torque at the rear wheel against rpm, the speed in each gear, and the peak power and torque, top speed, power to weight and a 0-100 km/h estimate. The previous run stays on the graph, dashed, with the change in each number, so you can see what a change did.

### The sales office

East of the paint shop, across a block-paved forecourt with a small car park, is the **sales office**: a two-storey building with a full glass front. Its **doors slide open** as you walk up to them, and a brass **shop bell** over them rings when someone comes in. You hear it across the yard, and a chime box high on the shed's front wall (inside, right of the roller door) goes ding-dong so the crew hear it at work. Customers coming to the office ring it.

- **Showroom**: double height behind the glass, with four lit **display plinths**. Wheel a bike in through the doors (hold F on it) and let go of it on a plinth: it stands square and upright on it, on show. Each plinth takes one bike.
- **Reception**: the desk facing the doors, with helmets on the shelves behind it. Customers stand in front of it, and you stand behind it to talk to them.
- **Viewing area**: sofas round a low table, looking out over the showroom.
- **Kitchen**: through the door behind reception, with the kettle, a fridge and a table.
- **Office**: up the stairs along the back wall, on a **mezzanine** that looks down over the showroom, with a desk, a computer and a meeting table.

The office has **its own light switch** (one at the foot of the stairs, one at the top); it's saved with the shed. The sign, canopy, bollards and car park lamps come on by themselves at dusk.

### XP, levels, tool upgrades and skills

Everything you do earns **XP**, one pool for the lot: work in the shed, riding, and selling. Each job pops up a small "+6 XP Cleaning" under the level bar at the top right. Doing the same job to the same part again straight away pays half as much each time (so unbolting and bolting one bolt over and over soon pays nothing), and the big one-offs pay once per bike or part.

| Job | XP |
| --- | --- |
| Moving a part, unpacking a box, binning a part | 1 |
| Unbolting or bolting, taking a part off, a tuning change, tipping old fluid | 2 |
| Fitting a part, recycling plastic | 3 |
| Chain tension, taking a tyre off | 4 |
| Strapping a bike down on the dyno (each strap) | 1 |
| Fitting the dyno's extraction hose | 2 |
| Pouring or draining fluids, a dyno run, recycling metal | 5 |
| Scrubbing a part with the brush, a part coming out of the parts washer, lubing a chain (x how good the job was) | 6 |
| Pressure washing a whole bike clean (more for a muddier one; 12 more, once, for a real mud monster) | 8+ |
| Drilling and trimming a part | 8 |
| Restoring a part on the grinder, sandblasting a part (x how much came up bare), starting a scratch build | 10 |
| Fitting a tyre (x quality) | 10 |
| Spraying a part (x how good the paint job is) | 12 |
| A part brought from tired (under 60%) to like new (95%) | 4, once |
| The first time a bike starts | 25, once per bike |
| Rebuilding an engine on the stand | 40, once per engine |
| Finishing a build: a scratch build, or a bike stripped of 5 or more parts, all fitted, bolted up and rideable | 150, once per bike |
| A scratch build finished (on top) | 100, once per bike |
| A project bike restored to max health (every part 95% or better) | 300, once per bike |
| Riding: a jump of half a second or more (more for longer, half again for a clean landing), wheelies (3 per 10 m), stoppies (4 per 5 m), burnouts, knee-down corners, every km ridden, new top speeds (50, 80, 100 ... 320 km/h), 0-100 km/h times, and beating your longest jump, wheelie or stoppie | 2 to 60 |
| Selling a bike, selling a part (at the parts computer) | 100, 5 |
| The business's account reaching 10k, 25k, 50k, 100k, 250k, 500k and 1 million (everyone in the shed, once each) | 50 |
| Running an MOT test on a contract bike | 6 |
| A contract handed back: a service, an MOT, modifications, a bespoke build (x how many goals were met; to everyone who worked on it) | 40, 60, 100, 250 |

**Levels**: level 2 takes 75 XP, and each level takes more than the last (level 10 is about 3,900 XP, level 50 the top). Levelling up sounds a fanfare and gives you **one tool point and one skill point**. The Character tab lists **goals** too ("Land a 2 s jump", "Restore a bike to 95% health", "Ride 10 km" and more), each paying a lump of XP once.

**Your character goes with you**: XP, level, tool upgrades, skills, personal bests and goals are kept on your own PC by your player name (`profile.json` beside the saves folder), not in the shed, so you take them to any shed and any co-op session. In co-op everyone earns their own XP, and the host's screens can show the whole crew's levels.

**Tool upgrades**: spend a tool point on the next stage of any hand tool (Esc, then **Character**). Stages need level 2, 4, 8, 14 and 20. Each stage makes the tool about 11% quicker (fitting, bolting, scrubbing, grinding), the spray can and gun coat 12% faster with a wider fan, the brush scrubs a wider patch, the pressure washer has a wider jet and blasts off more muck, and the stopwatch keeps more laps. Each stage looks better too: bare steel, polished, chrome, anodised, carbon and finally gold trim, and other players see your upgraded tools. The tool bar shows each tool's stage as dots.

**Skills tree**: spend skill points on ranks (Esc, then **Character**: click a skill). A skill needs the one before it in its branch, and the deeper tiers need level 5 and level 10. **Respec** hands every skill point back.

| Branch | Skills |
| --- | --- |
| Mechanic | **Quick Hands** (fit, remove, carry and pour 10% faster a rank) · **Torque Feel** (bolting and chain tension 10% faster a rank) · **Engine Whisperer** (engine work on the stand 15% faster a rank; part info shows how much power a worn engine part costs) · **Salvager** (+20% a rank XP from binning, tipping and recycling) · **Master Builder** (+25% a rank XP for builds, engine rebuilds and max-health restorations) |
| Finisher | **Elbow Grease** (scrub 12% faster, pressure washer 15% stronger a rank) · **Steady Hand** (spray fans 8% wider, and 10% more before it runs, a rank) · **Hot Welder** (grinder and welder 12% faster a rank) · **Showroom Shine** (paint and lube jobs 4% better a rank) |
| Rider | **Balance** (steadier wheelies and stoppies) · **Throttle Control** (less wheelspin) · **Airtime** (+15% jump XP a rank, ride out landings 4 degrees steeper a rank) · **Quick Reset** (back up a second sooner a rank after a crash) · **Speed Demon** (+25% XP a rank for top speeds and 0-100 times) |
| Tuner | **Dyno Reader** (the dyno desk shows the power lost to wear, then which part to restore first) · **Featherweight** (drilling and trimming takes 10% more off a rank) · **Fine Tuning** (map, ignition and rev limiter go 8% further a rank on bikes you tune) |
| Crew | **Foreman** (+5% XP a rank with a teammate within 6 m) · **Mentor** (crew within 10 m get a bonus 5% a rank of your XP) · **Haggler** (parts you order 5% cheaper and what you sell 3% dearer, a rank) |

### Riding

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Engine on / off | I | D-pad up |
| Throttle | W / Up | Right trigger |
| Front brake | S / Down | Left trigger |
| Rear brake | Space | B |
| Lean left / right | A / D | Left stick |
| Weight back (wheelie) / forward | Shift / Ctrl | LB / RB |
| Shift up / down | E / Q | A / X |
| Toggle auto-shift | T | |
| Reset after a crash | R | View |
| Camera (chase, first person) | C | Right stick click |
| Horn | H | D-pad down |
| Headlight: low beam, high beam, off | L | Left stick click |
| Paddle backwards with your feet (when stopped) | Hold S | Hold left trigger |
| Burnout | Hold S, then throttle | Left then right trigger |
| Ping / stopwatch | G or middle mouse / P | D-pad right / left |
| Get off (when stopped) | F | Y |

The suspension now moves visibly over bumps and dirt ruts, the rear shocks stretch and squash with the swingarm, and landings from jumps soak up instead of bouncing. **Tyres come in widths** (for example 120/70, 160/60, 180/55, 190/50): wider tyres grip more on tarmac and less in mud, a wide front tyre steers slower, and each wheel rim takes a range of widths and one rim size (the part info shows it). Tyres and rims are drawn at their real width and profile.

Lights run off the ignition: with the engine off the headlight, tail light, fog lamps and clocks are all dark, on your bike and everyone else's. With the engine running, L still picks low beam, high beam or off. At night the beam lights the night air softly, a faint glow in the mist rather than a solid cone, a little stronger on high beam, with a few specks drifting through it. The headlight is two lights: a core that lights the road and a wide, dim flood round it. Both fade out gradually from the middle, so the pool of light on the road has no ring round it, and only the soft flood shows in the air, as a haze with no edges. (On the simpler renderer for older graphics cards it's a faint soft glow instead.)

You get on with the engine off: press I to start it. The speedo shows a fuel gauge, and economy and range are on the bay screens. If the tank runs dry the engine stalls. Getting off puts the bike on its side stand (or centre stand), unless you stop by a bay's paddock stand. Bikes have no reverse gear: stopped, hold the front brake for a moment and you paddle backwards with your feet, steering as you go (or hold F next to a bike to wheel it about on foot). Hold the front brake and open the throttle to light up a burnout. The front tyre doesn't lock or skid any more; the back one does unless the ECU has ABS. The engine sound now follows the engine: cylinders, capacity, the exhaust and the gearbox's whine. The Esc menu switches units between metric (km/h, km, kg, L/100 km) and imperial (mph, miles, lb, UK mpg).

Hold weight back (Shift / LB) to lift and hold a wheelie; the bike now eases the throttle and dabs the back brake for you near the balance point, and a stoppie on the front brake is easier to hold. In the air, throttle tips the bike back and closing it (or the back brake) tips the nose down, so you can set up the landing. Skids screech and leave black marks on tarmac (and ruts on dirt). The moment a tyre loses grip it gives a loud, sharp chirp (louder the more suddenly it lets go, from a lock-up, a wheelspin or a burnout), and a skid that goes on settles to a quieter screech. The clocks face the rider and their needles, rev lights and screens show live speed, revs, gear and fuel; first person sits at eye height.

The **yard** past the drag strip has movable kit: small, medium and large ramps with a landing ramp, a tabletop, cones, posts, flags, barrels, a log, hay bales, a tyre stack, an old car, concrete and brick walls and fences. Take hold of any of it with F and push it where you want. Order more from the parts computer's **Yard:** categories; it's dropped in the yard.

You steer by leaning: the rider counter-steers for you, like on a real bike. The **rider assist** setting goes from 0 (full sim) to 1 (most help with balance, wheelspin and wheelies). The Esc menu has a **Controller check** tab that shows exactly what the game reads from your pad.

### Garage upgrades

The garage's money (the **Garage money** channel on any screen) buys a bigger, smarter shed. On the parts computer press **Garage upgrades** at the top: every upgrade is listed with its price and what it needs first. Pick one and press **Buy**. Anyone in the crew can buy with the garage's money, and it's built for everyone straight away. Each purchase earns the buyer XP, bigger jobs more.

| Upgrade | Price | Needs | What you get |
| --- | --- | --- | --- |
| Workshop extension | £30,000 | | A new wing behind the paint shop, through a doorway knocked in the back wall behind bay 4 (bay 4's screen moves up over it). Lots of floor room for more kit |
| Bays 5 and 6 | £20,000 | Extension | Two more work bays in the extension with lift plates, lights and their own screens. Project bikes, blueprint builds and scratch builds all use them |
| Bay 7 | £12,500 | Bays 5 and 6 | A seventh bay at the far end |
| Storage annex | £15,000 | | A tall storage building behind the storage room, through a wide doorway in its back wall. Lit from the storage room's switch |
| Pallet racking | £4,500 | Annex | Three runs of heavy-duty racking in the annex: real shelving that takes parts and can be moved |
| Mezzanine floor | £35,000 | Annex | A steel deck across the back of the annex, with stairs up the side, stacked with stock; room for the racking underneath |
| Painted epoxy floor | £3,500 | | A glossy charcoal flake floor |
| LED lighting | £6,000 | | Brighter cool-white lights and an LED strip round the walls |
| Wall cladding | £9,000 | | White wall panels over aluminium chequer plate with a red pinstripe |
| Branded signage | £5,000 | | A lit sign box over the roller door and a neon TORQUE SHED inside |
| Crew lounge | £22,000 | Extension | Leather sofa, coffee table, drinks fridge, arcade machine, rug, lamp and a neon sign in the extension |
| Showroom finish | £250,000 | Epoxy, LED, cladding, lounge | A gloss black and white chequered floor, honeycomb LED ceilings and chrome trim |

Upgrades are kept in the shed's save; older saves start with none. Everything is built behind the shed, away from the yard.

### Weather

The weather changes by itself every few minutes between **clear skies**, **cloudy**, **fog** and **rain**, drifting from one to the next over about 40 seconds. Clouds grey the sky and dim the sun, and the shadows go soft; fog closes in so you see only a short way; rain falls round you, soaks the roads and the yard so they go darker and shiny, and wet tarmac grips a little less (about 15%), so brake and lean with care. Once it stops the roads dry out over a few minutes. You hear the rain outside and drumming on the roof when you're in the shed, and it never rains indoors.

In the Esc menu's **Settings** tab, **Weather** picks **Changes by itself** or holds one kind (always clear, cloudy, foggy or raining). In co-op the host's weather is everyone's. The weather is saved with the shed.

### Money

There are two kinds of money: **your own cash**, kept with your character like your XP (so it goes with you to any shed), and **the business**: the garage's own account, kept with the shed. A new shed's business opens with **£10,000**. Your cash shows top right, next to your level, and pops up green ("+£4 Restoring") as it comes in.

**Wages**: every job that earns XP also pays a small wage (a few pounds for spanner work, more for restoring, spraying and fitting tyres, and a good lump for finishing a build or restoring a bike to max health). Like the XP, doing the same job again straight away pays less and less, and the one-offs pay once. The business takes its **cut** of every wage (20% to start); you get the rest. Riding pays XP, not wages. The real money is in selling bikes (and, later, contracts).

**Buying and selling**: parts cost money now, from the business's account: plain parts are cheap, fancy and light ones dear, engines by their size. If the business can't afford a part, the parts computer says so and nothing comes. A **project bike** costs a bit more than it would fetch as it comes, so the profit is in restoring it. The parts computer's **Sell** aisle sells **loose parts** (on the floor, a bench or shelf, or in your hands; an engine goes with whatever is fitted to it) and **whole bikes**. A dealer pays 70% of what a thing is worth now, and worn, rusty parts are worth far less than good ones, so restore before you sell. A complete bike fetches 15% more, and 15% more again with petrol and oil in it, ready to ride. The money goes to the business; whoever sells gets the XP and a small commission.

**The Money tab** (Esc menu): your cash and the business's, and:
- **Send money**: pick a mate or the business and an amount: it comes out of your own cash. Anyone can pay the business.
- **Take money out**: only the **garage owner** can move money from the business into their own cash.
- **Garage settings** (the host only; greyed for everyone else, and saved with the shed): the business's **cut** of wages (0 to 100%) and who the **garage owner** is (the host to start).
- **Bank loans**: the owner can borrow £5,000 (10 days), £20,000 (20 days) or £50,000 (30 days), up to £100,000 owed in all. Every in-game day (when the clock passes midnight) the bank adds a little interest to what's owed and takes the day's repayment from the business. **Pay** a thousand off, or **Clear it**, any time: paying early saves interest. If the business can't make a repayment it's **missed**: a fee goes on the loan and the bank won't lend again until that loan is paid off. With the day and night cycle off, days don't pass and nothing is due.
- **The ledger**: the business's last 100 movements (sales, purchases, cuts of wages, money sent in, repayments), newest first, and your own money's recent log.

In co-op the host keeps the books: everyone's wages, transfers and the business are checked by the host, and your cash is kept on your own PC.

### Debug tab

The Esc menu's **Debug** tab is for trying things out: **Reset my XP** (back to level 1 with no upgrades, skills or goals), **Max my XP** (top level, every point to spend), **Reset everyone's XP** (host only: every player in the shed), **Reset my money**, **Max my money**, **Reset garage money** and **Give the garage £1,000,000** (the last two host only); for contracts (host only) **Send a customer**, **Send a bespoke customer** and **Reputation +5**. Every reset asks first. Your money is kept with your character and the garage's with the shed, and both show on the TVs' **My money** and **Garage money** pages.

### Co-op

One player picks **Host a co-op shed**; the others type the host's address into the box and pick **Join**. The game uses UDP port **24680**. The host's shed is the shared one: everyone works on the same bikes. The host's Esc menu shows exactly which address to give friends.

- Same network: use the host's local address (192.168.x.x or similar).
- Over the internet: friends use the host's public IP address. When hosting, the game asks the host's router to open UDP port 24680 itself (UPnP), and the Esc menu says whether that worked. If it didn't, forward UDP port 24680 on the router to the host's PC by hand. The first time the game hosts, Windows asks whether to let it through the firewall: tick both Private and Public networks.
- The join box takes `81.2.3.4`, `81.2.3.4:24680`, an IPv6 address or a host name.
- If the host's internet provider shares one public address between many homes (carrier-grade NAT), port forwarding can't work; Steam invites are planned for later.

## How it works

| File | What it does |
| --- | --- |
| `data/parts.json` | Every part and its numbers, which feed the physics directly |
| `scripts/shed_state.gd` | The shared shed: bikes, parts, who holds what. The host checks and applies every action |
| `scripts/workshop.gd` | Builds the shed, the paint shop and storage room, its stations and dashboards, and draws parked bikes and loose parts |
| `scripts/garage_upgrades.gd`, `workshop_upgrades.gd`, `upgrades_panel.gd` | Garage upgrades: the catalogue and rules, building them onto the shed, and the parts computer's Garage upgrades page |
| `scripts/walker.gd` | First-person player, tools, targeting and hold-to-work |
| `scripts/placement.gd` | Snapping equipment square and flush to walls and corners |
| `scripts/dashboard.gd`, `shed_tv.gd`, `tv_channels.gd` | The shed's screens and wall TVs, and their channels and pages |
| `scripts/whiteboard.gd`, `board_data.gd`, `board_print.gd` | The shared whiteboard: drawing on it, pictures from players' PCs, and its marks kept in the shed state; whiteboard posters |
| `scripts/settings.gd`, `keybind_tab.gd` | Settings, every key binding and rebinding them in the Esc menu |
| `scripts/bike_build.gd` | Turns parts, their condition and the tune into stats: mass, torque curve, grip, brakes, top speed, dyno runs |
| `scripts/sales_office.gd` | The sales office: its forecourt, showroom plinths, reception, viewing area, kitchen, stairs and mezzanine office, the sliding doors and the shop bell |
| `scripts/dyno_room.gd`, `dyno_graph.gd`, `tuning_computer.gd` | The tuning room and its rolling road, the dyno graphs, and the tuning desk |
| `scripts/bike_model.gd` | Builds the visible bike part by part, with rust and grime, and each part's own fit from geometry mode |
| `scripts/geometry_mode.gd`, `geo_gizmo.gd`, `blueprint_tab.gd` | Geometry mode (fitting a bike's parts with move, rotate and scale handles), the handles and their maths, and the Esc menu's Blueprints tab |
| `scripts/tyre_game.gd` | The tyre-fitting game on the tyre changer |
| `scripts/blast_game.gd`, `blast_marks.gd`, `blast_hud.gd`, `blast_detail.gd` | The sandblasting game in the blast cabinet: the coverage, the satin bare-metal mask and its shader, the live readout, and the close-up engine detail |
| `scripts/bike.gd` | Rigid-body bike with ray-cast suspension, slip-based tyres, engine, clutch and gearbox |
| `scripts/controls.gd` | Gamepad sticks and triggers, calibrated against stuck axes |
| `scripts/net.gd`, `remote_player.gd`, `remote_bike.gd` | Multiplayer and other players |
| `scripts/world.gd` | The map outside: terrain, road loop, Build Yard, trees |
| `scripts/daylight.gd`, `weather.gd` | Time of day, sky and lighting; the weather (clouds, fog, rain, wet roads, rain sounds) |
| `scripts/debug_tab.gd` | The Esc menu's Debug tab: reset or max XP and money, give the garage a million, send a customer, raise the reputation |
| `scripts/money.gd`, `money_tab.gd` | Money: part and bike prices, selling, the business's bank (cut, owner, ledger, loans) and its requests; the Esc menu's Money tab |
| `scripts/contracts.gd`, `mot.gd` | Contracts: customers, offers, goals, payouts and reputation (kept in `Shed.contracts`); the MOT inspection sheet |
| `scripts/customer.gd`, `contracts_view.gd`, `contract_panel.gd`, `contracts_tab.gd` | The customers walking in to reception, the offer card and jobs list, and the Esc menu's Contracts tab |
| `scripts/progress.gd`, `ride_xp.gd`, `character_tab.gd`, `skill_tree_view.gd` | XP, levels, tool upgrades, skills and goals, kept in your own profile; riding XP; the Character tab |
| `scripts/sfx.gd` | Tool, footstep and workshop sounds, synthesised at start-up, and the volume buses |
| `scripts/shed_radio.gd`, `radio_stream.gd`, `mp3_stream_decoder.gd` | The shed radio: streams an MP3 station over HTTP(S) and decodes it gaplessly |

Built with [Godot 4.6](https://godotengine.org) and Jolt physics.

## Development

```sh
godot --headless --path . --import
godot --headless --fixed-fps 120 --path . res://tests/test_runner.tscn   # physics, world and session tests
tests/mp_test.sh                                                          # host and client on one machine
godot --headless --path . --export-release "Windows Desktop" build/windows/TorqueShed.exe
```
