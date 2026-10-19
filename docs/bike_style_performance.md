# Real-world performance by bike style

Reference figures used to tune each style's performance in the game. Medians are typical of current bikes of each
style. Most figures are manufacturer claims or typical published test values, accurate to about ±10%. Independent
tests are cited where they were found. Power is at the crank unless marked rwhp. Wet weight is fully fuelled.
mpg is UK (imperial), and UK mpg ÷ 1.201 = US mpg.

| Style | Example bikes | hp | Nm | Wet kg | Top mph | 0-60 s | 1/4 mile s | UK mpg | Tank L | Gears | CdA m² |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Classic | RE Classic 350, Bonneville T120, W800 | 47 (20-80) | 62 | 224 | 110 (75-120) | 5.5 (4.2-10) | 13.9 | 60 (55-95) | 14.5 | 5-6 | 0.60 |
| Cafe racer | Thruxton RS, Continental GT 650, R nineT Racer | 105 (47-110) | 112 | 214 | 130 (105-135) | 3.7 | 12.3 | 50 | 14.5 | 6 | 0.47 |
| Bobber | Bonneville Bobber, Scout Bobber, Street Bob | 94 | 106 | 255 | 115 | 4.0 | 12.9 | 48 | 12.5 | 5-6 | 0.65 |
| Chopper | Breakout 117, Softail Slim, customs | 100 | 165 | 308 | 115 | 4.0 | 12.8 | 43 | 16 | 6 | 0.78 |
| Cruiser | Fat Boy, Rebel 1100, Vulcan 900, Chief | 87 | 150 | 290 | 112 | 4.2 | 13.2 | 48 | 17 | 5-6 | 0.72 |
| Scrambler | Scrambler Icon, Scrambler 900/1200, R nineT Scrambler | 80 | 95 | 222 | 118 | 3.9 | 12.8 | 52 | 14 | 5-6 | 0.60 |
| Adventure | R1300GS, 890 Adventure, Africa Twin, Tiger 900 | 106 (101-145) | 106 | 226 | 130 | 3.4 | 11.9 | 51 | 20 | 6 | 0.65 |
| Tall roader | Versys 650/1000, V-Strom 650, Multistrada, Tracer 9 | 117 (66-170) | 93 | 219 | 140 (120-160) | 3.3 | 11.6 | 52 | 21 | 6 | 0.55 |
| Tourer | Gold Wing, R1250RT, K1600GT | 136 | 170 | 343 | 135 | 3.4 | 12.0 | 47 | 25 | 6-7 | 0.62 |
| Sports bike | R7, ZX-6R, CBR650R, Daytona 660 | 95 (73-127) | 68 | 200 | 145 (135-160) | 3.3 | 11.4 | 50 | 15 | 6 | 0.35 |
| Race bike | R1, Panigale V4, S1000RR, ZX-10R | 206 | 114 | 199 | 186 limited (~195 free) | 2.9 | 9.9 | 40 | 17 | 6 | 0.30 |
| Naked | Z900, MT-07/MT-09, Street Triple | 117 (73-128) | 85 | 190 | 145 (130-150) | 3.1 | 11.0 | 52 | 14 | 6 | 0.52 |
| Supermoto | 690 SMC R, 701 Supermoto, DR-Z400SM | 74 (39-74) | 73 | 158 | 110 (90-115) | 3.5 | 12.2 | 58 | 13 | 5-6 | 0.60 |
| MX bike | 450 SX-F, YZ250F, YZ450F, CRF450R | 54 rwhp (450) | 46 | 109 | 85, gearing-limited | ~3.0 | n/a | ~3.5 L/h | 6.5 | 5 | 0.65 |

## Rules of thumb

- **Top speed.** Wheel power = ½ρ·CdA·v³ + Crr·m·g·v, with ρ ≈ 1.2 kg/m³. Top speed scales with about (P/CdA)^⅓,
  so doubling power gives only about 26% more speed.
  - Superbike: 130 kW at the wheel with CdA 0.30 gives about 199 mph.
  - Naked: 85 kW with CdA 0.52 gives about 145 mph.
- **CdA by riding position.**
  - Tucked superbike: 0.28-0.32
  - Faired middleweight: 0.32-0.38
  - Half fairing or cafe racer: 0.45-0.5
  - Upright naked: 0.5-0.6
  - Adventure bike or tourer: 0.55-0.7
  - Cruiser or chopper: 0.65-0.85
- **Rolling resistance (Crr).**
  - Road tyres: 0.009-0.014
  - Knobbly tyres on tarmac: 0.02-0.03
  - Packed dirt: 0.03-0.05
  - Soft soil or sand: 0.06-0.15
- **Transmission loss.** Rear-wheel power is about 88-92% of crank power on chain drive and 85-88% on shaft or belt.
- **Fuel.** Real-world fuel use runs 10-20% worse than claimed.
- **Gearing.** On road bikes, top speed is limited by drag. MX bikes, with 5 close ratios and about 3.6:1 final
  drive, run out of revs first, at about 85 mph.

## Sources

- Cycle World dynos: [Rebel 1100](https://www.cycleworld.com/story/bikes/2021-honda-rebel-1100-dyno-test),
  [KTM 450 SX-F](https://www.cycleworld.com/2019-ktm-450-sx-f-dyno)
- [Dirt Rider KTM 450 SX-F dyno](https://dirtrider.com/story/tests/2022-ktm-450-sx-f-dyno-test)
- [BikeSocial R1300GS long-term test](https://www.bennetts.co.uk/bikesocial/reviews/bikes/long-term-test-bikes/bmw-long-term-test-bikes/bmw-r1300gs-2024-long-term-review)
- [Warwick wind-tunnel study on rider position](https://wrap.warwick.ac.uk/180779/1/WRAP-Effect-rider-position-energy-consumption-23.pdf)
- [Cycle World 1982 aerodynamics roundup](https://issues.cycleworld.com/article/1982/10/1/roundup)
- [Energy Reports 2021: motorcycle tyre rolling resistance](https://doaj.org/article/1b10d8e62ed148258b4f1a3aa2948c83)
- [Wikipedia: Yamaha YZF-R1](https://en.wikipedia.org/wiki/Yamaha_YZF-R1), [Kawasaki Z900](https://en.wikipedia.org/wiki/Kawasaki_Z900)

## The game's stock bikes against the real figures

These are the stock bikes from `Contracts.style_build`, as tuned in October 2026.
- **Ride 0-60:** a real full-throttle run on flat tarmac, with auto-shift and rider assist at 0.5.
- **Top mph:** the build's estimate.
- **mpg:** a steady 90 km/h in top gear, in UK gallons. The real figures are real-world averages.

`_test_style_performance` in `tests/run_tests.gd` keeps every style inside the real-world range.

| Style | hp (real) | Top mph (real) | Ride 0-60 s (real) | UK mpg (real) | Wet kg (real) |
|---|---|---|---|---|---|
| Classic | 54 (47) | 102 (110) | 5.3 (5.5) | 60 (60) | 211 (224) |
| Cafe racer | 98 (105) | 128 (130) | 5.3 (3.7) | 53 (50) | 195 (214) |
| Bobber | 85 (94) | 110 (115) | 5.8 (4.0) | 50 (48) | 231 (255) |
| Chopper | 91 (100) | 107 (115) | 5.9 (4.0) | 44 (43) | 240 (308) |
| Cruiser | 91 (87) | 109 (112) | 5.7 (4.2) | 46 (48) | 268 (290) |
| Scrambler | 77 (80) | 111 (118) | 5.1 (3.9) | 52 (52) | 208 (222) |
| Adventure | 101 (106) | 119 (130) | 5.3 (3.4) | 46 (51) | 252 (226; GS Adventure 269) |
| Tall roader | 114 (117) | 137 (140) | 3.8 (3.3) | 52 (52) | 213 (219) |
| Tourer | 153 (136) | 147 (135) | 4.3 (3.4) | 41 (47) | 277 (343) |
| Sports bike | 119 (95) | 156 (145) | 3.6 (3.3) | 62 (50) | 197 (200) |
| Race bike | 222 (206) | 186 (186) | 3.5 (2.9) | 43 (40) | 206 (199) |
| Naked | 124 (117) | 137 (145) | 3.9 (3.1) | 47 (52) | 201 (190) |
| Supermoto | 71 (74) | 109 (110) | 4.2 (3.5) | 54 (58) | 149 (158) |
| MX bike | 71 (63 crank) | 85 (85) | 5.8 on tarmac | 44 | 130 (109) |

**Known gap.** Launches are held back by tyre grip. The game's tyres give 0.9-1.2 on tarmac, a little below real
road tyres, and the ridden 0-60 times come out 0.3-2 s slower than magazine tests. The gap is widest for bikes on
vintage or dual-sport tyres. Closing it means retuning tyre grip, which would also change cornering and braking
everywhere.
