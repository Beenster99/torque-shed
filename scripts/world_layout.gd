class_name WorldLayout
extends RefCounted
## The hand-laid plan of the riding map, which the generator dresses with land, roads and
## props: where the villages and farms are, and the line of every road and track. Roads are
## drawn as smooth curves through these points; their heights follow the land (see WorldRoads).
##
## Map axes: +x is east, -z is north. The shed's yard is at (0, 100), the mountains are along
## the north edge, and the map is MAP_HALF either way from the middle.

## Villages and farmyards: centre, radius of the flat ground they stand on, kind and name.
const SITES := [
	{"name": "Ashby", "kind": "village", "at": Vector2(860.0, 430.0), "r": 170.0},
	{"name": "Thornley", "kind": "village", "at": Vector2(-950.0, 250.0), "r": 170.0},
	{"name": "Kettle Bridge", "kind": "village", "at": Vector2(150.0, 1250.0), "r": 160.0},
	{"name": "High Moor", "kind": "village", "at": Vector2(-1150.0, -660.0), "r": 120.0},
	{"name": "Northfield Farm", "kind": "farm", "at": Vector2(470.0, -330.0), "r": 95.0},
	{"name": "Brook Farm", "kind": "farm", "at": Vector2(-480.0, 690.0), "r": 95.0},
	{"name": "Eastcote Farm", "kind": "farm", "at": Vector2(1460.0, -150.0), "r": 95.0},
	{"name": "Lower Ley Farm", "kind": "farm", "at": Vector2(1230.0, 1120.0), "r": 95.0},
	{"name": "Westmoor Farm", "kind": "farm", "at": Vector2(-1520.0, 1080.0), "r": 95.0},
	{"name": "Hill Farm", "kind": "farm", "at": Vector2(-330.0, -620.0), "r": 85.0},
]

## Every road and track. kind: "tarmac" or "dirt". hw: half the width of the running surface.
## grade: the steepest climb allowed (rise over run). hard: a rough mountain track.
## start / end: the name of a road this one leaves from or joins (snapped onto it).
## pts: the line it follows. The loop is closed; everything else is open.
const ROADS := [
	{"name": "loop", "label": "The Loop", "kind": "tarmac", "hw": 4.0, "grade": 0.1, "closed": true, "pts": [
		Vector2(-45.0, 133.5), Vector2(-20.0, 134.4), Vector2(0.0, 137.8), Vector2(20.3, 138.1), Vector2(40.3, 135.4),
		Vector2(59.1, 130.1), Vector2(76.5, 123.2), Vector2(100.0, 111.0), Vector2(130.0, 98.0), Vector2(155.0, 76.0),
		Vector2(165.0, 46.0), Vector2(160.0, 16.0), Vector2(174.0, -14.0), Vector2(196.0, -42.0), Vector2(200.0, -80.0),
		Vector2(182.0, -114.0), Vector2(146.0, -136.0), Vector2(110.0, -141.0), Vector2(82.0, -126.0), Vector2(50.0, -133.0),
		Vector2(14.0, -160.0), Vector2(-26.0, -174.0), Vector2(-66.0, -168.0), Vector2(-100.0, -148.0), Vector2(-140.0, -122.0),
		Vector2(-176.0, -96.0), Vector2(-192.0, -56.0), Vector2(-178.0, -16.0), Vector2(-196.0, 24.0), Vector2(-186.0, 66.0),
		Vector2(-150.0, 102.0), Vector2(-110.0, 126.0), Vector2(-75.0, 135.0)]},
	{"name": "east", "label": "Ashby", "kind": "tarmac", "hw": 3.5, "grade": 0.09, "start": "loop", "pts": [
		Vector2(200.0, -62.0), Vector2(250.0, -58.0), Vector2(340.0, -30.0), Vector2(450.0, 40.0), Vector2(560.0, 140.0),
		Vector2(680.0, 270.0), Vector2(790.0, 380.0), Vector2(870.0, 440.0), Vector2(950.0, 520.0), Vector2(1060.0, 640.0),
		Vector2(1180.0, 780.0), Vector2(1250.0, 960.0), Vector2(1230.0, 1110.0), Vector2(1100.0, 1230.0), Vector2(900.0, 1300.0),
		Vector2(650.0, 1320.0), Vector2(420.0, 1280.0), Vector2(250.0, 1250.0), Vector2(100.0, 1260.0), Vector2(-60.0, 1300.0)]},
	{"name": "south", "label": "Kettle Bridge", "kind": "tarmac", "hw": 3.5, "grade": 0.09, "start": "loop", "end": "east", "pts": [
		Vector2(157.0, 72.0), Vector2(190.0, 110.0), Vector2(240.0, 200.0), Vector2(262.0, 320.0), Vector2(250.0, 460.0),
		Vector2(210.0, 660.0), Vector2(180.0, 860.0), Vector2(170.0, 1050.0), Vector2(160.0, 1180.0), Vector2(158.0, 1256.0)]},
	{"name": "west", "label": "Thornley", "kind": "tarmac", "hw": 3.5, "grade": 0.09, "start": "loop", "pts": [
		Vector2(-195.0, 30.0), Vector2(-240.0, 36.0), Vector2(-380.0, 62.0), Vector2(-560.0, 122.0), Vector2(-760.0, 200.0),
		Vector2(-950.0, 252.0), Vector2(-1120.0, 330.0), Vector2(-1300.0, 500.0), Vector2(-1420.0, 750.0), Vector2(-1470.0, 960.0),
		Vector2(-1500.0, 1080.0)]},
	{"name": "brook", "label": "Brook Farm", "kind": "tarmac", "hw": 3.0, "grade": 0.09, "start": "west", "end": "east", "pts": [
		Vector2(-910.0, 240.0), Vector2(-890.0, 330.0), Vector2(-820.0, 470.0), Vector2(-660.0, 600.0), Vector2(-500.0, 668.0),
		Vector2(-330.0, 760.0), Vector2(-180.0, 940.0), Vector2(-60.0, 1150.0), Vector2(-40.0, 1290.0)]},
	{"name": "north", "label": "High Moor", "kind": "tarmac", "hw": 3.5, "grade": 0.09, "start": "loop", "pts": [
		Vector2(-28.0, -174.0), Vector2(-40.0, -230.0), Vector2(-90.0, -330.0), Vector2(-190.0, -450.0), Vector2(-330.0, -590.0),
		Vector2(-540.0, -640.0), Vector2(-800.0, -660.0), Vector2(-1000.0, -665.0), Vector2(-1150.0, -650.0), Vector2(-1260.0, -640.0)]},
	{"name": "northeast", "label": "Northfield", "kind": "tarmac", "hw": 3.5, "grade": 0.09, "start": "north", "pts": [
		Vector2(-85.0, -322.0), Vector2(0.0, -350.0), Vector2(200.0, -360.0), Vector2(460.0, -350.0), Vector2(700.0, -400.0),
		Vector2(950.0, -480.0), Vector2(1150.0, -580.0), Vector2(1300.0, -690.0), Vector2(1380.0, -760.0), Vector2(1430.0, -830.0)]},
	{"name": "eastcote", "label": "Eastcote", "kind": "tarmac", "hw": 3.0, "grade": 0.09, "start": "northeast", "end": "east", "pts": [
		Vector2(1260.0, -660.0), Vector2(1350.0, -520.0), Vector2(1420.0, -330.0), Vector2(1440.0, -160.0), Vector2(1380.0, 40.0),
		Vector2(1240.0, 230.0), Vector2(1080.0, 420.0), Vector2(1000.0, 570.0)]},
	{"name": "pass", "label": "Moor Pass", "kind": "tarmac", "hw": 3.5, "grade": 0.095, "start": "north", "end": "northeast", "pts": [
		Vector2(-1140.0, -652.0), Vector2(-1080.0, -720.0), Vector2(-980.0, -800.0), Vector2(-840.0, -850.0),
		Vector2(-600.0, -880.0), Vector2(-390.0, -900.0), Vector2(-345.0, -918.0), Vector2(-332.0, -946.0), Vector2(-355.0, -968.0),
		Vector2(-500.0, -978.0), Vector2(-700.0, -988.0), Vector2(-742.0, -1004.0), Vector2(-748.0, -1032.0), Vector2(-720.0, -1050.0),
		Vector2(-550.0, -1062.0), Vector2(-385.0, -1076.0), Vector2(-342.0, -1092.0), Vector2(-336.0, -1122.0), Vector2(-364.0, -1140.0),
		Vector2(-520.0, -1152.0), Vector2(-640.0, -1166.0), Vector2(-682.0, -1182.0), Vector2(-684.0, -1212.0), Vector2(-652.0, -1228.0),
		Vector2(-450.0, -1242.0), Vector2(-200.0, -1266.0), Vector2(0.0, -1276.0), Vector2(150.0, -1270.0), Vector2(350.0, -1250.0),
		Vector2(560.0, -1215.0), Vector2(900.0, -1172.0), Vector2(940.0, -1160.0), Vector2(944.0, -1132.0), Vector2(905.0, -1118.0),
		Vector2(620.0, -1080.0), Vector2(582.0, -1070.0), Vector2(578.0, -1042.0), Vector2(615.0, -1030.0),
		Vector2(930.0, -990.0), Vector2(970.0, -978.0), Vector2(972.0, -950.0), Vector2(935.0, -938.0),
		Vector2(650.0, -905.0), Vector2(612.0, -895.0), Vector2(610.0, -867.0), Vector2(648.0, -855.0),
		Vector2(1000.0, -800.0), Vector2(1180.0, -720.0), Vector2(1290.0, -688.0)]},
	# Dirt tracks.
	{"name": "woods", "label": "Woods trail", "kind": "dirt", "hw": 2.2, "grade": 0.2, "start": "west", "end": "south", "pts": [
		Vector2(-380.0, 62.0), Vector2(-392.0, 120.0), Vector2(-400.0, 180.0), Vector2(-330.0, 300.0), Vector2(-180.0, 380.0),
		Vector2(0.0, 362.0), Vector2(150.0, 336.0), Vector2(258.0, 330.0)]},
	{"name": "northfield", "label": "Northfield climb", "kind": "dirt", "hw": 2.0, "grade": 0.3, "hard": true, "start": "northeast", "end": "north", "pts": [
		Vector2(460.0, -350.0), Vector2(450.0, -470.0), Vector2(390.0, -640.0), Vector2(330.0, -820.0), Vector2(270.0, -980.0),
		Vector2(150.0, -1080.0), Vector2(20.0, -1030.0), Vector2(-80.0, -900.0), Vector2(-200.0, -760.0), Vector2(-300.0, -640.0),
		Vector2(-320.0, -600.0)]},
	{"name": "ridge", "label": "Ridge run", "kind": "dirt", "hw": 1.9, "grade": 0.34, "hard": true, "start": "pass", "end": "pass", "pts": [
		Vector2(0.0, -1276.0), Vector2(-25.0, -1330.0), Vector2(-150.0, -1365.0), Vector2(-350.0, -1390.0), Vector2(-600.0, -1370.0), Vector2(-850.0, -1300.0),
		Vector2(-1000.0, -1180.0), Vector2(-1080.0, -1000.0), Vector2(-1050.0, -870.0), Vector2(-990.0, -805.0)]},
	{"name": "easthills", "label": "East hills", "kind": "dirt", "hw": 2.2, "grade": 0.22, "start": "eastcote", "end": "eastcote", "pts": [
		Vector2(1180.0, 300.0), Vector2(1260.0, 330.0), Vector2(1380.0, 330.0), Vector2(1500.0, 300.0), Vector2(1650.0, 150.0),
		Vector2(1620.0, -40.0), Vector2(1460.0, -150.0)]},
	{"name": "river", "label": "River trail", "kind": "dirt", "hw": 2.2, "grade": 0.2, "start": "east", "end": "brook", "pts": [
		Vector2(100.0, 1260.0), Vector2(80.0, 1400.0), Vector2(-100.0, 1500.0), Vector2(-400.0, 1460.0), Vector2(-600.0, 1300.0),
		Vector2(-660.0, 1100.0), Vector2(-560.0, 920.0), Vector2(-330.0, 760.0)]},
	{"name": "peaks", "label": "Peak circuit", "kind": "dirt", "hw": 1.9, "grade": 0.34, "hard": true, "start": "northeast", "end": "eastcote", "pts": [
		Vector2(1430.0, -830.0), Vector2(1470.0, -960.0), Vector2(1440.0, -1150.0), Vector2(1540.0, -1330.0), Vector2(1720.0, -1250.0),
		Vector2(1800.0, -1020.0), Vector2(1760.0, -800.0), Vector2(1640.0, -640.0), Vector2(1500.0, -560.0), Vector2(1385.0, -490.0)]},
]
