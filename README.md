# Torque Shed

A co-op motorbike restoration game: walk round the shed with friends, strip rusty project bikes down, clean and restore every part, fit better ones, then ride them out of the roller door.

Current milestone, **The Shed**: a snug first-person workshop with four bike bays, a workbench, a wheeled engine stand, a parts computer that orders parts and equipment, a parts washer, a repair bench, posters, seats and TVs to buy, wall dashboards for every bike and the crew, a radio everyone hears, a wash bay with a pressure washer beside the shed, and the riding map outside. Bikes are made of 48 parts from 42 kinds (stands, headlight, horn, ECU, panniers, top box, fog lights, fairing, mirrors, front mudguard, indicators, side panels, rearsets, engine guards, number boards and a swingarm of its own are optional), at least 5 of each and 16 wheels, plus petrol, oil, brake fluid and chain lube, and every part has its own colour, rust, dirt and wear. Everything you do earns XP towards levels, tool upgrades and a skills tree, and a wage; the business buys parts and project bikes, sells parts and bikes, and can borrow from the bank (see Money below), and the garage's money buys upgrades to the shed itself.

### What a bike is made of

| Area | Parts |
| --- | --- |
| Chassis | Frame, front fork, rear suspension (type, travel, bump and rebound damping, adjustability) |
| Wheels | Front and rear wheel (spoked, wire, cast, carbon; 17" to 21"), front and rear tyre (type, compound, width) |
| Brakes, front and rear | Disc (type, diameter), caliper (pistons), pads (compound), master cylinder (axial or radial) |
| Body and controls | Fuel tank (capacity, style), saddle, handlebars (style, width), dashboard, headlight (style, lumens), horn (17 types, from a disc horn or a courtesy pip to a truck air horn, a police yelp, a ship's foghorn or a musical one), fog lights |
| Electronics | ECU (stock, remap, ABS, sport with traction control, race with all of it): more power and revs, and rider aids for ABS, traction control, stability and anti-wheelie |
| Tail and front | Tail unit (6 kinds: long classic mudguard, café racer hump, scrambler loop, sport tail tidy, bobber chopped fender, enduro high fender), which carries the rear light, mudguard and number plate; fairing (headlight flyscreen, bikini, half, touring with a tall screen, full race in fibreglass or carbon), which cuts drag for a higher top speed but adds weight; mirrors (round chrome, bar-end, sport stalk, wide touring, fairing-mount); front mudguard (road hugger, MX high, enduro, bobbed steel, alloy café, chrome classic, carbon hugger) |
| Luggage | Panniers (canvas throw-overs, roll-top dry bags, leather saddlebags, rounded plastic cases, riveted aluminium boxes) and top boxes (30 L and 45 L plastic cases, an aluminium case, a wooden crate, a leather trunk, a waterproof roll bag strapped across the rack); they add drag |
| Stands | Side stand (length, lean), centre stand (lift). Without either, a bike left anywhere but a paddock stand falls over |
| Fluids | Petrol in the tank, oil in the engine, brake fluid in each master cylinder. Each has 3 grades and ages with use |
| Engine, built on the stand | Block (single, twin, parallel twin, V-twin, boxer, two-stroke or inline four; 50 to 1800 cc), cylinder head, fuel system, air filter, oil filter, spark plugs, cooling, gearbox |
| Drivetrain | Exhaust, sprockets, chain (slack and lube matter) |

Engine parts have to suit each other: one carb can't feed a big four, a race head needs a radiator, worn plugs misfire and a poor oil filter lets a tired engine wear faster. The bay screens list anything that doesn't suit.

## Playing

Unzip `TorqueShed-windows.zip` and run `TorqueShed.exe`. No install is needed.

**Save games**: you can keep as many games as you like, each with **its own garage and its own character** (XP, level, tool upgrades, skills, personal money, rider gear, personal bests and goals), so one save can be a level 20 shop with a full showroom while another starts from nothing. **New game** on the title screen asks for the save's name, then opens a new shed with a new level 1 character, solo or hosted. The title's **Continue** and **Host** buttons carry on with the game you played last; **Load game** opens the Load screen, which lists every save with a picture of it, its name, when it was last played, how long it's been played, your level and the garage's money; pick **Play solo** or **Host co-op**, or **Rename** or **Delete** one (it asks first). The game saves itself into the save you're playing every minute, when you leave to the title and when you close the game. The Esc menu has **Save now**, **Save as...** (a copy under a new name, which you then play on in) and **Save games...** (the same list: load another game, which saves this one first, or rename and delete the others). Everything about the shed is kept: the bikes and every part, where things were left (bikes out on the road included), equipment, the time of day and where you stood. A **new shed starts empty**: no bikes, nothing on the workbench and the engine stand bare, just the shed's own machines (stand, parts washer, repair bench, tyre changer, paint shop) and the business's opening money. Buy a project bike from the parts computer, or take on a customer's job, to get started. **Your old shed and character carry on**: the first time this version starts, the shed you had saved and the character from `profile.json` become your first save game, called "*your name*'s shed". **Co-op**: the host's save holds the garage and the host's character. Players who join keep their own character on their own PC (in `profile.json`, as before) and take it to whichever shed they join; the host's save just remembers where each of them stood and their crew numbers. Saves live in `%APPDATA%\Godot\app_userdata\Torque Shed\saves`.

### In the shed

| Action | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Walk / look | W A S D / mouse | Left stick / right stick |
| Run | Shift | Left stick click |
| Crouch (low parts such as stands, oil filter and chain need it) | C or Ctrl | Right stick click |
| Jump (a small hop; walk up the trailer's ramp to get on its bed) | Space | B |
| Pick a tool (hands, wrench, brush, grinder, spray can, pressure washer, spray gun, stopwatch) | 1-8, Q / E, mouse wheel | LB / RB |
| Work on what you're looking at, or put a held part down anywhere | Hold left mouse | Hold RT or A |
| Spray colour / finish (can or gun); with the spray gun, T also picks a protective coat after the finishes | R or right mouse / T or the mouse back (side) button | X / B |
| Ping what you're looking at for the crew | G or middle mouse | D-pad right |
| Stopwatch start / stop (lap or reset: right mouse with the stopwatch out) | P | D-pad left |
| Name the bike you're looking at | N | |
| Looking at any bike: order one of these, or copy its blueprint | O | |
| Roller door, shed lights (switches by the door); paint shop and storage room lights (switch inside each door) | F | Y |
| Dyno room: its lights and the cooling fan (switches inside its door), put on or hang up the ear defenders | F | Y |
| Sales office lights (switches by the foot of the stairs and at the top) | F | Y |
| Raise or lower a bay's bike lift (bays 5 to 7: look at the yellow button post beside the bay) | F | Y |
| Dyno room: strap the bike down (at each of the 4 posts), take the extraction hose off its hook and push it over the exhaust | Hold left mouse | Hold RT or A |
| Sandblaster: put your hands in the gloves / step back | F | Y |
| Sandblaster: blast where you aim / turn the engine | Hold left mouse / W A S D, or hold right mouse and move the mouse | Hold RT / left stick |
| Sandblaster: scan the engine for what's still to blast (press again to stop) | X | D-pad up |
| Spray can or gun on a part: bring up the spray controls (press again to step back) | F | Y |
| With the spray controls up: hold your breath to steady your hand | right mouse | LT |
| Spray can or gun: scan the part for missed, thin, dry and run patches (press again to stop) | X | D-pad up |
| Pressure washer on a bike: bring up the wash controls (press again to step back); hold the trigger to wash; X shows what's still dirty | F / left mouse / X | Y / RT / D-pad up |
| Drain a fluid (holding a drain pan, empty can or bleed bottle); with the wrench at a chain, set its tension | Hold R or right mouse | Hold X |
| Get on a finished bike (tap), or wheel it about on foot (hold) | F | Y |
| Use the parts computer or the dyno desk, switch the radio on or off | F | Y |
| Sort the parts computer's list, or show only parts that fit a bike, are within budget or suit a style | Sort / Fits / Within budget / Style, under the aisles | d-pad up to them, A |
| Sell a loose part, or a bike on a showroom stand to the trade (parts computer, Sell aisle); send money, take money out, loans (Esc, Money tab) | F at the computer / Esc | Y / Start |
| Garage upgrades (parts computer): pick a finish's colour or style, see it in the shed, back to the page | Click a swatch, **See it in the shed**, Esc | D-pad to a swatch and A, B |
| Talk to a customer waiting at reception (their offer card: Accept, Decline) | F | Y |
| Put a bike up for sale: ride or wheel it onto a showroom display stand and get off or let go | F (tap or hold) | Y |
| Use the sales PC (upstairs office): Showroom, Offers, Part exchange and Deals pages | F at the PC; Esc to close | Y; B or Start |
| Answer a buyer's offer (sales PC, Offers): **Accept**, **Turn it down**, or type a figure and **Counter-offer** | Click | d-pad to it, A |
| Talk to a part-exchange buyer in the showroom (opens their page on the sales PC) | F | Y |
| Bring a customer's bike in from the car park: get on and ride it (tap), or walk it in by the handlebars (hold) | F | Y |
| Unpack a delivery box; take hold of or let go of equipment (posters, TVs and the whiteboard hang on the wall you look at) | F | Y |
| Carrying equipment: push it further away / pull it closer | Mouse wheel up / down (or Q / E) | LB / RB |
| Carrying equipment: snapping to walls and corners on or off | R or right mouse | X |
| Turn the part in your hands or the equipment you're carrying before you put it down (a quarter turn a press; with free rotate on, or snapping off, a tap turns it 5 degrees and holding turns it smoothly). Posters turn portrait or landscape | , / . (the < and > keys) | View (turns it right) |
| Free rotate on / off: the turn keys go a quarter at a time, or to any angle | / | (none: use the Settings tab switch) |
| Scrap any machine, bench, shelf, stand, seat, poster, TV or trinket you're looking at (hands empty), the equipment you're carrying or the part in your hands, for good: hold, then press again to confirm | Hold Delete, then Delete | Hold D-pad down, then D-pad down |
| Sit on a seat (tap), or move it (hold) | F | Y |
| Change radio station | Hold left mouse on the radio | Hold RT or A |
| Tyre changer: fit the tyre you're holding (keep the lever on the marker) | Hold left mouse, steer the lever with the mouse | Hold RT or A, steer with the right stick |
| Tyre changer: lever the old tyre off / lift the wheel off, tyre and all | Hold left mouse / hold right mouse | Hold RT or A / hold LT |
| TV or wall screen: next / previous channel | R or right mouse / T | X / B |
| Throw away or recycle a part (hold it, look at a bin) | Hold left mouse | Hold RT or A |
| Whiteboard: draw / rub out; pen colour, eraser, thickness; text; undo; wipe it all | Hold left / right mouse; 1-6, 7, wheel; T; Z; hold X | Hold RT / LT; B colour; LB / RB thickness; D-pad left undo |
| Whiteboard: add a picture from your PC; move a picture (again to put it down); size it; make a poster of the board | U; M; + / - (or the wheel while moving it); K | (no picture upload); D-pad up; LB / RB while moving it; D-pad down |
| Whiteboard: turn a picture (15 degrees a press; with free rotate on or snapping off, hold to turn it freely) | , / . while moving it or looking at it | View |
| Geometry mode: fit the parts of the bike you're looking at (again, or Esc, to leave) | F2 | |
| Geometry mode: select a part / drag a handle; orbit; pan; zoom | Left mouse; right drag; middle drag; wheel | |
| Geometry mode: move, rotate, scale handles; snap (hold); undo; reset the part | W, E, R; Ctrl; Z; Backspace | |
| Menu (your level, tool upgrades and skills are in its Character tab; rider gear and trinkets in its Shop tab; change any key in its Key bindings tab) | Esc | Start |
| In menus and on the computers: move, press, back; next / previous tab or aisle | Mouse, Esc | D-pad or left stick, A, B; LB / RB |

**Building from scratch**: hold a frame and look at an empty bay floor (every bay is free in a new shed), then hold the work button to stand the frame up in the bay. Fit the fork, wheels, engine and the rest onto it from there. Taking the bare frame off again frees the bay.

Look at any part to see its spec, condition, rust, dirt, wear and colour. With your **hands** you take parts off (once unbolted and once the parts mounted on them are off), carry them, fit them and put them down anywhere: the floor, a bench top, a shelf or an engine stand. The **wrench** bolts and unbolts. The **brush** scrubs off dirt from every part around where it lands; the parts washer does it on its own. The **grinder and welder** restores rust and wear on a repair machine, every part on the machine at once. The **spray can** paints a part in the colour and finish shown above the tool bar (16 colours; gloss, matte, metallic flake, chrome or old patina); the part has to be free of rust first. Painting and chain lube are hand work: hold the button and sweep the can over the whole part. The panel shows how much is covered; missed patches make a patchy job and going over one spot too long leaves runs (or flings lube off), and the part's info shows how good the job was. Hold a part while looking at a bike or engine to see how fitting it would change power, top speed, weight and braking.

Chains stretch and lose their lube as you ride, faster off-road: crouch by the chain with the wrench and hold the second button to set the tension, and spray it with **chain lube** (hold the can, crouch, sweep it along the chain). A slack or dry chain wastes power and the bay screen says so.

**Fluids** come in containers from the parts computer. Hold one and look at a bike's tank, engine or brake master cylinder to pour it in; hold an empty container (jerry can, drain pan, bleed bottle) and hold the alt button to drain it out, then tip old fluid away at the general waste bin. Draining the oil means crouching under the bike. Low or old oil costs power and wears the engine, stale fuel loses power, and old brake fluid makes the brakes spongy. Bikes pick up dirt as they're ridden, where it really goes (see Dirt and pressure washing below). Wash a muddy bike in the shed or the **wash bay** beside it with the **pressure washer** (tool 6). With your hands, look at a bike with a stand bolted on to put it on its side or centre stand.

### Tail units, fairings and mirrors

Every bike has a **tail unit** behind the seat: the rear light, the mudguard or hugger and the number plate in one part, so swapping it changes the look of the back end and where the rear light sits. It bolts to the frame and is needed to ride. Bikes from older saves get the one that suits them (a hump on a café seat, a tail tidy on a sports bike, a high fender on an enduro, a long mudguard on the rest).

A **fairing** is an extra, like panniers. It goes on over the headlight, so the headlight has to be fitted first and the fairing has to come off before the headlight can. Flyscreens and bikini fairings turn with the bars; the half, touring and race fairings are fixed to the frame. The bigger and sleeker it is, the less drag and the higher the top speed (a cracked or filthy one helps less), but it adds weight; the touring fairing's tall screen is calm but pushes a lot of air. New bikes come with theirs painted to match.

**Mirrors** bolt to the handlebars (take them off before the bars), except fairing-mount mirrors, which need a fairing fitted and have to come off before it. They add a touch of drag. From the saddle the glass is a real mirror finish, catching the sky and what's round you.

All three are ordinary parts: order them at the parts computer (Bike aisle), clean, repair, paint and recycle them (steel guards go in metal recycling, plastic fenders and fairings in plastic, fibreglass and carbon ones and mirrors in general waste), and blueprints and saves keep them.

### Bike styles and the bolt-on style bits

Every part you can see on a bike says which **styles** it suits (classic, cafe racer, bobber, chopper, cruiser, scrambler, adventure, tall roader, tourer, sports, race, naked, supermoto, MX); the parts computer lists them under "Suits". Put the parts together and the bike has a style of its own: the frame says most, then the tank, seat, bars, tail and fairing, then the fork, exhaust, front mudguard and the rest. When most of the bike agrees (70% or more) it's **a proper** one ("A proper bobber"); less, and it's "mostly" one or a mix. The showroom computer shows each bike's style, and a proper one is worth more to a buyer. Customers can ask for a style (cafe racer, scrambler, tourer, sports bike, bobber, chopper, cruiser, adventure, MX or supermoto): the job counts it from the marks on its card, or from the bike being a proper one of the style all over.

Six optional kinds finish a bike in its style, each bolted to the frame, five or more of each:

| Kind | Models |
|---|---|
| Indicators | amber stalks, chrome bullets, mini LEDs, flush-mount LEDs, big touring indicators |
| Side panels | classic painted triangles, oval number panels, MX side plates, sculpted sports cowls, a chrome battery cover |
| Footpegs and rearsets | rubber road pegs, billet alloy rearsets (feet up and back), cleated MX pegs, forward controls (feet out in front), footboards. Rearsets move where the rider's feet go |
| Engine guards | chrome engine bars, an adventure crash cage, an alloy bash plate, frame sliders, an MX skid plate |
| Number boards | MX front plate and side boards, a front race plate, radiator shrouds, oval club-racer plates, flat-track side boards; each carries the bike's race number |
| Swingarm | in place of the one the frame comes with: steel or polished alloy **box-section** arms, steel or gold anodised **banana** arms bowed up over the exhaust, alloy or black **braced MX** arms with the truss under each side, a chain slider and guide, chrome or black **hardtail** rear ends (rigid stays, the shocks hidden away) and alloy or black **single-sided** arms. Take it off and the frame's own arm goes back on when the bike is rebuilt |

#### Style packs

Each of the fourteen styles has its own **pack** of about thirty parts made for it (436 in all): frames with their own wheelbase and rake, forks, wheels, tyres, tanks, seats, bars, exhausts, headlights, tails, front mudguards, mirrors, the bolt-on style bits, and fairings or bags where the style uses them. They aren't recolours: each part has a **look** that changes its shape and detail, for example:

- Tanks: teardrop, slab-sided, coffin, fat split cruiser tanks with a dash console, slim peanuts, little round tanks, long tanks with knee dents and long low racing tanks. Paint can be two-tone, a band, racing stripes, scallops or pinstripes. Caps can be monza, flush or twin, with oval, roundel or wing badges and knee pads.
- Seats: brat, stepped two-up, king-and-queen, sprung solo pans, gunfighter, long cafe humps and flat-track seats. They can be tuck-and-roll, ribbed or diamond-stitched with coloured piping, with springs, sissy bars and backrests.
- Bars: tracker, drag, buckhorn, Z bar, T bar on a centre post, clubman drops and ape hangers, on risers, with an MX brace and pad.
- Exhausts: fishtails, turnouts, cigar mufflers, trumpets, reverse cones, triangle cans and stubbies. Headers can be chrome, black, blued titanium or heat-wrapped, and some systems fit a pipe each side.
- Lamps: bullet, oval, quad LED, stacked twins, square lamps and nacelles, with chrome rings, stone grilles, visors and side brackets. Tail lamps can be tombstone, cateye, twin or halo LED.
- Tails: ducktail, cafe hump, solo cowl, flat-track tail with an oval number board, and sharp sport and race tails, with chrome fender struts.
- Wheels and tyres: moon discs, split-spoke cast wheels, rim stripes, polished lips, black or chrome spokes, big finned drum hubs and whitewall tyres.
- Forks: gaiters, chrome or black shrouds, fork braces, wide-glide spreads and fatter legs. Frames come in chrome, nickel and polished finishes.
- Front mudguards and fairings: ribbed and striped guards, a batwing, a club racer half fairing, a dome cowl and a bare cruiser screen. Bags come as studded leather saddlebags or rounded hard cases.

Each pack part suits its own style first and usually one or two related ones, so a bike built from one pack reads as a proper example of that style.

The parts computer's **Style** filter shows only parts that suit a style (kinds with no style, like engines, aren't filtered), and with a bike picked under **Fits** each part's page says what it would do to that bike's style. New project bikes and customers' bikes come with the bits that suit them; bikes in older saves get the slots empty.

#### Style refinements (Simon's notes, 16 Oct)

- **Sports and race bikes** wear a full fairing: one shell from a sharp nose round the lamps, under the tank and round the engine to a belly pan, with side panels back to the tail. Race fairings have a blank nose (no headlight), stacked winglets and a lower, flatter screen; some sports fairings have a winglet a side. Whatever is behind the bodywork is left undrawn while it's on. The red sports frame and the white race frame have a single-sided swingarm.
- **Adventure bikes** get a beak-nosed, creased half fairing with a tall screen, and an angular tank; **supermotos** a low flat tank with radiator shrouds.
- **Tanks sit level**: the nose can't rise more than 13° (6° on cruiser frames), and the classic and cruiser tanks are smaller and flatter.
- Plug caps come off the head sideways and the coil sits low; a V-twin's air cleaner is on the right of the vee; airboxes stay under the tank; twin shocks tuck under the seat on low frames, and a softail's lie flat under the gearbox.
- Whitewalls and wall stripes are on the outside of the sidewall.
- Classics and scramblers lose the race number boards; classic side covers are domed, with a badge.

#### The detail pass

Up close, every bike now carries the small parts that make it read as a real machine:

- **Engines you can tell apart.** Every engine has a rounded crankcase (crinkle black when it's painted dark, brushed cast alloy when it's bare), a round alternator cover on the left held by a ring of bolts, an ignition cover on the right and a finned sump. A V-twin has its chrome nose cone and pushrod tubes up to both heads; a boxer's finned valve covers stick out into the wind; an inline four or triple has one wide cam cover across the head with its bolts and cam-end caps; a two-stroke has deep fins on its barrel and head and no cam cover. HT leads run from every plug cap back to the coil.
- **Bars and cables.** Knurled grips with bar-end weights, switch gear both sides, the throttle housing, a clutch lever on its perch and a shaped brake lever with a ball end. The clutch and throttle cables run down past the headstock to the engine, and the brake hose runs from the master cylinder to the bottom yoke and down the back of the fork leg to the caliper.
- **Drum brakes.** Three new brakes fit either wheel in place of a disc: a 180 mm single leading shoe, a 200 mm twin leading shoe (two cams on a link rod, with an air scoop) and a 230 mm four leading shoe (a drum each side). Each has a finned drum, a backplate, a brake arm and a torque stay, with a cable at the front and a rod at the back. A drum bites less than a disc its size.
- **Seats** are piped along their edges, grained (or quilted, on a diamond-stitched seat), and a two-up seat has a grab rail and pillion pegs on hangers.
- **Forks** end in axle clamps with pinch bolts and axle nuts; classic shrouded and gaitered forks carry the headlamp on ears. Two new forks: a **leading-link** fork and an **Earles** fork, each with its links and spring units out in the open.
- **Wheels.** Cast spokes are shaped and taper to the rim, the rear has a cush drive, every wheel has a valve, and the tyre walls carry the maker's name and size ("TORQUE RADIAL", "120/70 ZR17"). Sprockets have teeth and lightening holes; discs have their bolts and floating buttons.
- **Radiators** have a finned core behind a grille, side tanks, a fan, shrouds and the top and bottom coolant hoses to the thermostat and the pump.
- **Bodywork.** Full and race fairings have twin headlamp eyes that light with the headlight, half fairings have side vents, sports tanks have a grip pad, and silencers have a clamp band and a riveted end cap. A kickstart folds up on singles, two-strokes and classic twins.
- **Surfaces.** Carbon parts show a twill weave, brushed alloy and titanium parts show their grain, grips and pegs are knurled, and engine covers are crinkle finished. A rusty part shows its rust instead.

### Front mudguards

The **front mudguard** is a part of its own, in its own slot, bolted to the fork (so it comes off before the fork does). There are seven: a **short road hugger** and a **bobbed steel blade** (both come painted to match the bike), a **polished alloy café guard** on wire stays, a long valanced **chrome classic**, a light **carbon sport hugger**, and two that bolt up under the bottom yoke clear of the mud: the **MX high fender** and the longer **enduro fender**. The low ones ride up and down with the wheel; the high ones stay put while the wheel moves under them. Each has its own condition, rust, dirt and wear, and can be cleaned, repaired, painted (spray can or the paint shop) and recycled like any part.

A bike can be ridden without one, but the front wheel then throws road muck all over the fork, engine, radiator, exhaust and lights, so they get dirty much faster. The more of the tyre a guard covers, the more spray it stops (the parts computer shows how much); a cracked one stops less. New project bikes come with the guard that suits them, and bikes in saves from before front mudguards get one too (on the bench if their fork is off). Customers can ask for one fitted, and bespoke builds name the one that suits their style.

### Geometry mode and blueprints

The bikes are built from simple shapes, and on some of them a part doesn't sit quite right. **Geometry mode** lets you fix that yourself. Walk up to any bike, look at it and press **F2** (or use the Esc menu's **Geometry mode** button): the mouse is freed and the camera circles the bike. **Click any part** to select it (it glows), and a set of handles appears on it, like in Blender, Unreal or 3ds Max:

- **Move (W)**: red, green and blue arrows. Drag one to slide the part along X (across), Y (up) or Z (along the bike).
- **Rotate (E)**: three rings. Drag one to turn the part about that axis.
- **Scale (R)**: boxes on stalks stretch the part along its own X, Y or Z; the white box in the middle sizes it all over.

Hold **Ctrl** to snap (1 cm, 5 degrees, 5%), or tick "Always snap". **Z** undoes, **Backspace** resets the selected part (Reset all puts every part back). The panel shows exactly how far the part has been moved, turned and stretched. Right-drag orbits the camera round the bike, middle-drag pans and the wheel zooms, so you can see it from every side. Every part can be fitted, engine parts and all.

Changes are only for **that bike**: another bike with the same tank isn't touched. While you work they're a draft; **Save to this bike** keeps them (the host saves them with the shed, and everyone in co-op sees them, riding too). **Save + blueprint** saves them to the bike and also keeps the bike as a **blueprint** with the name you type: its parts, paint, each part's colour and finish, and your fit. Leaving with changes not saved asks whether to save or discard them. If you swap a part, the new one in that slot keeps the slot's fit. It's only looks: power, weight and handling don't change.

**Building from a blueprint**: in the Esc menu press **Build from blueprint** (the **Blueprints** tab, where blueprints can also be renamed and deleted). Pick a blueprint and an empty bay, and a flickering blue **hologram** of the finished bike appears in that bay. The bay screen shows the checklist of every part it needs (fitted, on order or needed, with what the parts still needed cost). **Order missing parts** (in the Blueprints tab, or **Order blueprint parts** on the parts computer) delivers what's still needed in boxes to the delivery area outside the roller door, in the blueprint's colours, each paid for by the business (it stops when the money runs out). A whole bike's worth of parts fits in one go; if the delivery area and its racking ever fill up, bring boxes in and order again. Then put the frame on the bay's stand as for any scratch build: the bike takes the blueprint's name, paint and fit. Each ghost part vanishes as the real one goes on, and when the last part is on the hologram is gone. A project bike is never delivered into a bay with a hologram in it. Cancel in the Blueprints tab takes a hologram away.

**Order one of these, or copy its blueprint**: look at any bike on foot and press **O**. That's any of the shed's bikes wherever it is (in a bay, in the yard, parked at the roadside on an adventure), a crew mate's while they ride it, a customer's or a part-exchange buyer's, a biker's parked at the Pit Stop Cafe, a rider going past on the roads (they don't stop, so they can be picked out from about 30 m) and the bikes parked out front of an adventure's bike cafes. Every one of them has a real build behind it: the adventure cafes' bikes are a style's build from the stop's seed, the same on everyone's game, and once you're off your bike and walking about they're drawn as the bikes themselves, leaning on their side stands. The bike's card shows it turning on a turntable, every part on it with what it costs you at the parts computer (Haggler counts), the total and the delivery, and two buttons:
- **Order one of these** buys the lot out of **your own money**. They come as any parts order does, boxed outside the roller door in that bike's colours with your name on the notes, straight away. If the delivery area and its racking fill up, the rest wait on order (already paid for) and are boxed up as soon as there's room.
- **Copy its blueprint** keeps the bike as a blueprint named after it ("Rusty Ranger", "Dave's Cafe racer", "Sports bike, 600cc four"; a second copy is "... 2"): its parts, each part's colour, its paint and, for one of the shed's bikes, its fit. Build it or order its parts from the Blueprints tab as usual.

In co-op the host does both: it works out the price itself and hands back anything it didn't spend, so each player pays for their own orders.

### The sandblaster

A **sandblasting cabinet** (from the equipment page of the parts computer) strips rust and muck off a whole engine at once, its head, carbs and other ancillaries and all. The cabinets are big enough for the biggest engine with everything fitted, with room to turn it right round and tip it over. Take the engine off the stand and put it in the cabinet: it sits up on the turntable's post, drawn close up with its side covers, fins, bolts and float bowls. Look in through the glass and press F to put your hands in the gloves. One hand turns the engine (W A S D, the left stick, or hold right mouse and move the mouse); the other blasts wherever you aim (hold left mouse or RT). Thousands of fine grains of sand roar out of the nozzle, bounce off the engine and the cabinet's walls and glass and rattle down onto the grate, with dust kicking back off the metal. The sand never leaves the cabinet. Wherever the jet goes, the rusty, painted surface turns to **satin bare metal** as you blast (aluminium on the castings, bare steel on steel parts), so the bits you've missed stay rusty and are easy to see. Two strip lights under the cabinet's roof light the chamber.

While you work, a big readout shows a bar for the whole engine across the top and, down the side, each part with how much of it is bare and its **rust, dirt, wear and condition**, which change as you go (the crew sees them change too). When a part comes up bare there's a ding, a flash and "Bare metal!"; when the whole engine is done it says so, and you step back a moment later. Don't linger: blast one spot for too long and it goes dull and pitted, which wears the part (until the whole engine is done, below). Press F to step back early: each part keeps what you've stripped off it, and pays XP like restoring on the grinder. One person at the gloves at a time; the crew sees the jet, the engine turning and the bare metal coming up.

**The bare metal stays.** When you step back, each part keeps exactly where it's bare: the engine looks the same in the cabinet, in your hands, on the engine stand and fitted to a bike, in co-op too, and it's kept in the save. Put it back in the cabinet and you carry on from where you left off (only the newly bared metal pays XP). A part blasted all over (90% or more) comes out **bare metal all over**, so a finished engine is bare metal from end to end. **A fully blasted engine is as good as new**: the moment every part on it is bare all over, every one of them goes to **100% condition with no wear, dirt or rust** (any pitting goes too), and the readout shows it; it says so when you step back. It stays new if you put it back in the cabinet later, and it's still bare metal, ready for a protective coat. Fresh paint from the spray can covers it up again. Bare metal with nothing on it **flash-rusts** when the bike is ridden (faster in the muck), so give it a protective coat (below).

**The scan button** (X, or D-pad up on a pad, at the gloves; the green SCAN button on the cabinet lights up) shows what's still to blast: the engine glows red where there's rust left, green where it's bare and purple where it's pitted, with a sweep running up it, and a panel down the right gives the percentage still to blast over the whole engine, on each part and on each side (top, underneath, front, back, left and right). Press it again to turn it off. The crew watching see the glow too.

**Protective coats.** After blasting, hang the engine on one of the paint shop's hooks (carry it in and put it on a hook like any part: a whole engine hangs on an orange lifting sling, just under the hook). Take the **spray gun**, press T past the paint finishes to pick a coat, and sweep it over the engine like a paint job (the panel shows how much is covered; missed patches and runs make a worse coat). One job coats the engine and everything fitted to it:

| Coat | Looks | Protection |
| --- | --- | --- |
| Clear lacquer | The blasted metal on show under a gloss clear coat | Very good |
| Satin clear lacquer | The blasted metal under a soft satin sheen | Good |
| Black engine enamel | Gloss black paint | Best |
| Silver engine enamel | Metallic silver paint | Best |

A coat won't go over rust (blast it first). A coated part hardly flash-rusts and picks up less muck when ridden; the better the coat, the better it protects, and it slowly wears thinner with the miles. The part's info shows its coat and how good it is. Blasting a part again strips its coat with the rust.

Filters and spark plugs can be changed with the engine in the frame. Everything else on the engine needs it on the **engine stand**: take the exhaust and chain off, unbolt the engine, carry it to the stand, and work on it there. The **parts computer** orders any part (paid for from the business's account), equipment or a new project bike (also paid for), and its **Sell** aisle sells loose parts and whole bikes (see Money). Equipment comes in several models, with compact ones for a full shed: engine stands, shelving (four or five shelves that take parts anywhere on them), parts washers and repair machines (rated for 1 to 4 parts at full speed, some faster; see below), workbenches, wall posters, seats (stool, creeper, camp chair, bench, sofa) and big wall TVs with channels (see below). Parts marked "light" save weight; the bay screens show power to weight. Deliveries are left in the painted delivery area outside the roller door (see Deliveries below): parts come boxed (F unpacks a box, and boxed stock can go straight onto shelves), equipment comes ready to push in. Take hold of equipment with F, walk it where you want it (it turns with you) and press F to let go; whatever is on it goes with it. Posters, TVs and the whiteboard hang flat on whichever wall you look at. Write on a shelving unit's label plate by holding the work button on it. What you're looking at is described in the panel on the right. A bike can be ridden once every slot is filled and bolted up. What the speedo shows depends on the dashboard fitted.

### Placing equipment and parts

**Carrying equipment**: while you hold a piece of equipment, the mouse wheel (or LB / RB on a pad) pushes it further away from you, up to 3 m, or pulls it back in, so you can stand back and see the whole space you're putting it in. It stops short of walls. An outline on the floor shows exactly where it will go. While carrying, the wheel only moves the equipment; it doesn't change tool.

**Snapping** (on by default): equipment you put down turns square to the walls in quarter turns, and when one side comes close to a wall (or another piece of equipment) it slides flush against it; near two walls it goes tight into the corner. The outline turns blue and the panel says "Snapped flush to the wall" or "Snapped into the corner". Posters, TVs and the whiteboard slide into a corner that's close. Press R (right mouse, X on a pad) while carrying to turn snapping off or on; the Esc menu's Settings tab has the same switch. Yard kit outside never snaps.

**Benches, washers, repair machines and shelves take as many parts as fit**: there are no set places any more. Look anywhere on the top of the workbench, a bought bench, a parts washer, a repair machine or any shelf of a shelving unit with a part in your hands and put it down; it goes where you're looking, or the nearest clear spot to it, turned the way you face (and however you've turned it, see below). Each part takes up its real size, so you can line up a row of spark plugs, but a frame won't go in a small washer, and parts can't go on top of one another. The washer cleans everything in it and the grinder restores everything on the machine at once. Each machine works at full speed up to its rated number of parts (shown in its info); pile on more and each one goes a little slower, so a big load saves walking rather than time. Parts left in the old places in an older save stay where they were. Each shelf of a shelving unit works the same way: boxed stock and parts go anywhere along it, side by side, and parts left in a shelf's old numbered places in an older save stay just where they were.

**Turning things before you put them down**: with a part in your hands or a piece of equipment in your arms, press , or . (the < and > keys; View on a pad) to turn it left or right. Each press is a quarter turn. Press **/** (or the Settings tab switch on a pad) for **free rotate**: then a tap nudges it 5 degrees and holding the key turns it smoothly, to any angle; press / again to go back to quarter turns. The panel says which it's on and shows the key, and the choice is kept with your settings (the Esc menu's Settings tab has the same switch). Free rotate keeps the angle you set, so carried equipment isn't squared up to the walls while it's on. Turning snapping off (R while carrying) also turns things freely, as before. The outline on the floor (or on the bench or shelf) shows where it'll go and which way round, red if it won't fit there, and the panel shows how far it's turned. It's put down that way on the floor, a bench, a washer, a repair machine or a shelf (square to a bench or shelf with snapping on). The next part you pick up starts the way you face.

**Scrapping kit and parts**: anything the bins won't take, or that you just don't want, can be scrapped. Look at any machine or piece of furniture with your hands empty (a parts washer, workbench, repair machine, sandblaster, engine stand, shelving, seat, poster, TV, yard ramp or a trinket), or carry one (F), or hold a part, and hold Delete (D-pad down on a pad) for a second: the panel asks if you're sure, and pressing Delete again within a few seconds scraps it for good. Nothing is refunded. Whatever was on a shelf, bench or stand you scrap goes on the floor where it stood, and the parts bolted to an engine or the tyre on a wheel go on the floor in front of you. You can't scrap something a mate is carrying or someone is working at. The shed's own built-in kit (the spray bay, the tyre changer and the whiteboard) can't be scrapped: they can't be bought again and the shed needs them.

**The whiteboard can move**: press F on it to take it down and hang it on any wall, drawing and all. Where it hangs is kept with the shed; an older save has it in its usual place on the front wall.

**Deliveries** go to the big painted delivery area in the yard, to the right of the roller door as you come out. Each part comes in a box sized to fit it (a spark plug in a little one, a frame in a long one), and the boxes are packed tight in rows from the front of the area, so a whole bike's worth of parts from a blueprint fits easily. When the floor is full, boxes go onto the orange **delivery racking** along the back of the area (four shelves on each of two units, with a hatched aisle in front to walk along), and after that small boxes are stacked on top of the ones on the floor, no more than about chest high. Pick up a box from the bottom of a stack and the ones on top drop down. Equipment you order is left on the floor of the area where there's room for it. The racking is fixed down there: it can't be moved or scrapped, but anything on it can be taken off like any shelf.

**Delivery boxes** carry a shipping label from one of several made-up courier firms, with its logo, what's inside and a tracking number, on the lid (reading along the box's longer side) and on the front, so boxed stock on a shelf is easy to read. A box always comes from the same courier.

### Dirt and pressure washing

**Dirt sits where it really goes.** Every part keeps its dirt region by region (a grid over each of its six faces), not as one figure, and it's saved and shared in co-op. Bikes arrive dirty, with the muck where it collected: caked underneath, under the mudguards, behind the front wheel and along the lower sides, and no more than a light dulling of dust up top (the tank, seat and bars of a bike that comes in dirty are nothing like as mucky as its fork and wheels). Riding adds more the way it does in Farming Simulator: more the further and faster you go, much more on the dirt tracks and in mud, and more in the wet (wet tarmac throws up road spray too). It's heaviest **behind the front wheel** (the front of the engine, the downtubes, the radiator, the lower fork legs) and **under the mudguards**, and spreads along the lower sides of the bike. Above about 30 km/h **dead flies** build up on the fronts of the headlight, the fairing, the mirrors and the fork. A front mudguard still stops much of the spray. The tops of the tank, seat and panels stay all but clean on a normal road ride. The dirt is drawn on the bike as a layer of mud, dust and fly smears, not a tint, so you see exactly where it is; light dust is just a slight dulling of the finish.

**Pressure washing is a mini game**, like the spray gun and the sandblaster. Wheel the bike into the **wash bay** beside the shed (that's the only place the hose reaches), look at it with the pressure washer and press **F** (or just pull the trigger) to bring up the wash controls. Hold the trigger: a tight, fast fan of fine high-pressure water (with a fine mist round it, stopping where it lands) takes the dirt off **where it lands, on the side facing it**, in a good wide stripe; a film of dust goes in a flash and caked mud in a pass or two, so a normal muddy bike is a couple of minutes' work. Walk round the bike for the far side. For underneath, wheel it onto the **wash bay lift** (a grated runway over the drain: let go of the bike near it and it's clamped upright on it), press F on the lift's button post to raise it, then crouch beside it and aim up: the water goes through the grating. Lower it again to wheel the bike off or ride it. Every part can be got at with the lift up or down, and a speck in a fold the jet can't get square on to doesn't stop a part (or the bike) being called clean. Water splashes and mists back off the bike, and runs across the floor into the **drain in the middle of the wash bay**, leaving a puddle that slowly dries. The washed patches come up clean and wet as you go. The readout across the top shows how clean the whole bike is, the part you're aiming at and its % clean, how far off you're holding the lance (too close is a tiny spot; too far loses its bite), how clean each side is, and the dirtiest parts still to do. X shows what's still dirty. Each part that comes clean gets a **ding** and its name on the screen, once. The whole bike clean gets a bigger one: **Spotless!** Each part is worth its XP once, and the whole bike the bike-washed XP (more for a muddier one). A spotless bike sells for a little more (3%). In co-op everyone sees the dirt, the jet and the water, and two people can wash the same bike at once.

### The tyre changer

Tyres are changed on the **tyre changer**, built into the shed against the west wall past the end of the workbench. A tyre only goes on a rim it suits: each wheel takes a range of tyre widths and a tyre is made for certain rim sizes (17", 18", 21" and so on). Look at a wheel or tyre, here or on the parts computer, and its info says what it fits; if it doesn't fit, the changer tells you why.

To change one: unbolt the wheel and take it off the bike (any brake disc, caliper and pads on it come off first). The tyre comes off with it. Put the wheel on the changer. With empty hands, hold the work button to break the bead and lever the old tyre off, or hold the alt button to lift the wheel off whole. Then hold the new tyre and hold the work button: a marker runs round the rim, and you keep your tyre lever on it with the mouse (or right stick) until it has gone all the way round. Let go early and the bead slips off. How closely you follow it decides how well the bead is seated. A badly seated bead grips a little less and slowly lets the tyre down as you ride, and the part info and bay screen say so; do it again to put it right. Put the wheel back in the bike and it goes in with its new tyre. Everyone in the crew sees the changer turn while someone works on it, and a wheel left on it is kept with the shed.

The **parts computer** is split into three aisles, **Shed**, **Bike** and **Outdoors**, and has a search box that finds any part or piece of kit by name, kind or spec. In each aisle the kinds are listed under headings: the Bike aisle has **Engine and drivetrain**, **Chassis**, **Wheels and brakes**, **Body and lights**, **Luggage** and **Fluids**; the Shed aisle **Tools and machines**, **Storage and benches** and **Comfort and decor**; Outdoors **Jumps** and **Course**. Every model's row shows its price and the couple of numbers that matter most (and how many the shed already has loose, if any). The bar under the aisles sorts the list (**Sort**: shop order, price low to high or high to low, name, lightest first) and filters it: **Fits** picks one of the shed's bikes and shows only parts that go on it as it is now (tyres that suit its wheels, wheels its tyres take, fairing mirrors only with a fairing, a fairing only with a headlight), **Within budget** shows only what the business can pay for now, and **Style** only the parts that suit a style of bike. The part's page says whether it fits the chosen bike, and why not.

The **paint shop** is through the doorway in the east wall, between the parts computer and the parts washer; it's only reachable from inside the shed. It's a white-walled room with a ceiling of bright white **hexagon LED tiles** and its own light switch just inside the door. Its built-in **downdraft spray bay** has **ten hooks** on two rails, spaced so you can walk right round every part, with a walkway between the bay and the door. Hang parts on its hooks and sweep the **spray gun** over them. Hung parts swing, wire, hook and all, from the rail on the ceiling when you (or a mate) walk into them or spray them, and keep swinging for a few seconds before they settle. The gun's fine mist coats every part it passes, and the bay adds a better finish. With the can or the gun, the wet paint shows on the part as you go, so you can see the patches you've missed, and too much in one place runs. Fluid containers are see-through or have a sight strip, so you can see how full they are. In a shed saved before the paint shop got bigger, parts on the old booth's hooks stay on the same hooks.

#### Spraying by hand: primer, colour and lacquer

Painting works like the sandblaster: it's a careful mini game of its own. With the can or gun in hand, look at the part and press **F** to bring up the spray controls. They lock on that part (wherever you look) and give you a moment to **get set** before the trigger works, so you can line up, step to the right distance and compose yourself. While they're up you shuffle slowly, the view turns slowly for precise aim, and the paint lays on slower, so it takes steady, overlapping passes. Your hand sways very slightly (more if you walk while spraying); hold **right mouse** (LT) to hold your breath and steady it for a few seconds, shown by the breath bar, which refills as you breathe again. Before you pull the trigger the footprint ring already shows where the fan would land and how far off you are. **F** again steps back. Then hold the button and sweep the can or gun over the part, and the paint goes on exactly where the spray lands. You see a fine mist of paint (tiny droplets, with a faint haze of overspray that drifts and hangs), a ring on the part shows where the fan is landing (green at the right distance, red too close, blue too far, grey out of reach), and the bits you've missed keep showing the old colour (or the grey primer) until you cover them. A job can take up to three coats, picked with T (the picker shows them as COATS):

1. **Grey primer** (optional): a matte grey coat over the bare or old paint. Paint keys on better over it (a better paint job), and the part reads "in primer" until it's painted. Lacquer won't go on bare primer.
2. **Colour**: the colour and finish shown above the tool bar.
3. **Clear lacquer** (optional): with the spray can anywhere, or the gun in the booth, over the colour. It shines the paint and brings the job up a little, once.

**Distance and pace matter.** Hold the can about half a metre to a metre and a quarter off the part (Steady Hand and the tool's stage widen that): too close and the paint piles up and **runs** (they drip down the part); too far and it goes on **dry** and speckled; move steadily, as too fast leaves it thin and lingering piles it on. A panel at the top shows the coat's **coverage** (with the 90% mark), **evenness** (runs, dry and thin patches), a distance gauge and a pace gauge, the coat steps (Primer, Colour, Lacquer) and cues as you go. Once it's covered, let go of the button to finish the coat; it finishes itself if you cover it all. The coat's quality (coverage less runs and dry spray) sets the paint job's quality and the part's value, and pays XP. **X** scans the part: red where it's missed, amber where it's thin, green where it's good, blue where it's dry and purple where it's run. The spray gun in the booth coats every hooked part its mist reaches. In co-op each coat is checked by the host, and the crew see your mist.

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
- **Sales**: the bikes on the showroom stands with their prices, buyers' offers waiting for an answer (with the margin on each), part-exchange buyers in the showroom, and the latest deals.
- **Contracts**: laid out now; customers' jobs arrive in a later update.

Bay screens start on their bay's bike and the crew board starts on the crew list. The channel each screen is on is kept with the shed, and everyone in co-op sees the same channel. The money pages show your own figures on your own screen.

The **whiteboard** on the front wall, left of the roller door, is for the crew's plans and lists. Walk up and look at it: hold left mouse to draw where you're looking and right mouse to rub out; 1–6 pick the pen colour (black, blue, red, green, orange, purple), 7 the eraser, and the scroll wheel the thickness (fine, medium, thick, marker). T types a line of text at the crosshair (Enter starts the next line under it), Z or Ctrl+Z undoes your own last mark, and holding X wipes the whole board. Everyone sees it as it's drawn, and it's kept with the shed.

**Pictures on the whiteboard**: press U at the board to pick a picture on your PC (PNG, JPEG or WebP). It goes up where you're looking, shrunk to at most 512 pixels across so it's quick to send, and everyone in the shed gets it a piece at a time (a grey card shows where it goes until it arrives). Look at a picture and press M to take hold of it: it follows the crosshair, the scroll wheel or + and - size it, and M or left mouse puts it down. + and - also size a picture you're just looking at. Pictures rub out with the eraser and undo with Z like any other mark. The board holds 12 pictures; they're saved with the shed. While you're moving a picture (or just looking at it), , and . turn it 15 degrees at a time; with snapping off, hold the key to turn it smoothly. Turned pictures rub out and undo like the rest, and stay turned on posters made of the board.

**Posters of the whiteboard**: press K at the board and give it a name, and what's on the board now (pictures and all) is saved as a poster design kept with the shed. The parts computer's **Shed, Wall posters** list then has it under "From the whiteboard": order it and a framed print of that drawing arrives outside the roller door, to hang on any wall. Wiping the board afterwards doesn't change the poster.

**Poster sizes**: every poster in the shop, the whiteboard ones too, comes in **A2**, **A1**, **A0** or as a **large banner** (2.4 m across): pick the size on the poster's page before you order it (A1 is picked to start with). Carrying a poster to hang it, press , or . to turn it a quarter, portrait or landscape. Its size and which way up it hangs are kept with the shed; posters bought before sizes came keep their old size. The shop holds up to 24 designs; past that the oldest one nobody has hung goes.

**Key bindings**: the Esc menu's **Key bindings** tab lists every action with its key or mouse button and its pad button. Click one and press the new key, mouse button or pad button (Esc cancels); Clear takes a binding off and Reset to defaults puts them all back. If one key would do two things in the same place (on foot, riding, with a spray can out, or at the whiteboard), the tab says so in red. Your bindings are saved with your settings and used from the next start too. The spray can's finish moved off the middle mouse button, which is ping's: it's T or the mouse's back side button now.

**Using a controller in menus**: the parts computer, the dyno desk and the Esc menu work with a pad. The d-pad or left stick moves between buttons, A presses (on the parts computer: A picks a kind, A picks a part, A again orders it), B goes back a step and then closes, and LB / RB go to the next aisle or tab.

The **radio** on the shelf above the workbench streams internet radio stations (SomaFM and Radio Paradise). Everyone in the shed hears the same station; each player's PC streams it, so it needs an internet connection. The Esc menu's Settings tab has volume sliders for sound effects (tools, the pressure washer, knocks, dings, horns, footsteps and the ambience), engines (yours, other riders', the traffic and the truck) and the radio, saved with your settings. Stations live in `data/radio.json`.

### The paint mixing bay

The **paint mixing bay** is a narrow white room of its own off the paint shop, behind a **sliding glass door** in the paint shop's east wall near the front (the door slides open as you come up to it). It's lit with the paint shop's light switch. Along its walls:

| Station | What it does | Controls |
| --- | --- | --- |
| **Mixing bench** with the **digital scale** | Step up to it and the view drops to the scale. Put a 1 litre tin of base on (white, black, silver metallic, clear candy or lacquer), pick a tint, then tip the bottle: hold left mouse on the left of the screen and drag down to tilt it, and the further it tips the faster it pours. Circle the mouse with right held to stir. The panel shows the weight on the scale, the colour in the tin, the match against a target, add 250 g of base (to fix an over-pour, which uses more paint), spray a test card, the shaker, tip it away, and a name box to **Save tin**. Tabs for **Recipes** (codes, swatch wall, the manufacturer cards) and **Supplies**. | F to step up, F, Esc or Done to step back |
| **Tint rack** | 16 bottles of solid tints, with flattener. The **effects rack** upgrade adds pearl, candy dye, flake and chameleon bottles. | (from the bench) |
| **Tin shelf** | Saved tins wait here with their names on. | Left mouse: take a tin. Holding one: left mouse puts it on the shelf, on the scale, in the bin or in a mate's hands; right mouse pours it into the spray gun's cup |
| **Swatch wall** | A card for every saved colour, with its recipe code. | Left mouse: put its recipe card on the bench. F: pin the card to the whiteboard. Right mouse (with the automatic shaker): remix it |
| **Shaker** | Shakes a tin even in 20 s, or 4 s once it's the **automatic shaker**, which also remixes a saved colour from its card by itself. | (from the bench) |
| **Spray-out stand** and **daylight booth** | The last test card hangs on the stand and in the booth under daylight, the shop's strip light and a sunset, side by side, with the closest factory colour. The **curved panel** upgrade shows it on a curve, so a metallic, pearl or chameleon flips. | Look at it |
| **Masking tape** | On its hook by the door. | F or left mouse to take it; R picks centre stripe, twin stripes, pinstripe or two-tone; hold left mouse on a painted part to tape it, right mouse to peel |

**Mixing.** A tin takes up to 5 tints, weighed in grams. The scale reads to 1 g (0.1 g with the **0.1 g scale**). Your hand steadies as you level up (and on the stainless bench), the scale reads finer, and stirring takes fewer turns. A badly stirred tin sprays blotchy and won't make a test card. Give it a name and **Save tin**: it goes on the shelf and onto the swatch wall, and from then on the spray gun can load it: pour the tin into its cup and pick **Cup** with T. A litre does a tank, the guards and the side panels; a whole bike takes about two. Each part takes its share out of the cup. Every colour has a **recipe code** like `W-SC60-MG4:S` (base, then each tint and its grams, then the effect), which you can copy from the Recipes tab and paste into a mate's bench.

**Manufacturer colours.** The Recipes tab has 38 real factory colours as recipe cards, from 18 makers (Triumph, Ducati, Kawasaki, Honda, Yamaha, Suzuki, BMW, KTM, Harley-Davidson, Norton, MV Agusta, Moto Guzzi, Royal Enfield, Indian, Aprilia, classic British colours and custom paint shops): British Racing Green, Kawasaki Lime Green, Ducati Rosso, Honda Candy Red, Harley Hot Rod Red Flake and more. **Card** puts it on the bench to weigh out yourself (the accuracy pays XP), and **By eye** sets it as the target to mix by eye. You can mix anything you like freely as well.

**Effects** unlock by level: solid and metallic at the start, **pearl** at 5, **candy** at 8, **flake** at 10, **chameleon** at 15. Flattener in lacquer makes **matt**, **satin** or **gloss** (40%, 15% or none). **Masking** (two-tone and stripes) comes at level 3 and **fades** at 12. Candy goes on over a base colour and **darkens with each coat**: 3 or 4 is right, and a missed patch shows lighter. Solid and metallic need 2 coats, the effects 3. The gun's cup decides the coats: each pass with the same tin adds one.

**Masking and fades.** Tape a painted part (R picks the pattern), spray the second colour over it, then peel the tape: the first colour shows as the stripe, the pinstripe or the top of a two-tone. With the gun's **fade top** or **fade rear** load, the cup's colour fades in over what's there.

**Paying for it.** Bases and tints are bought with **garage money**, from the parts computer's **Shed aisle, Paint mixing bay** (Bases and Tints) or the bench's Supplies tab. A new shed starts with a few tins and part bottles. The bay's upgrades are in the parts computer's **Garage upgrades** (Paint mixing bay): stainless bench and tin racks, effects rack, 0.1 g scale, automatic shaker, colour meter and curved spray-out panel.

**XP.** You earn XP for accurate pours against a card, for a match over 95%, for an even stir, for test cards and for masking.

**Colour match jobs.** At reputation 3, customers bring **Colour match** jobs. They want the tank in a factory colour, or matched to a panel of their old paint. They need at least 85%, and they pay more the closer you get (up to 45% of the fee on top for a perfect match). Modification and bespoke customers sometimes ask for one too, and bespoke builds can add a stripe: "British Racing Green, with a gold pinstripe". Fades only come up once you're level 12. The **colour meter** upgrade lets you read a painted part's colour (right mouse on it) as the bench's target, from anywhere. Custom paint on a bike adds to its sale price: pearl, candy, flake, chameleon and hand-masked stripes make it more of a one-off.

**Co-op and saves.** The host checks every pour, stir and save. Only one player can be at the bench at a time, but anyone can carry a tin, hand it to a mate or fill their own cup from it. Stock, tins, the swatch wall, the test card, each player's cup and the paint on every part (its recipe, coats and stripes) are kept with the shed. If someone leaves with a tin, it goes back on the shelf.

### Contracts: customers at reception

Customers come to the **sales office reception** every few in-game hours, a couple at most at once. They **ride their own bike in** along the road and across the yard, park it in one of the marked bays of the sales office **car park**, get off and walk in (quietly: no bell or door chime rings as they come in), and the **phone** at reception rings as a new one calls ahead to say they're on the way (an extension bell in the shed rings with it, so the crew hear it at work). Look at them and press **F** to see their offer card: who they are, the job, their bike, what they want, the budget, the pay and the deadline in in-game days. **Accept** and they leave you the keys and walk off: their bike stays in the car park until you bring it into the shed, either riding it in (tap **F** to get on) or walking it in by the handlebars (hold **F**), and let go of it in any free bay to put it on the paddock stand. **Decline** and they walk back to their bike and ride away. Ignore them and they give up after about three in-game hours. The exclusive customer of a bespoke build arrives on foot: their bare frame goes straight onto a free bay. (Customers already waiting in a shed saved before they rode in came on foot, and their bikes still go straight to a bay.) Every rider has their own way of riding, the same for every player in co-op: some cruise and some are quicker, they come along the road from either end (keeping left) and take their own line across the yard, slow for the tight corners and lean into them, and paddle back out of a bay swinging round to ride off.

| Job | Unlocks at reputation | What it is |
| --- | --- | --- |
| Maintenance | 0 | A quick job (1 or 2 tasks), a service (3 or 4) or the works (5 or 6), from: oil change, chain lubed and tensioned, brake pads, air and oil filters, spark plugs, brake fluid, a wash, a new front or rear tyre, a new chain and sprockets, a new front brake disc, a fork service. Each task pays its own labour, and jobs that renew parts come with a parts budget for them. 2-4 days |
| MOT | 2 | The full inspection: tyre tread depth (legal minimum 1 mm), tyre condition and bead, wheels and rims, brake discs (thickness), pads (mm left), calipers, master cylinders, brake fluid level and age, fork and shock leaks, handlebars, chain and sprocket wear and tension, headlight, rear light, number plate (the tail unit), horn, dash, mirrors, exhaust condition and noise (a straight pipe is too loud), frame rust, the tank, the seat, engine oil and everything bolted up. A bike can come in with anything from a couple of faults to seven (the worse it is, the more it pays and the longer you get), and about half the customers add a job or two to do while it's in (an oil change, a wash, new plugs...). 2-5 days |
| Colour match | 3 | The tank resprayed in a factory colour or matched to a panel of their old paint (at least 85%), sometimes with a stripe, a pinstripe, two-tone or a fade in a named colour. Mixed in the paint mixing bay; the closer the match, the more it pays (up to 45% on top). 3-5 days |
| Modifications | 5 | 2 to 5 goals (a top speed, more power, a weight, a style such as cafe racer, scrambler, chopper or MX, one or two of panniers, a top box, a fairing, fog lights or a front mudguard fitted, radial four-pot front brakes, new pipes, a paint colour) and a parts budget. Pay and time go up with each goal. 5-10 days |
| Bespoke build | 10 | An exclusive customer: a bare frame on a bay, built up to their targets: the style always, and their own mix of top speed and/or power, a weight, one or two particular parts, a colour, and a finish of 90%, 95% or 98% condition or better. Big pay, more for more targets, 11-18 days |

The **Contracts** tab in the Esc menu lists every job with its goals ticked off as you meet them, the deadline, the parts spent against the budget and what handing it back now would pay. For an MOT job, **Run MOT test** fills in the pass/fail sheet with what to fix; fix the fails and test again (any work on the bike after a test needs a re-test). When the bike is finished, ride it or wheel it out to the **customer car park** in front of the sales office (any of its marked bays, or anywhere on that tarmac) and press **Hand back**: it can't be handed back from a bay in the shed (the Contracts tab and the bay screen say where to leave it). The customer pays, walks out of the sales office to it, gets on (only once they've reached it) and rides off along the road. A pass on an MOT issues an **MOT certificate**.

**The job on the bay screen**: while a customer's bike is in a bay, the screen over it shows the job instead of the usual numbers: a checklist of everything the customer asked for, each ticked off as soon as it's done (with what it reads now, and for an MOT the fails still to fix), how far through it you are, the deadline (red once it's late), and the money: the fee, the parts budget, what's been spent on parts so far, what handing it back now would pay, and the **profit** once the parts are paid for. The bottom line says what's left to do, or, once it's finished, to leave it in the car park outside the sales office to hand it back.

**Pay**: the fee, plus the parts back up to the budget; spending over the budget comes off the fee. Missing goals pays less (an MOT that never passed pays only the test fee), each day late takes 15% off (up to half), and a job done to the letter on time earns a tip, bigger for a bike in great condition. The garage's account gets the parts money and half the labour and tip; the other half is shared out to the players who worked on the bike, by how much each did. Good jobs raise the garage's **reputation** (1 for a service up to 5 for a bespoke build); late or poor ones lower it. The **Contracts** TV channel shows who's waiting, the jobs in progress with their deadlines, and what's done.

#### Batch orders and manufacturer test rides

**Batch orders** (from reputation 4): a trade customer walks in wanting a run of identical prepared parts, say "6 x 750 cc V-twins in bare metal making 67 hp" or "12 tanks in Iridium Orange (metallic), gloss under lacquer, finished to 85% or better". Engine orders name the engine, the finish (bare metal, bare under clear lacquer, or engine enamel from level 3) and the power it must make on the bench within 3 hp (from level 6, some want a stage one engine with a cotton filter and iridium plugs). Paint orders name a library colour (Iridium Orange is in the library now and a favourite), its sheen, whether it's lacquered, and the finish quality. Most send their donor parts crated in the delivery area (more come as room is made); some want you to source the parts and pay more for it. The number of parts and the pay grow with your XP level. Put each finished part down on the yellow-signed **dispatch pallet** next to the delivery area: it's checked there and then (an engine has to be complete, bolted up and oiled) and, if it's right, taken and paid for. The Contracts card counts them (7/10), lists what's on the pallet and the engine stands with what's wrong, and has **Dispatch from pallet** and **Close the order**. All of them in on time earns the bonus; late parts pay less.

**Test rides** (from reputation 6): a manufacturer's rep (Ducati, Triumph, KTM, Honda, Yamaha, BMW Motorrad, Kawasaki, Harley-Davidson, Royal Enfield or Aprilia, in the brand's colours; names only, no logos) rides their new prototype into the car park. It's a whole bike in the brand's style with one to three real faults in its physics: a weave at speed (yokes with too much offset), a weak front brake, a flat spot in the mid-range, a soft rear shock, or an engine that runs hot. Ride the set test: a distance, plus some of a top speed run, a hard stop, a hard lean, a lap of **The Loop** and a dyno pull. The ride logger checks each one. Then fill in the **report** (on the Contracts card, or the new **Contracts** tab on the office PC upstairs): rate handling, brakes, power, comfort and looks 1 to 5 and tick the issues you noticed. Some of the issues on the list aren't real faults on any prototype. The closer the report is to the truth, the bigger the bonus. It's their bike: no spanners on it, and it can't be sold. Leave it in the car park and press Hand back, and the rep rides it away.

### Recovery jobs: barn finds and crash rescues

At **character level 8** the parts computer's Garage upgrades sell the **recovery rig** (Vehicles, 14,500): a double-cab diesel pickup and a two-bike trailer with a fold-down ramp, a winch, ratchet strap anchors and a **dolly tray** (a wheeled bike skate) on its side rail. It parks in the yard west of the shed. The truck drives on four ray-cast wheels on the bikes' own tyre model, with springs and dampers, Ackermann steering, ABS brakes, a handbrake (**Space**) that locks the back wheels, an automatic box (hold the brake stopped for reverse) or the manual one (the bikes' gear keys and toggle), and its own engine note. **F** at the driver's door gets in or out (stop first), **C** swaps the chase camera for the view from the cab, and the trailer follows on a ball joint. The truck is a modern double-cab pickup (no maker's badges): a crowned bonnet, wheel arches with black trims, alloys on all-terrain tyres, tinted glass with its pillars and frames, headlights, tail lights and reversing lamps that light with the engine, a sports bar and tow bar, and seats, dash, instruments and steering wheel inside for the cab view. With the ramp down you can **walk up it onto the trailer's bed** and about on it; nobody rides on the trailer, so if someone drives off you're put down beside it.

Once the rig's bought the phone rings every few in-game hours with a job: a **barn find** (a bike left by a farm's barn or under a tarp behind a village house: rusty, filthy, flat tyres, stale fuel and oil, and maybe brakes seized solid) or a **crash rescue** for an insurer (a bike on its side on a country verge with smashed parts, maybe a buckled front wheel). Accept it from the clipboard (the truck's passenger door) or **Esc, Recovery**; a beacon marks the site and the HUD gives the distance and direction. On site: pull off the tarp, stand the bike up, lower the ramp (**F** at the back of the trailer), wheel the bike to its foot and **F at the winch** pulls it up into a channel. A bike that won't roll goes on the **dolly tray** first (F on the side rail carries it over, F again gets the bike on it) and is pushed up on that, more slowly. **Ratchet the straps** at the yellow anchors: the front pair hold it. A loose bike rolls about in its channel as you drive, and under hard braking or hard cornering it goes over the side and lands on the road, scuffed. Back in the yard, let it down the ramp: the **call-out fee** is paid.

Then **assess** it (Recovery tab): every part's condition, whether it needs restoring or replacing and what that costs, the repair estimate, and what it's worth now and put right. Then choose: **Buy it** (pay the owner their price: it's your project bike), **Break it for parts** (a lower price; every part comes off into the delivery area and the frame goes for scrap), or **Do the work for the insurer** (they list the damaged parts to put right, to 75% or better, everything on and bolted up; then **Insurer collects** and pays). The rig, the jobs, what's on the trailer and its straps are saved with the shed and shared in co-op; whoever is at the wheel drives it on their machine and the crew see it go by.

### The dyno room

Through the doorway in the back wall, between bays 2 and 3, is the **dyno room**: a rolling road set into the floor with a drum under the rear wheel, a clamp for the front, strap-down posts, a big cooling fan, the dyno desk and a wall screen. The doorway is just wide enough to wheel a bike through. The room has its **own light switch** inside the door, next to the **fan switch**.

Wheel a bike in (hold F on it) and let go of it near the drum: it snaps onto the rig. Before it will run it has to be **strapped down**: hold the work button at each of the four strap posts until the strap is done up (hold it again to undo one). Undo all four and take the hose off before you wheel it out.

- **Extraction hose**: it hangs on its hook on the east wall. Hold the work button at the hook to take it, then at the bike's exhaust to push it on; it stays drawn on the tailpipe. Hold the button on it again to take it off and hang it back up. Run the bike without it and the room fills with exhaust haze, which clears slowly.
- **Cooling fan**: switch it on and it winds up with a roar. During a run it's pushed harder as the roller speeds up, louder and higher, and winds up again as each run starts. Without it the engine heats up run after run and makes less power; the graph shows the engine temperature. The fan cools it down again between runs.
- **Ear defenders**: they hang by the door. Press F to put them on and the shed goes quiet and muffled; the badge in the corner says you're wearing them, and the crew sees them on your head. F at the hook hangs them back up.

Press F at the **dyno desk** to tune the bike on the rig, or any bike within about 10 m. Every change goes through the host, so the whole crew sees the same tune, and riding uses it too:

- **Engine**: fuel map (lean saves petrol but runs hot and wears the engine; a little rich makes the most power and fattens the low end), ignition timing (advance adds power until the petrol pinks: higher octane takes more) and the rev limiter. With no ECU the map and timing only move a little; a remap or race ECU opens them right up and lets the limiter go higher.
- **Suspension**: preload, compression and rebound, front and rear, only where the fork or shock has that adjuster.
- **Tyres and chain**: pressures (off a tyre's best pressure it grips less; soft tyres drag and wear faster, though a knobbly a touch soft finds more grip in the dirt) and chain slack.
- **Gearing**: front and rear sprocket teeth, and with a cassette gearbox (the close-ratio and race boxes) the spacing of the ratios.
- **Last ride**: charts of your last ride's telemetry (see Handling below).
- **Weight**: drill and trim parts (frame, wheels, discs, sprockets, seat, bars, exhaust and more) to save weight. Each part can be done once; it costs it some condition and it wears a little faster after.

**Run the dyno** and the bike revs up through the gears on the drum, then sweeps one gear to the limiter. The desk and the wall screen plot power and torque at the rear wheel against rpm, the speed in each gear, and the peak power and torque, top speed, power to weight and a 0-100 km/h estimate. The previous run stays on the graph, dashed, with the change in each number, so you can see what a change did.

### The sales office

East of the paint shop, across a block-paved forecourt with a small car park, is the **sales office**: a two-storey building with a full glass front. Its **doors slide open** as you walk up to them. A little brass shop bell hangs over them and a chime box is high on the shed's front wall (inside, right of the roller door), but customers coming in don't ring them: there's no bell or ding in the background, in the town's bustle or anywhere else.

- **Showroom**: double height behind the glass, with four lit **display plinths**. Wheel a bike in through the doors (hold F on it) and let go of it on a plinth: it stands square and upright on it, on show. Each plinth takes one bike.
- **Reception**: the desk facing the doors, with helmets on the shelves behind it. Customers stand in front of it, and you stand behind it to talk to them.
- **Viewing area**: sofas round a low table, looking out over the showroom.
- **Kitchen**: through the door behind reception, with the kettle, a fridge and a table.
- **Office**: up the stairs along the back wall, on a **mezzanine** that looks down over the showroom, with a desk, the big-screened **sales PC** (see Selling bikes below) and a meeting table. The PC's screen shows the stands and any offers waiting, and each display plinth has a price card.

The office has **its own light switch** (one at the foot of the stairs, one at the top); it's saved with the shed. The sign, canopy, bollards and car park lamps come on by themselves at dusk.

### Selling bikes

Bikes are sold from the **showroom**. Ride or wheel a bike in through the sales office doors and let go of it (or get off) on one of the four **display stands**: it's on show, and its price card says it's waiting for a price. Customers' bikes can't be sold.

Go up to the office and use the **sales PC** (F). It has four pages:

- **Showroom**: pick a stand. The page shows what's **sunk** into the bike (what it was bought for, the parts bought for it and the wages paid for work on it), what it's **worth** (its parts as they are, more for complete and ready to ride, and more again for being **unusual**: changed and top-spec parts, two-tone or chrome, metallic or patina paint, a scratch build, its own name, nothing like it in stock), and a **recommended price** for the target **margin** you pick (10% to 40%): at least the fair price, and no more than 15% over it. It says so when the bike is worth less than what's gone into it. Type an asking price (or **Use recommended**): the page shows the profit and margin at that price and how many buyers to expect. **Put it up for sale**, change the price later, or take it off sale. **Sell to the trade now** still pays 70% of its worth straight away.
- **Offers**: buyers find the bike online. Priced near or under what it's worth, a couple a day get in touch; well over, hardly anyone. Each offer rings the **till** (heard by everyone, and shown on the TVs' **Sales** channel) and waits about 8 in-game hours. **Accept** it, **Turn it down**, or **Counter-offer**: each figure shows its profit and margin. The buyer answers a counter-offer within a quarter of an hour: they take it if it's within what they'd pay (a little more with the Haggler skill), meet you halfway, or walk away if it's far too much or you keep pushing. A sold bike leaves its stand when the buyer comes to collect it and rides it away; the money goes to the garage's account and the seller gets the XP.
- **Part exchange**: now and then (sooner once a bike goes up for sale) a buyer **rides their own bike** into the forecourt, parks it and waits in the showroom by the bike they're after. Talk to them (F) or open the page: it shows their bike's model, colour, mileage, condition and each part's wear and rust, what it's worth to a buyer and to the trade, and what they want for it. **Accept their figure**, offer your own **allowance** (the page shows what the deal is worth: their cash plus their bike's trade value, against what ours cost), or **Send them away**. Offer too little or haggle too long and they leave. On a deal they pay the difference, ride ours away, and their bike is ours, parked outside the showroom.
- **Deals**: what's been sold, to whom, for how much and at what margin.

Everything is kept with the shed, and in co-op the host runs the buyers: everyone sees the same offers and hears the same till.

### The coffee shop next door

West of the storage room is the **Pit Stop Cafe**: a small brick cafe with a striped awning, a counter with a coffee machine and a cake display, the kitchen through a hatch behind it, four tables inside on a black and white floor, eight more out on the **terrace** under umbrellas, and a marked **car park for twenty bikes** in front. It's **open from 08:00 to 18:00**: the sign, the pendant lights and the festoon bulbs are lit and a barista is behind the counter. The rest of the time it's dark and the **CLOSED** signs are up in the window and on the pylon by the car park.

- **Bikers** ride in during the day along the road from either end and up the yard's west side, each on their own line and at their own pace, **on their own or in groups of two to five**, on bikes of every style (and the odd parts-bin special). They park in the bays, sit down inside or out on the terrace with a coffee, chat, and after an hour or two walk back to their bikes and ride off. At closing time they drink up and go.
- **Look at a parked bike** for its basics: style, engine, power, condition and roughly what it's worth.
- **Talk to its owner** (F, on them or on their bike) for a chat and to **make an offer** for it from the business's account. They almost always say no (a lowball gets laughed at; offering over the odds helps a little, never a lot) and hear you out three times at most. A yes buys the bike: it's the shed's, parked where it stands in the cafe car park, and they walk off down the yard to get a lift home.
- Now and then one **wanders over to the sales office** to look at a bike on show, and once in a while makes an offer on it (it comes in on the Sales PC's Offers page like any other buyer's).
- **The counter** (F on it or the barista) sells **coffee** (£3), **tea** (£2), **cake** (£3) and **sandwiches** (£5) from your own money, up to four things on a **tray** you carry in both hands (other players see it too). With a tray in your hands you can't work: put it down on anything flat (left mouse), the workbench in the shed included, and pick it up again later. Have what's on it with the right mouse button, for a little XP. Hand an empty tray back on the counter and it's cleared away.

The cafe, its bikers and the trays are kept with the shed (sheds saved before it simply start with an empty cafe), and in co-op the host runs it: everyone sees the same bikers and the same trays.

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
| Spraying a part (x how good the paint job is), giving a part or a whole engine a protective coat (x how good the coat is) | 12 |
| A part brought from tired (under 60%) to like new (95%) | 4, once |
| The first time a bike starts | 25, once per bike |
| Rebuilding an engine on the stand | 40, once per engine |
| Finishing a build: a scratch build, or a bike stripped of 5 or more parts, all fitted, bolted up and rideable | 150, once per bike |
| A scratch build finished (on top) | 100, once per bike |
| A project bike restored to max health (every part 95% or better) | 300, once per bike |
| Riding: a jump of half a second or more (more for longer, half again for a clean landing), wheelies (3 per 10 m), stoppies (4 per 5 m), burnouts, knee-down corners, every km ridden, new top speeds (50, 80, 100 ... 320 km/h), 0-100 km/h times, and beating your longest jump, wheelie or stoppie | 2 to 60 |
| Selling a bike, selling a part (at the parts computer) | 100, 5 |
| A part-exchange deal (on top of selling the bike) | 40 |
| The business's account reaching 10k, 25k, 50k, 100k, 250k, 500k and 1 million (everyone in the shed, once each) | 50 |
| Running an MOT test on a contract bike | 6 |
| A contract handed back: a service, an MOT, modifications, a bespoke build (x how many goals were met; to everyone who worked on it) | 40, 60, 100, 250 |

**Levels**: level 2 takes 75 XP, and each level takes more than the last (level 10 is about 3,900 XP, level 50 the top). Levelling up sounds a fanfare and gives you **one tool point and one skill point**. The Character tab lists **goals** too ("Land a 2 s jump", "Restore a bike to 95% health", "Ride 10 km" and more), each paying a lump of XP once.

**Your character is kept with your save game**: XP, level, tool upgrades, skills, personal bests, goals, your own money and rider gear are saved in each save game (see Save games above), so each save has its own character. When you join someone else's shed, you play the character kept on your own PC by your player name (`profile.json` beside the saves folder), which goes with you to any co-op session. In co-op everyone earns their own XP, and the host's screens can show the whole crew's levels.

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
| Engine on / off | I | LB + RB together |
| Throttle | W / Up | Right trigger |
| Front brake | S / Down | Left trigger |
| Rear brake | Space | B |
| Lean left / right | A / D | Left stick |
| Weight back (wheelie) / forward | Shift / Ctrl | Left stick back / forward |
| Shift up / down | E / Q | A / X |
| Hold the clutch in: the throttle blips the revs in any gear, at any speed, without driving the back wheel (let go and it takes up smoothly) | Hold Z | Hold LB |
| Look over your shoulder (while held) | Hold X | Hold RB |
| Nod to a biker you pass; hold it to raise your left hand off the bar in a wave (the crew see both; a biker in the traffic nods back) | N (hold: wave) | Right stick click (hold: wave) |
| Toggle auto-shift | U | |
| Adventure: ask a mate for a tow when you've broken down, or let the strap go | T | (none) |
| Reset after a crash | R | View |
| Camera (third person, first person, fly-by) | C | D-pad down |
| Swing the camera round the bike (first person: look round) | Mouse | Right stick |
| Ride-by camera: watch yourself ride past (again to end it) | V | (none; set one in Key bindings) |
| Telemetry overlay on / off | F3 | (none; set one in Key bindings) |
| Horn (hold it; other players hear it where your bike is) | H | D-pad left |
| Headlight: off, low beam, high beam (then high beam and fog lights, with fog lights fitted) | L | D-pad up |
| Paddle backwards with your feet (when stopped) | Hold S | Hold left trigger |
| Burnout | Hold S, then throttle | Left then right trigger |
| Circle burnout: spin round on the front wheel | Burnout, then A / D | Burnout, then left stick |
| Ping / stopwatch | G or middle mouse / P | Left stick click / (none: D-pad left is the horn) |
| Get off (when stopped) | F | Y |

The suspension now moves visibly over bumps and dirt ruts, the rear shocks stretch and squash with the swingarm, and landings from jumps soak up instead of bouncing. **Tyres come in widths** (for example 120/70, 160/60, 180/55, 190/50): wider tyres grip more on tarmac and less in mud, a wide front tyre steers slower, and each wheel rim takes a range of widths and one rim size (the part info shows it). Tyres and rims are drawn at their real width and profile.

Lights run off the ignition: with the engine off the headlight, tail light, fog lamps and clocks are all dark, on your bike and everyone else's. With the engine running, L steps through off, low beam and high beam; on a bike with fog lights the next press after high beam puts the fog lamps on as well, and the one after that switches everything off. At night the beam lights the night air softly, a faint glow in the mist rather than a solid cone, a little stronger on high beam, with a few specks drifting through it. The headlight is two lights: a core that lights the road and a wide, dim flood round it. Both fade out gradually from the middle, so the pool of light on the road has no ring round it, and only the soft flood shows in the air, as a haze with no edges. (On the simpler renderer for older graphics cards it's a faint soft glow instead.)

You get on with the engine off: press I to start it. The speedo shows a fuel gauge, and economy and range are on the bay screens. If the tank runs dry the engine stalls. Getting off puts the bike on its side stand (or centre stand), unless you stop by a bay's paddock stand. Bikes have no reverse gear: stopped, hold the front brake for a moment and you paddle backwards with your feet, steering as you go (or hold F next to a bike to wheel it about on foot). Hold the front brake and open the throttle to light up a burnout. With Riding realism at 0.5 or more the rider won't let the front tyre lock; at full sim it can, and the back one can lock at any setting unless the ECU has ABS. The Esc menu switches units between metric (km/h, km, kg, L/100 km) and imperial (mph, miles, lb, UK mpg).

**Horns** are recorded from real ones: the stock disc horn, low-tone and high-tone discs, snail horns, the twin trumpet and truck air horns and the freight train horn sound for as long as you hold H and stop when you let go; the courtesy pip horn gives one short pip however long you hold it; the **police yelp horn** keeps whooping and yelping while you hold it, a different yelp each time; and, as a joke, the **ship's foghorn** and the **tugboat horn** blow their whole blast on every press. The twin-tone, klaxon, bulb, scooter beeper, musical and goose horns are still made by the game. Fit one from the parts computer's Horn aisle. Other players hear your horn from where your bike is, quieter and duller further off.

Hold weight back (Shift, or the left stick back) to lift and hold a wheelie; the bike now eases the throttle and dabs the back brake for you near the balance point, and a stoppie on the front brake is easier to hold. In the air, throttle tips the bike back and closing it (or the back brake) tips the nose down, so you can set up the landing. Skids screech and leave black marks on tarmac (and ruts on dirt). The moment a tyre loses grip it gives a loud, sharp chirp (louder the more suddenly it lets go, from a lock-up, a wheelspin or a burnout), and a skid that goes on settles to a quieter screech. The clocks face the rider and their needles, rev lights and screens show live speed, revs, gear and fuel; first person sits at eye height.

**Cameras**: move the mouse (or the right stick) to swing the chase camera round the bike and look at it from any side, or from above. Let go and after a moment it eases back behind the bike; untick "Chase camera swings back" in the Esc menu's Settings to leave it where you put it. In first person the same moves turn your head. Press **V** for the **ride-by camera**: it drops a camera at the roadside ahead of you, watches you ride past for a few seconds, then goes back to the view you had (V or C ends it early). **C** steps through the views: third person, first person, then **fly-by** (the roadside camera stays on, hopping ahead each time you've gone past).

**Circle burnouts**: hold the front brake and open the throttle to light up the back tyre, then lean (A / D or the left stick) and the back of the bike slides round the front wheel in a circle of smoke. Burnouts scrub the back tyre down quickly.

**Out on the road a bike is just for riding.** Away from the shed, the yard round it, the wash bay and the sales office forecourt, you can't use tools, fit or take off parts, drain or lube anything, tune it or open geometry mode, and looking at it only shows its name. You can still ride it, wheel it about, name it and pour a can of petrol into the tank. Ride it back to work on it.

**Retrieving a bike**: if you leave a bike out on the road (you got off and walked back, fell off the edge of the map, or a friend left it there), the Esc menu lists it under "Left out on the road". Press **Retrieve** and the recovery truck brings it back to the yard just west of the roller door, for £40 from the garage's account. Anyone in a co-op shed can do it. Ride off the edge of the map and you're put back on the last bit of ground you were on, turned round.

The **yard** has movable kit: small, medium and large ramps with a landing ramp, a tabletop, cones, posts, flags, barrels, a log, hay bales, a tyre stack, an old car, concrete and brick walls and fences. Take hold of any of it with F and push it where you want. Order more from the parts computer's **Yard:** categories; it's dropped in the yard.

### The riding map

The **yard** in front of the shed is laid out as a **test area** for checking the bikes you build. The tarmac runs out level into the grass all round, with no kerb to hop.

- **Acceleration lane**: two painted lanes with a start line and a mark every 10 m up to the **BRAKE** line.
- **Braking zone**: a line every 5 m over green, amber and red bands, with number boards beside it, so you can see how short a bike stops.
- **Slalom**: cones and posts on painted spots.
- **Jump line**: ramps and a tabletop.
- **Skid pad**: a circle ringed with cones, for steady cornering.
- **Slow area**: speed humps, a U-turn box and a figure of eight.
- **Obstacle corner**: barrels, a log, hay bales, tyres, an old car, walls and fences.

The movable kit starts in its places and can be pushed anywhere as before. Kit you order is dropped in the painted **yard kit drop-off** box.

The **1 km loop** leaves the yard under a start gantry. It is all tarmac now, with fast sweepers, tighter corners with red and white kerbs, and gentle rises and dips. There are no jumps on it.

The map is about **4 km across**:

- **Tarmac roads** run off the loop to the villages of **Ashby**, **Thornley**, **Kettle Bridge** and **High Moor**, and to farms with barns, silos, fields, fences and hay bales.
- **Moor Pass** climbs into the **mountains** to the north on tight hairpin switchbacks, with armco and chevron boards on the bends.
- **Dirt tracks** branch off the roads and loop back: through the woods, along the river and round the east hills. The **Northfield climb**, the **Ridge run** and the **Peak circuit** are steeper, rockier and harder going.
- **Signs** at the junctions say where each road goes.
- Villages and farms have **street lamps** and **lit windows** after dark.

Tarmac grips best, dirt less, and grass least. The bike's dirt and ride stats know which one you're on. Rocks, trees, buildings and barriers are solid, so ride round them. Out at the edge of the map the hills rise up. Ride off it and you're put back where you last had both wheels down.

The **draw distance** graphics setting decides how far away trees, rocks, buildings and the detailed ground are drawn. Turn it down if the frame rate drops out on the map.

### Engine sound

Every bike sounds like the parts it's built from. The engine itself isn't a recording: the sound is worked out from how the engine runs. Each cylinder fires on its own crank angle, so a single thumps, a 360 degree twin beats evenly, a 270 degree parallel twin and a 90 degree V-twin lope, a boxer burbles, a triple warbles with its airbox howling and rasping, a flat-plane four screams evenly and the crossplane 1000 cc four growls. Two-strokes ring-ding at tickover, rattle, and come "on the pipe" in their powerband with a swelling, screaming note. Each firing goes down the header pipes and through the silencer: the **exhaust** decides how much gets out (stock can: quiet and boomy; slip-on; full system; titanium race system; straight pipe: loud and raspy). An open **air filter** (cotton cone, pods, velocity stacks) lets you hear the intake roar. A rusty exhaust blows and rasps, and worn plugs misfire.

- You hear the **exhaust** from the tail pipe and the **engine and intake** from the airbox. In the helmet view you hear more airbox and induction; on the chase camera, more exhaust. Other riders' bikes lose their top end with distance, and their pitch shifts (doppler) as they go past.
- Snap the throttle shut at high revs and the pipe **pops and burbles** on the overrun, most just after you roll off, then the odd crackle as the revs fall. Loud pipes pop far more than a stock can. Now and then a big backfire cracks with a lick of **flame** from the tail pipe.
- **Gear changes**, up or down, on every bike (yours, other players', customers' and the dyno's), engine running or not, are the gearbox's own **mechanical click or clunk** and nothing else: the lever's pawl ticking the selector drum round, the detent clicking into its notch and the dogs knocking home. Into first, and on a big bike or an old box, it's a heavy clunk (the dogs settle with a second knock); up the box, and on a small bike or the race box, it's a lighter click; a downshift knocks a touch harder than the change up; finding neutral is a soft click. A recording of a real gear lever is layered on top, a different take each change: low and heavy into first or on a vintage or wide-ratio box, a positive click on a close-ratio or enduro box, a light tick on the race box's **quickshifter** (which cuts the engine for a blink as you change up). The race box has a dry clutch, which rattles at tickover, and its straight-cut gears whine.
- Press I and you hear it **start like the engine it is**: the solenoid clacks and the **starter motor** whines up and cranks it over, labouring at each compression, the chuffs coming through the pipe. A single chugs over slowly, compression by compression; a twin beats in pairs; a big V-twin grinds over slowly and lumpily, an old Bendix drive clanking into mesh first; a triple and a four whirr over quickly and evenly. Small engines' starters whine higher, big ones lower. Then it **catches**: a few ragged first firings, the revs flaring (a single or a V-twin harder than a four) and settling to tickover as the starter spins down. A two-stroke single, a single with the vintage four-speed box and any little single, twin or two-stroke of 125 cc or less is **kick-started**: the lever's ratchet bites, the kick spins it through a few compressions and the lever springs back. Each engine has three takes of its start, so no two starts sound quite alike.
- The dyno room and other players' bikes use the same sound.

Each new engine's sound is worked out in the background when you get on (about a second; tickover is ready almost at once) and is shared by every bike with the same engine, exhaust, intake and gearbox.

**Recorded sounds** can replace the synthesised ones. Put .wav files in a folder named after the engine and exhaust, in `engine_samples` in the game's user folder (no import needed) or in `res://audio/engines` to ship them: the folder is `<layout>_<cylinders>_<exhaust>`, `<layout>_<exhaust>` or just `<layout>` (layouts: single, twin, parallel, vtwin, boxer, triple, inline, 2stroke; exhausts: stock, slip, full, race, straight). Loops are named by side, throttle and revs, each a seamless loop held at those revs: `ex_on_6000.wav` (exhaust, on the throttle, 6000 rpm), `ex_off_6000.wav` (overrun), `in_on_6000.wav` and `in_off_6000.wav` (engine and intake side). One-shots: `pop*.wav`, `bang*.wav`, `crack*.wav`, `shift*.wav` (every gear change), `neutral*.wav`, `starter*.wav` and `catch*.wav` (the engine firing up off the starter). Anything left out is synthesised as usual.

You steer by leaning: the rider counter-steers for you, like on a real bike. The Esc menu has a **Controller check** tab that shows exactly what the game reads from your pad.

### Handling: tyres, riding realism and telemetry

**Tyres work like real ones now.** Each tyre has a grip curve: grip builds as it starts to slip, peaks, then falls away to a slide. Braking or accelerating uses up grip the tyre could have used for cornering, so braking hard while leaned over leaves less to hold the line. A tyre loaded harder grips more, but not in proportion (a front tyre squashed under hard braking has a little less grip for its load). A leaned tyre pushes towards the lean (camber thrust), and grip builds over a short roll rather than all at once. The contact patch rolls round the tyre's round profile as you lean, so on fat tyres the bike leans a few degrees further for the same corner. Each tyre in the parts computer has a construction (radial or bias ply), a profile, a stiffness and how much grip is left once it slides: sport tyres and slicks are sharp and let go suddenly, touring tyres are softer, knobblies and old bias-ply tyres slide progressively. Tyre pressures change it too: a soft tyre slips further before it grips and is lazier to respond.

**Riding realism** (Esc menu, Settings) is a slider from 0 to 1:
- **0, full sim**: nothing hidden helps. Grab a handful of front brake leaned over and the front locks and tucks under, and you're down. Spin the back tyre up in a corner and snap the throttle shut and the slide grips all at once and throws you over the high side. The throttle goes exactly where you put it.
- **About 0.5**: the rider protects the front (eases the brake before it locks, leaving grip for the corner), rolls the throttle on and off smoothly and feathers it when the back spins.
- **1, easy**: as before this update, with the most help balancing, with wheelspin and with wheelies.

**Direct bars** (Settings, off unless you tick it) changes what steering does: instead of choosing how far to lean and letting the rider counter-steer for you, A / D or the stick push on the handlebars. Push the right grip (D, stick right) and the bars turn left for a moment, which leans the bike right; let go and the front end's own trail swings it into the lean and the bike carries on round the corner at the lean you let go at: the rider's hands keep a light hold on the bars (soaking up any shake) and steer a little into a roll they feel, and their body steadies the bike. Push the left grip to stand it back up. A full push is firmer the faster you go (a fast bike takes more to tip in), firmer on a heavy bike and gentler on a light one with soft knobblies, so a press tips any bike in at much the same pace. On a keyboard the push builds up as you hold the key, so a tap is a nudge; on a stick, a small move is a gentle push. At walking pace your feet are down and the bars just point where you steer. The F3 overlay's bar torque strip shows how hard you're pushing.

**Telemetry**: press **F3** while riding (or tick it in Settings) for the telemetry overlay at the right of the screen: each tyre's friction circle (the dot is where its force is against its grip: past the ring it's sliding, and it turns red) with its load, the throttle and brakes, and the last 8 seconds of lean, steering, slip ratios, slip angles, grip used and tyre loads. Every ride is recorded; the **dyno desk's Last ride tab** shows the whole of your last ride as charts (speed, lean, steering, slips, grip used, loads, throttle and brakes, gear and revs) with the top speed, most lean, hardest braking and cornering, and how long each tyre spent sliding.

### Handling: real steering and geometry

**The front end steers itself, like a real one.** The forks turn about a steering axis raked back through the steering head. How far the front tyre's contact patch trails behind where that axis meets the road (the **trail**) comes from the frame's rake, the fork's **offset** (in the parts computer's fork specs) and the size of the front wheel: about 100 mm on a sports bike, 120 to 180 mm on cruisers and choppers. The trail and the spinning front wheel turn the front into a lean and line it up with where it's rolling, so a bike all but holds itself up: ridden no-handed at normal speeds it rides on upright, the rider's hips only nudging it (on round tyres a bike left wholly to itself slowly falls into a turn). The front's own weight, out ahead of the axis on the offset, swings it into a lean too, and the wheel's spin fights it being tipped. The rider steers by pushing on the bars (you still choose the lean with A / D or the stick): push the right grip and the bars turn left for a moment, the bike leans right and turns right. That's **counter-steering**, and it really happens now. At walking pace your feet are down and the bars just point where you steer.

- **Feel**: a long, raked chopper with lots of trail is slow and steady to turn in; a sports frame flicks in. A light bike with a steep head angle can shake its head on a bumpy road, and the shake dies away.
- **Weave, wobble and tank-slappers**: put a fork with a lot of offset on a steep frame (a chopper's springer on a sports frame) and the trail all but disappears: the bike info warns you, and a shove at the bars grows into a tank-slapper. A **steering damper** (its own part, five of them: friction, linear, adjustable linear, rotary race and off-road) calms the front end; adjustable ones have a clicker on the dyno desk's Suspension tab. Bikes that turn up already built (project bikes, customers') always have a fork that suits the frame.
- **Weight**: where the parts sit moves the centre of mass. Luggage and a top box put weight high and out the back, a big engine sits it low, and a full tank weighs more than an empty one. Leaning into a turn, the rider hangs off to the inside.
- **Riding realism**: below 0.35 there is no helping hand pushing the bike over; the bars alone balance it. The rider holds the bars where they aim them as firmly as the front pulls and settles into the steady push it needs, rolls the bike towards the lean you ask for at a pace they can stop it from, and never asks the tyres for more than about 80% of their grip; so the bars stay steady at any realism, with no wiggle. From 0.35 up an invisible push helps, more the higher you set it, at a pace the steering can follow, and it lets go as the tyres run out of grip.
- **Telemetry** (F3 and the dyno desk) adds the bar torque, the steering shake and the trail as it changes (it shortens as the fork dives under braking).

### Garage upgrades

The garage's money (the **Garage money** channel on any screen) buys a bigger, smarter shed. On the parts computer press **Garage upgrades** at the top: every upgrade is listed with its price and what it needs first. Pick one and press **Buy**. Anyone in the crew can buy with the garage's money, and it's built for everyone straight away. Each purchase earns the buyer XP, bigger jobs more.

| Upgrade | Price | Needs | What you get |
| --- | --- | --- | --- |
| Workshop extension | £30,000 | | A new wing behind the paint shop, through a doorway knocked in the back wall behind bay 4 (bay 4's screen moves up over it). Lots of floor room for more kit |
| Bays 5 and 6 | £20,000 | Extension | Two more work bays in the extension, each with a bike lift, a light and its own screen. Project bikes, blueprint builds and scratch builds all use them |
| Bay 7 | £12,500 | Bays 5 and 6 | A seventh bay at the far end, with its own lift |
| Storage annex | £15,000 | | A big, tall storage building (about 11 by 14 metres, 6 metres high) behind the storage room, through a wide doorway in its back wall. Lit from the storage room's switch |
| Pallet racking | £4,500 | Annex | Three runs of heavy-duty racking in the annex: real shelving that takes parts and can be moved |
| Mezzanine floor | £35,000 | Annex | A steel deck across the back of the annex, with stairs up the east wall from a clear space at the bottom, stacked with stock; room for the racking underneath |
| Painted epoxy floor | £3,500 | | A glossy charcoal flake floor |
| LED lighting | £6,000 | | Brighter cool-white lights and an LED strip round the walls |
| Wall cladding | £9,000 | | White wall panels over aluminium chequer plate with a red pinstripe |
| Branded signage | £5,000 | | A lit sign box over the roller door and a neon TORQUE SHED inside |
| Crew lounge | £22,000 | | A room of its own upstairs on top of the workshop, with windows, up a steel staircase outside along the front of the paint shop: leather sofa, coffee table, drinks fridge, pool table, arcade machine, rug, lamp and a neon sign |
| Showroom finish | £250,000 | Epoxy, LED, cladding, lounge | A gloss black and white chequered floor, honeycomb LED ceilings and chrome trim |

Upgrades are kept in the shed's save; older saves start with none. With branded signage, the shed's own TORQUE SHED letters shrink to fit inside the light box's neon frame, above the strapline. Everything is built behind the shed, away from the yard, apart from the crew lounge on its roof.

**Bike lifts**: bays 5, 6 and 7 each have a motorbike lift. Look at the yellow post beside the bay (it has a green and a red button) and press **F**: the platform rises smoothly on its scissor arms to about waist height, carrying the bike on its paddock stand, so you can work on it standing up. Press **F** again to bring it down. Everyone in the crew sees it go up and down, and a lift left up stays up in the save. A bike can't be wheeled off or ridden while its lift is up, and you can't wheel a bike onto a raised lift.

**The crew lounge** is upstairs: walk round to the steel staircase that climbs the front of the paint shop (a sign at the bottom says UP TO THE CREW LOUNGE), up to the landing and in through the door. Its lights are on the shed's switch.

**The storage annex mezzanine**: the stairs run up the annex's east wall, from a clear space at the bottom, onto the deck across the back.

**Colours and styles**: the finishes come in your choice of looks. Pick one in the list and click the swatches (colours) or named buttons (effects and styles) under its description before you press **Buy**; a little preview room beside them shows it with everything you've already built, and the shed itself changes to match on your screen while you pick (nobody else sees it until it's bought). Press **See it in the shed** to hide the page and look, then **Back to the upgrades** (or Esc). Closing the page, or picking another upgrade, puts the shed back as it is. Colours cost nothing extra when you buy; to change a finish you already have, pick new choices and press **Change it**, which costs 5% of its price (at least £250, at most £5,000) from the garage's money. In co-op the looks are the host's shed's and everyone sees them, and they're kept in the save (older saves keep the standard looks).

| Finish | Choices (standard first) |
| --- | --- |
| Painted epoxy floor | Colour: charcoal, slate grey, racing red, garage blue, racing green, sand, gloss white, jet black. Effect: speckled flake, metallic swirl, plain gloss, satin |
| LED lighting | Light colour: cool white, daylight, neutral white, warm white. Wall strip: the lights' colour, red, amber, green, blue, purple or pink. Strip effect: steady, slow pulse, colour cycle |
| Wall cladding | Wall panels: white, light grey, cream, anthracite, garage blue, racing red, racing green. Chequer plate: brushed aluminium, black, copper, painted red. Pinstripe: red, blue, yellow, green, white, black or none |
| Branded signage | Neon colour (blue, red, pink, green, orange, purple, white), light box edge colour, neon effect: steady, old flicker or slow pulse |
| Crew lounge | Sofa leather, rug and neon sign colours |
| Showroom finish | Floor: black and white, red and black, grey and white or blue and white chequer, mirror black, gallery white. Tile size: 30 cm, 60 cm, 1.2 m. Ceiling: honeycomb, fine or giant honeycomb. Ceiling light colour. Trim: chrome, gold, black chrome, red |

### Weather

The weather changes by itself every few minutes between **clear skies**, **cloudy**, **fog** and **rain**, drifting from one to the next over about 40 seconds. Clouds grey the sky and dim the sun, and the shadows go soft; fog closes in so you see only a short way; rain falls round you, soaks the roads and the yard so they go darker and shiny, and wet tarmac grips a little less (about 15%), so brake and lean with care. Once it stops the roads dry out over a few minutes. You hear the rain outside and drumming on the roof when you're in the shed, and it never rains indoors.

In the Esc menu's **Settings** tab, **Weather** picks **Changes by itself** or holds one kind (always clear, cloudy, foggy or raining). In co-op the host's weather is everyone's. The weather is saved with the shed.

### Graphics settings

The Esc menu's **Graphics** tab sets how the game looks and how fast it runs. Everything except the rendering driver changes straight away, and it's all saved with your settings.

- **Quality preset**: **Low**, **Medium**, **High** (the default) or **Ultra** set the shadows, detail, draw distance, lighting, effects and anti-aliasing together (Low also renders at 75% with FSR 1). Change any one of those yourself and the preset says **Custom**.
- **Display**: **Window mode** (windowed, borderless fullscreen or exclusive fullscreen); **Resolution**, from 1280 x 720 to 3840 x 2160 (4K) in 16:9, 16:10 and 21:9 sizes: in a window it's the window's size (never bigger than the screen), in fullscreen the screen keeps its own size and this sets how sharp the 3D view renders while the menus stay crisp; **Monitor** (when you have more than one); **VSync** (off, on, adaptive or mailbox); a **frame-rate cap** (30, 60, 120, 144, 165, 240 or unlimited); **Field of view** (60 to 110 degrees; the riding cameras move by the same amount); **Brightness**; and **Show the frame rate**, a small FPS counter in the top left corner to help you tune.
- **Upscaling**: **Render scale** from 50% to 100% renders the 3D view smaller and scales it back up (faster), and 100% to 200% renders it bigger and shrinks it (supersampling: sharp but slow). The **Upscaler** for below 100% is **AMD FSR 2.2** (temporal: the best looking), **FSR 1.0** (fastest) or plain bilinear, with a **Sharpness** slider. At exactly 100% no upscaler runs. **Off** turns upscaling off altogether: the 3D view always renders at your screen's own resolution, whatever the render scale says.
- **DLSS?** No. The Godot engine the game is built on (4.6) doesn't include NVIDIA DLSS or Intel XeSS. FSR 2.2 is its temporal upscaler and works on NVIDIA, AMD and Intel cards alike.
- **Anti-aliasing**: **MSAA** (off, 2x, 4x, 8x), **TAA** (smoothest, a little soft; FSR 2.2 does its own, so TAA is skipped while it upscales) and **screen-space AA** (off, FXAA or SMAA).
- **Quality**: **Shadows** (low to ultra), **Detail level** (how far away bikes and parts keep their detailed shape, and texture sharpness at an angle), **Draw distance** (50% to 200%), **Global illumination** (off, SSIL or SDFGI), **Volumetric fog and light**, **Volumetric clouds**, **Screen-space reflections**, **Ambient occlusion**, **Glow** and **Avatar shadow** (whether you, the other players, the staff, customers and townsfolk cast shadows; off saves a little in a busy shed or town).
- **Ray tracing?** Godot 4.6 has no hardware ray tracing (RTX / DXR). The **Ray-traced lighting** switch honestly turns on SDFGI, Godot's real-time global illumination that bounces sun, sky and lamp light round the shed; off uses SSIL, a cheaper screen-space version.
- **Motion blur**: there isn't any, so it's always off. **HDR**: the game always renders in HDR and tone-maps it for your screen, but HDR displays (HDR10 output) aren't supported by the engine yet.
- **Rendering driver**: **Vulkan** (the default) or **DirectX 12** on Windows. The driver is picked when the game starts, so the tab says **restart to apply**; if DirectX 12 won't start on your PC the game falls back to Vulkan by itself and the tab tells you. The choice is written to `graphics_override.cfg` in the game's user folder (`%APPDATA%\Godot\app_userdata\Torque Shed` on Windows), which the game reads at start-up; delete it to go back to Vulkan. Nothing extra needs shipping with the exe: the official Godot 4.6 Windows export templates include DirectX 12.

Settings files from before this tab carry on: if "high quality lighting" was off, you start on the Low preset.

### Lighting

The game uses Godot's best lighting on the Forward+ renderer, all set from the **Graphics** settings in the Esc menu:

- **Global illumination** (SDFGI, or the lighter SSIL, or off): light bounces. Sun through the open roller door spills warm light across the shed floor and up the walls, and the lamps light the room round them, not just what's under them.
- **Volumetric clouds** (high, low or off): real 3D clouds 1.5 to 3 km up, lit by the sun with bright silver edges when you look towards it and dark, heavy bases, drifting with the wind. A few fair-weather clouds on a clear day, a broken sky when it's cloudy, a low, dark deck in the rain; the moon lights them at night. Off draws the older flat cloud layer.
- **Volumetric fog** (high, low or off): the air itself catches the light. Morning sun makes soft shafts through the dust hanging in the shed, the shed's lamps make soft cones of light, the paint shop fills with haze while you spray and clears again, the dyno room fills with exhaust haze, and fog and rain thicken the air outside. Headlights stay a soft glow in the night air, not a hard beam.
- **Shadows** (low to ultra): sharper and further away the higher you go; at high and above the yard floodlights cast shadows too, so their light breaks into rays at night, and ultra softens shadow edges with distance.
- **Reflections** on paint, chrome and wet roads, **ambient occlusion**, and **glow** round anything bright: tail lights, neon, screens and the sales sign.

Your eyes adjust too: walk out of the bright yard into the shed with the lights off and it starts dark, then slowly opens up; step back into daylight and it clamps down quickly. On the simpler renderer (and on low settings) the game keeps a plainer look: flat clouds, no bounce light and no light in the air.

### Sound

Most sounds are made by the game itself as it starts, modelled on how the real thing makes its noise, and kept in a cache file so later starts are quick. A few are **recordings** (in `audio/sfx`): the wrench ratcheting, the sandblaster, the dyno room's cooling fan winding up and running, the roller door's motor, the sales office door chime and phone, the light switches, the gear levers and the horns. Each has several takes, picked at random and never the same one twice running; if a recording's file is missing the game makes its own sound instead. The sales PC's **cash till** (a buyer's offer or answer) is made by the game for now, until a recording is added as `sale_offer`. Nothing to set up: the Esc menu's sound effects slider covers all of it.

- **Variety**: every knock, clink, footstep and part going down comes in several versions, played at random with a touch of pitch and level, and never the same one twice running. Tools pick up their loop at a different point each time.
- **Parts landing**: putting a part down sounds of what it's made of and what it lands on: steel clanks and rings on the concrete floor, knocks on the wooden bench top, rings on for a while on a steel shelf or machine, and thuds dead on the grass outside; plastic clacks, tyres thump and bounce, seats and gear flop, delivery boxes thud.
- **Tools and machines**: the ratchet's pawl clicking on the backswing and the bolt creaking round; the grinder spinning up, dropping in pitch as it bites with a rasp and spark crackle, and winding down; the pressure washer's pump pulse and jet; the parts washer's pump, splash and bubbles; the spray can's sputtering hiss and the spray gun's air rush; the sandblaster's roar and grit hiss; the tyre changer's motor and the rubber groaning, then the bead popping on; the dyno drum whining with its speed; the roller door's motor, chain and slats with a clunk at each end.
- **Footsteps** sound of the floor: concrete (or the epoxy floor once it's bought, with the odd squeak), tiles in the paint shop and the showroom, wooden stairs and carpet upstairs in the sales office, the steel mezzanine, and outside tarmac, gravel on the dirt, grass, and splashes in puddles when it's wet. You hear other players' footsteps too.
- **Rooms**: each room has its own acoustics: the shed's hard concrete, the small tiled paint booth, the cluttered store, the dyno room, the showroom's glass, the carpeted office, and outside nearly dry with an echo back off the shed wall. Sounds from another room come through muffled and quieter.
- **Ambience**: a low room tone indoors (the showroom's air conditioning), the strip lights humming (the LED upgrade's are quieter) and ticking on when switched on, the roof creaking now and then, and the air compressor in the shed's back corner cycling on and off (sooner while the spray gun or sandblaster is drawing air). Outside there's wind, distant traffic, a burst of birdsong now and then by day (a few seconds of it, then quiet for a minute or so, and less round midday than morning and evening) and crickets at night, quieter in the rain and muffled from indoors. The sales office's front doors whirr open and thump shut.

### Money

There are two kinds of money: **your own cash**, kept with your character like your XP (so it goes with you to any shed), and **the business**: the garage's own account, kept with the shed. A new shed's business opens with **£10,000**. Your cash shows top right, next to your level, and pops up green ("+£4 Restoring") as it comes in.

**Wages**: every job that earns XP also pays a small wage (a few pounds for spanner work, more for restoring, spraying and fitting tyres, and a good lump for finishing a build or restoring a bike to max health). Like the XP, doing the same job again straight away pays less and less, and the one-offs pay once. The business takes its **cut** of every wage (20% to start); you get the rest. Riding pays XP, not wages. The real money is in selling bikes (and, later, contracts).

**Buying and selling**: parts cost money now, from the business's account: plain parts are cheap, fancy and light ones dear, engines by their size. If the business can't afford a part, the parts computer says so and nothing comes. A **project bike** costs a bit more than it would fetch as it comes, so the profit is in restoring it. The parts computer's **Sell** aisle sells **loose parts** (on the floor, a bench or shelf, or in your hands; an engine goes with whatever is fitted to it) and, to the trade, **whole bikes standing on a showroom display stand** (see Selling bikes for buyers who pay more). A dealer pays 70% of what a thing is worth now, and worn, rusty parts are worth far less than good ones, so restore before you sell. A complete bike fetches 15% more, and 15% more again with petrol and oil in it, ready to ride. The money goes to the business; whoever sells gets the XP and a small commission.

**The Money tab** (Esc menu): your cash and the business's, and:
- **Send money**: pick a mate or the business and an amount: it comes out of your own cash. Anyone can pay the business.
- **Take money out**: only the **garage owner** can move money from the business into their own cash.
- **Garage settings** (the host only; greyed for everyone else, and saved with the shed): the business's **cut** of wages (0 to 100%) and who the **garage owner** is (the host to start).
- **Bank loans**: the owner can borrow £5,000 (10 days), £20,000 (20 days) or £50,000 (30 days), up to £100,000 owed in all. Every in-game day (when the clock passes midnight) the bank adds a little interest to what's owed and takes the day's repayment from the business. **Pay** a thousand off, or **Clear it**, any time: paying early saves interest. If the business can't make a repayment it's **missed**: a fee goes on the loan and the bank won't lend again until that loan is paid off. With the day and night cycle off, days don't pass and nothing is due.
- **Money over time**: graphs of your own cash and of the business's account. Pick **Minutes**, **Hours**, **Days**, **Weeks**, **Months** or **Years** of in-game time (the last hour, 24 hours, week, 12 weeks, 12 months or 5 years); a month is 30 in-game days and a year 365. The choice is kept with your settings and the My money and Garage money TV channels show the same range. Graphs start from when you first play this version: older saves have no earlier history.
- **The ledger**: the business's last 100 movements (sales, purchases, cuts of wages, money sent in, repayments), newest first, and your own money's recent log.

In co-op the host keeps the books: everyone's wages, transfers and the business are checked by the host, and your cash is kept on your own PC.

### The Shop: rider gear and trinkets

The Esc menu's **Shop** tab spends **your own money** (not the garage's). Pick a category along the top, then an item in the list: the turntable on the right shows your rider wearing it with the rest of your gear, so you can try it on before you buy.

- **Rider gear**: helmets, jackets, trousers, boots and gloves, six to eight designs of each from made-up brands (Kestrel race leathers, Mudlark motocross kit, Ironside leathers, Fenway waxed cotton, Beacon hi-vis, Strata adventure gear and more), from £20 gloves to a £620 carbon race helmet. Helmets come as full-face, race (with a spoiler), open-face, pudding basin with goggles and motocross (peak, chin bar and goggles); jackets and trousers come in stripes, hoops, panels, chequers, hi-vis bands and carbon. **Buy and wear** pays and puts it on; **Wear** changes into something you already own. Everyone starts in free shed overalls in their crew colour, work boots, work gloves and a cap (a plain lid in your colour on the bike).
- What you own and wear is kept with your character, so it goes with you to every shed. Everyone sees your gear: walking about the shed, on the bike and when you come off it.
- **Trinkets** for the shed: a bobblehead racer, a biker gnome, a potted plant, a framed photo, a lava lamp, a station wall clock and digital wall and desk clocks that keep the shed's in-game time (the hands and the display move with the day), a gold trophy, a chequered flag rug, a toolbox radio, a mini bike model and a pink neon TORQUE SHED sign. A trinket you buy is delivered outside the roller door and then belongs to the shed: press **F** on it to pick it up and carry it (the mouse wheel holds it further out, the rotate keys turn it, R toggles snapping), hold it over the workbench or another bench to put it down on top, or against a wall for the clock, photo and neon sign, and **F** puts it down. Hold the scrap key while carrying one to get rid of it. Trinkets are saved with the shed.

### 3D part previews in the shop

Pick a part on the parts computer and it turns slowly in 3D at the top of its page, drawn just as it looks on a bike, so you can see what you're buying. Drag it with the mouse to turn it yourself. In the Sell aisle the loose part you'd be selling is shown as it is now, rust, box and all. Shed kit has no preview.

### Trolleys

The parts computer sells two **trolleys** (Shed aisle, Storage and benches): a **parts trolley** with a waist-high lipped deck and a shelf underneath, and a long, low **flatbed trolley** for the heavy stuff. Load the deck like a workbench: look at it with a part or a box in your hands and put it down, as many as fit. Then take hold of the trolley with F (by its handle or anywhere on it), walk it where you want it and press F to let go: everything on the deck rides along with it, so a whole delivery comes in from the yard in one trip. Take things off again at the other end like off any bench. In co-op everyone sees the trolley move with its load, and the shed saves it where it was left, loaded.

### Who ordered which box

Every box ordered from the parts computer (and from a blueprint) has a yellow sticky note on its lid and front saying who it's **for**: the name of the player who ordered it. Look at a box and the panel says "Ordered by ..." too. In co-op it's easy to see whose boxes are whose in the delivery area. Unpack a box and the note goes with it.

### The parts list in geometry mode

Geometry mode (F2) has a list of the bike's parts down the left: each row is a slot and the part in it ("Fork: Showa USD forks"). Click a row to select that part, the same as clicking it on the bike (handy for small or hidden parts). Clicking a part on the bike lights up its row, and parts you've moved are marked with a *.

### Ordering a bike in a style

Next to **Order a project bike** on the parts computer is a style picker: pick one of the 14 styles (cafe racer, bobber, chopper, cruiser, scrambler, adventure bike, tourer, sports bike and the rest) and the button orders that style ("Order a cruiser"). The bike is found to order: it's built round the style's reference bike, with every part on it made for that style (the style's own parts pack first), tyres to suit its rims and the bolt-on bits that go with it, so it reads as a proper example of the style. It turns up in a free bay as worn as any project bike, named "Cruiser project" and so on, and costs the business 15% more than an ordinary project bike in the same state. Any style orders an ordinary project bike, as before.

### Emotes

On foot, press **B** for the emote bar, then **1** to **6**: **wave**, **thumbs up**, **point**, **shrug**, **cheer** and **dance** (B again closes it). Or do one straight away with **F5** to **F10**. The rest of the crew sees your figure do it, with what you're doing over your head; a point aims at whatever your crosshair is on. When you **ping** something (G or middle mouse), your figure points at it for the crew as well as it lighting up. Every key can be changed in the Key bindings tab.

On a bike, **N** (the right stick click on a pad) nods to a biker you're passing; hold it and your rider takes their left hand off the bar for a wave. The crew see your rider do both on your bike, and a biker in the traffic nearby nods back.

### Debug tab

The Esc menu's **Debug** tab is for trying things out: **Reset my XP** (back to level 1 with no upgrades, skills or goals), **Max my XP** (top level, every point to spend), **Reset everyone's XP** (host only: every player in the shed), **Reset my money**, **Max my money**, **Reset garage money** and **Give the garage £1,000,000** (the last two host only); for contracts (host only) **Send a customer**, **Send a bespoke customer**, **Send a batch order**, **Send a test ride** and **Reputation +5**. Every reset asks first. Your money is kept with your character and the garage's with the shed, and both show on the TVs' **My money** and **Garage money** pages.

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
| `scripts/garage_upgrades.gd`, `workshop_upgrades.gd`, `upgrades_panel.gd` | Garage upgrades: the catalogue and rules, building them onto the shed (the extension bays and their bike lifts, the annex and its mezzanine, the crew lounge upstairs), and the parts computer's Garage upgrades page |
| `scripts/upgrade_looks.gd`, `look_preview.gd` | Garage upgrade colours and styles: how each choice looks on the shed, and the preview room on the Garage upgrades page |
| `scripts/walker.gd` | First-person player, tools, targeting and hold-to-work |
| `scripts/placement.gd` | Snapping equipment square and flush to walls and corners |
| `scripts/dashboard.gd`, `shed_tv.gd`, `tv_channels.gd` | The shed's screens and wall TVs, and their channels and pages |
| `scripts/whiteboard.gd`, `board_data.gd`, `board_print.gd` | The shared whiteboard: drawing on it, pictures from players' PCs, and its marks kept in the shed state; whiteboard posters |
| `scripts/settings.gd`, `keybind_tab.gd` | Settings, every key binding and rebinding them in the Esc menu |
| `scripts/graphics.gd`, `graphics_tab.gd` | Graphics settings: presets, putting them on the window, viewport and cameras, the driver override and FPS counter; the Esc menu's Graphics tab |
| `scripts/bike_build.gd` | Turns parts, their condition and the tune into stats: mass, torque curve, grip, brakes, top speed, dyno runs |
| `scripts/sales_office.gd` | The sales office: its forecourt, showroom plinths, reception, viewing area, kitchen, stairs and mezzanine office with the sales PC, the sliding doors and the shop bell |
| `scripts/coffee_shop.gd`, `coffee_shop_building.gd`, `coffee_view.gd`, `coffee_visitor.gd`, `coffee_panel.gd` | The coffee shop next door: its opening hours, bikers and their bikes, offers on them and the counter's trays (host-run, saved with the shed); the building, terrace and car park; the bikers riding in, sitting and leaving, the barista and the trays put down; the menu and offer card |
| `scripts/sales.gd`, `sales_view.gd`, `sales_computer.gd` | Selling bikes: pricing and appraisal, online buyers' offers and counter-offers, part-exchange buyers and deals (host-run, saved with the shed); the buyers and their bikes in the showroom, the till and the price cards; the sales PC's pages |
| `scripts/dyno_room.gd`, `dyno_graph.gd`, `tuning_computer.gd` | The tuning room and its rolling road, the dyno graphs, and the tuning desk |
| `scripts/bike_model.gd` | Builds the visible bike part by part, with rust and grime, and each part's own fit from geometry mode |
| `scripts/geometry_mode.gd`, `geo_gizmo.gd`, `blueprint_tab.gd` | Geometry mode (fitting a bike's parts with move, rotate and scale handles), the handles and their maths, and the Esc menu's Blueprints tab |
| `scripts/bike_copy.gd`, `bike_copy_view.gd`, `bike_order_panel.gd`, `parked_bike.gd` | Order one of these and Copy its blueprint for any bike looked at: the requests and what's on order, which bike the crosshair's on, the bike's card, and the bikes parked at the adventure cafes |
| `scripts/tyre_game.gd` | The tyre-fitting game on the tyre changer |
| `scripts/blast_game.gd`, `blast_marks.gd`, `blast_hud.gd`, `blast_detail.gd`, `blast_grit.gd` | The sandblasting game in the blast cabinet: the coverage, the satin bare-metal mask and its shader, the live readout and the scan, the close-up engine detail, and the bare metal kept on each part and drawn wherever the engine goes, and the sand particles held inside the cabinet (protective coats, and a fully blasted engine coming out as new, are in `shed_state.gd`) |
| `scripts/bike.gd` | Rigid-body bike with ray-cast suspension, the tyres on the road, the front end turning about its raked steering axis, the rider (steering by bar torque, riding realism), engine, clutch and gearbox |
| `scripts/tyre_model.gd` | The tyres: a Magic Formula with combined slip, load sensitivity, camber thrust, relaxation length and the round profile, from each tyre's catalogue numbers |
| `scripts/ride_telemetry.gd`, `telemetry_overlay.gd`, `telemetry_graph.gd` | The ride's telemetry recorder, the F3 overlay while riding, and the strip charts (the overlay's and the dyno desk's Last ride tab) |
| `scripts/chase_camera.gd` | The riding cameras: the chase view you can swing round the bike, first person, the ride-by camera and the title screen orbit |
| `scripts/controls.gd` | Gamepad sticks and triggers, calibrated against stuck axes |
| `scripts/net.gd`, `remote_player.gd`, `remote_bike.gd` | Multiplayer and other players |
| `scripts/emotes.gd`, `emote_bar.gd` | Emotes: the poses other players see your figure do (and the point when you ping), and the emote bar |
| `scripts/part_preview.gd`, `order_note.gd` | The parts computer's turning 3D preview of a part; the "for" note on a delivery box naming who ordered it |
| `scripts/world.gd`, `world_layout.gd`, `world_terrain.gd`, `world_roads.gd`, `world_road_mesh.gd`, `world_yard.gd`, `world_props.gd`, `world_buildings.gd` | The riding map: the layout of roads, villages and farms; the height map, its chunked meshes and collision; road heights (grades, no jumps, flush junctions) and their meshes and markings; the yard's test area; trees, rocks, buildings, fences, armco, signs and lamps in batches |
| `scripts/daylight.gd`, `weather.gd` | Time of day, sky and lighting; the weather (clouds, fog, rain, wet roads, rain sounds) |
| `scripts/lighting.gd`, `cloud_sky.gd` | Graphics settings into GI, volumetric fog, fog volumes, shadows, glow and eye adaptation; the raymarched cloud sky shader |
| `scripts/debug_tab.gd` | The Esc menu's Debug tab: reset or max XP and money, give the garage a million, send a customer, raise the reputation |
| `scripts/money.gd`, `money_tab.gd`, `money_graph.gd` | Money: part and bike prices, selling, the business's bank (cut, owner, ledger, loans) and its requests; the Esc menu's Money tab; the money graphs over in-game time |
| `scripts/contracts.gd`, `mot.gd`, `contract_batch.gd`, `contract_test_ride.gd` | Contracts: customers, offers, goals, payouts and reputation (kept in `Shed.contracts`); the MOT inspection sheet; batch orders and manufacturer test rides |
| `scripts/customer.gd`, `contracts_view.gd`, `contract_panel.gd`, `contracts_tab.gd` | The customers riding in, parking and walking in to reception (and collecting finished bikes), the offer card and jobs list, and the Esc menu's Contracts tab |
| `scripts/progress.gd`, `ride_xp.gd`, `character_tab.gd`, `skill_tree_view.gd` | XP, levels, tool upgrades, skills and goals, kept in your own profile; riding XP; the Character tab |
| `scripts/rider_gear.gd`, `rider_figure.gd`, `trinkets.gd`, `shop_tab.gd` | Rider gear (catalogue, owned and worn in your profile), drawing the avatar in it on foot and on the bike, trinkets for the shed, and the Esc menu's Shop tab |
| `scripts/engine_synth.gd`, `engine_bank.gd`, `engine_sound.gd`, `exhaust_flame.gd` | Engine sound: the synthesis (firing order and crank phasing, header and silencer resonances, intake and airbox, valve train, clutch rattle, two-stroke ring-ding), the per-engine bank of seamless loops baked on a worker thread, and the 3D player that crossfades and pitches them and adds pops, bangs, shifts, the starter and the backfire flame. `tests/engine_render.tscn` renders them to .wav files |
| `scripts/sfx.gd` | Playing the shed's sounds: the recordings that stand in for made ones (`audio/sfx`), variants without repeats, impacts by material, footsteps by floor, machine start and stop sounds, room reverb and through-wall muffling, the volume buses and the sound cache |
| `scripts/sfx_synth.gd` | Synthesising every shed sound from physical models (modal metal, contact impacts, motors under load, water and bubbles) |
| `scripts/sfx_ambience.gd` | The shed's ambience: room tone, light hum, the compressor's cycle, creaks, the sliding doors, the phone ringing for a new customer, wind, traffic, birds in bursts and crickets |
| `scripts/horn_audio.gd` | Bike horns: playing a horn's recordings (held, once or repeating), or synthesising the rest |
| `audio/sfx/` | The recorded sounds: mono Ogg Vorbis, trimmed, loops crossfaded so they repeat without a seam |
| `scripts/shed_radio.gd`, `radio_stream.gd`, `mp3_stream_decoder.gd` | The shed radio: streams an MP3 station over HTTP(S) and decodes it gaplessly |

Built with [Godot 4.6](https://godotengine.org) and Jolt physics.

## Development

```sh
godot --headless --path . --import
godot --headless --fixed-fps 120 --path . res://tests/test_runner.tscn   # physics, world and session tests
tests/mp_test.sh                                                          # host and client on one machine
godot --headless --path . --export-release "Windows Desktop" build/windows/TorqueShed.exe
godot --headless --path . res://tools/export_glb.tscn -- --out=DIR             # five finished bikes as .glb (GlbExport)
```
