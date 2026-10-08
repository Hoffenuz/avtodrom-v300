#include "vehicle_params.h"

namespace avto {

namespace {

// Corner layout helper. Body frame = Godot's: origin on the ground centred
// between the axles, +x right, +y up, forward is -z.
void layout_wheels(VehicleParams &p, double wheelbase, double track_f, double track_r, double radius,
		double mount_above_center) {
	const double zf = -wheelbase * 0.5;
	const double zr = wheelbase * 0.5;
	const double xs[4] = { -track_f * 0.5, track_f * 0.5, -track_r * 0.5, track_r * 0.5 };
	const double zs[4] = { zf, zf, zr, zr };
	for (int i = 0; i < 4; ++i) {
		WheelParams &w = p.wheels[static_cast<size_t>(i)];
		w.x = xs[i];
		w.z = zs[i];
		w.y = radius + mount_above_center; // mount point height at static ride
		w.static_length = mount_above_center;
		w.steered = i < 2;
		w.driven = i < 2; // front-wheel drive; make_gazelle() drives the rear
		w.handbrake = i >= 2;
	}
}

} // namespace

VehicleParams make_nexia2() {
	VehicleParams p;
	p.id = "nexia2";
	p.mass = 1025.0 + 75.0;
	// Estimated from mass distribution (61 % front) and body dimensions.
	p.inertia = { 520.0, 1780.0, 1650.0 };
	// Wheel layout measured on the game model (pipeline/blender/build_nexia.py):
	// wheelbase 2480 mm, track 1421 mm — within 1.6 % of the maker's figures.
	p.center_of_mass = { 0.0, 0.50, -0.27 }; // 61/39 front/rear split
	p.drag_area = 0.34 * 1.92;
	p.wheelbase = 2.4802;
	p.track = 1.4212;
	p.abs = true;

	EngineParams &e = p.engine;
	e.torque_full = Curve{ { 0.0, 62.0 }, { 600.0, 86.0 }, { 1000.0, 97.0 }, { 1500.0, 106.0 }, { 2000.0, 113.0 },
		{ 2500.0, 119.0 }, { 3200.0, 123.0 }, { 3800.0, 121.0 }, { 4400.0, 116.0 }, { 5000.0, 109.0 },
		{ 5600.0, 101.0 }, { 6200.0, 88.0 }, { 7000.0, 60.0 } };
	e.inertia = 0.13;
	e.idle_rpm = 850.0;
	e.limiter_rpm = 6200.0;
	e.redline_rpm = 6000.0;

	p.clutch.max_torque = 190.0;

	GearboxParams &g = p.gearbox;
	g.type = TransmissionType::Manual;
	g.forward = { 3.545, 2.048, 1.346, 0.971, 0.763 };
	g.reverse = 3.333;
	g.final_drive = 3.722;
	g.efficiency = 0.93;

	TireParams &t = p.tire;
	t.radius = 0.2888; // 185/60 R14: 355.6/2 + 185*0.6 = 288.8 mm
	t.width = 0.185;
	t.load_nominal = (1100.0 * kGravity) / 4.0;

	p.steering.wheel_lock_deg = 540.0; // ≈3 turns lock to lock
	p.steering.max_road_angle_deg = 39.0; // ≈10 m kerb-to-kerb turning circle

	layout_wheels(p, p.wheelbase, p.track, p.track, t.radius, 0.26);
	for (int i = 0; i < 4; ++i) {
		WheelParams &w = p.wheels[static_cast<size_t>(i)];
		const bool front = i < 2;
		w.inertia = front ? 1.05 : 0.85;
		w.brake_torque = front ? 1250.0 : 520.0; // disc front, drum rear
		w.handbrake_torque = front ? 0.0 : 900.0;
		w.spring_rate = front ? 23000.0 : 19000.0;
		w.damper_bump = front ? 1550.0 : 1250.0;
		w.damper_rebound = front ? 2500.0 : 2050.0;
		w.travel_up = 0.095;
		w.travel_down = 0.085;
	}
	p.anti_roll_front = 11000.0;
	p.anti_roll_rear = 3500.0;
	return p;
}

VehicleParams make_cobalt_at() {
	VehicleParams p;
	p.id = "cobalt_at";
	p.mass = 1165.0 + 75.0;
	p.inertia = { 600.0, 2050.0, 1900.0 };
	p.center_of_mass = { 0.0, 0.54, -0.26 }; // ~60/40
	p.drag_area = 0.33 * 2.05;
	p.wheelbase = 2.62;
	// Maker: 1479/1493 mm; the game model's wheel arches sit at 1.52 m.
	p.track = 1.52;
	p.abs = true;

	EngineParams &e = p.engine;
	e.torque_full = Curve{ { 0.0, 66.0 }, { 600.0, 92.0 }, { 1000.0, 104.0 }, { 1500.0, 112.0 }, { 2000.0, 118.0 },
		{ 2500.0, 123.0 }, { 3000.0, 128.0 }, { 4000.0, 134.0 }, { 4800.0, 131.0 }, { 5400.0, 127.0 },
		{ 5800.0, 124.0 }, { 6400.0, 110.0 }, { 7000.0, 80.0 } };
	e.inertia = 0.14;
	e.idle_rpm = 750.0;
	e.limiter_rpm = 6500.0;
	e.redline_rpm = 6300.0;

	GearboxParams &g = p.gearbox;
	g.type = TransmissionType::Automatic;
	g.forward = { 4.584, 2.964, 1.912, 1.446, 1.000, 0.746 };
	g.reverse = 2.943;
	g.final_drive = 3.53;
	g.efficiency = 0.90;
	g.upshift_kmh_light = { 17.0, 30.0, 44.0, 57.0, 70.0 };
	g.upshift_kmh_full = { 42.0, 72.0, 105.0, 138.0, 168.0 };
	g.downshift_hysteresis_kmh = 8.0;
	g.creep_idle_rpm = 750.0;
	TorqueConverterParams &tc = g.converter;
	// Typical small-car converter: stall ratio 2.0, coupling point at SR 0.86.
	tc.k_factor = Curve{ { 0.0, 150.0 }, { 0.5, 158.0 }, { 0.7, 170.0 }, { 0.8, 185.0 }, { 0.86, 205.0 },
		{ 0.92, 260.0 }, { 0.97, 450.0 }, { 1.0, 2000.0 } };
	tc.torque_ratio = Curve{ { 0.0, 2.0 }, { 0.3, 1.72 }, { 0.6, 1.36 }, { 0.8, 1.10 }, { 0.86, 1.0 }, { 1.0, 1.0 } };
	tc.turbine_inertia = 0.05;

	TireParams &t = p.tire;
	t.radius = 0.3165; // 185/75 R14
	t.width = 0.185;
	t.load_nominal = (1240.0 * kGravity) / 4.0;

	p.steering.wheel_lock_deg = 510.0;
	p.steering.max_road_angle_deg = 37.0; // 10.4 m turning circle

	layout_wheels(p, p.wheelbase, p.track, p.track, t.radius, 0.27);
	for (int i = 0; i < 4; ++i) {
		WheelParams &w = p.wheels[static_cast<size_t>(i)];
		const bool front = i < 2;
		w.inertia = front ? 1.2 : 1.0;
		w.brake_torque = front ? 1450.0 : 620.0;
		w.handbrake_torque = front ? 0.0 : 1000.0;
		w.spring_rate = front ? 25000.0 : 21000.0;
		w.damper_bump = front ? 1700.0 : 1400.0;
		w.damper_rebound = front ? 2700.0 : 2250.0;
		w.travel_up = 0.10;
		w.travel_down = 0.09;
	}
	p.anti_roll_front = 12500.0;
	p.anti_roll_rear = 4000.0;
	return p;
}

VehicleParams make_gentra() {
	VehicleParams p;
	p.id = "gentra";
	p.mass = 1185.0 + 75.0;
	// Estimated like the Cobalt's (same platform class, 61/39 front/rear).
	p.inertia = { 610.0, 2080.0, 1930.0 };
	p.center_of_mass = { 0.0, 0.54, -0.27 };
	p.drag_area = 0.34 * 2.05;
	// Measured on the game model (pipeline/blender/build_gentra.py, scaled to
	// the maker's 2600 mm wheelbase): track 1498 mm at the wheel centres.
	p.wheelbase = 2.60;
	p.track = 1.498;
	p.abs = true;

	EngineParams &e = p.engine;
	// B15D2 in the Gentra's tune: 141 N·m @ 3800 rpm, 107 hp @ 5800 rpm.
	e.torque_full = Curve{ { 0.0, 68.0 }, { 600.0, 95.0 }, { 1000.0, 108.0 }, { 1500.0, 117.0 }, { 2000.0, 124.0 },
		{ 2500.0, 130.0 }, { 3000.0, 136.0 }, { 3800.0, 141.0 }, { 4600.0, 138.0 }, { 5200.0, 134.0 },
		{ 5800.0, 129.0 }, { 6400.0, 112.0 }, { 7000.0, 80.0 } };
	e.inertia = 0.14;
	e.idle_rpm = 800.0;
	e.limiter_rpm = 6500.0;
	e.redline_rpm = 6300.0;

	p.clutch.max_torque = 205.0;

	GearboxParams &g = p.gearbox;
	g.type = TransmissionType::Manual;
	g.forward = { 3.545, 1.952, 1.276, 0.941, 0.756 };
	g.reverse = 3.333;
	g.final_drive = 4.176;
	g.efficiency = 0.93;

	TireParams &t = p.tire;
	t.radius = 0.2978; // 195/55 R15: 381/2 + 195*0.55 = 297.75 mm
	t.width = 0.195;
	t.load_nominal = (1260.0 * kGravity) / 4.0;

	p.steering.wheel_lock_deg = 520.0;
	p.steering.max_road_angle_deg = 37.0; // 10.3 m turning circle

	layout_wheels(p, p.wheelbase, p.track, p.track, t.radius, 0.27);
	for (int i = 0; i < 4; ++i) {
		WheelParams &w = p.wheels[static_cast<size_t>(i)];
		const bool front = i < 2;
		w.inertia = front ? 1.25 : 1.05;
		w.brake_torque = front ? 1480.0 : 640.0;
		w.handbrake_torque = front ? 0.0 : 1000.0;
		w.spring_rate = front ? 25500.0 : 21500.0;
		w.damper_bump = front ? 1700.0 : 1400.0;
		w.damper_rebound = front ? 2750.0 : 2300.0;
		w.travel_up = 0.10;
		w.travel_down = 0.09;
	}
	p.anti_roll_front = 12500.0;
	p.anti_roll_rear = 4000.0;
	return p;
}

VehicleParams make_onix(bool automatic) {
	VehicleParams p;
	p.id = automatic ? "onix_at" : "onix";
	p.mass = (automatic ? 1150.0 : 1125.0) + 75.0;
	// Estimated like the Gentra's (same size class, ~61/39 front/rear).
	p.inertia = { 600.0, 2060.0, 1910.0 };
	p.center_of_mass = { 0.0, 0.53, -0.27 };
	p.drag_area = 0.31 * 2.08;
	// Measured on the game model (pipeline/blender/build_onix.py, scaled to
	// the maker's 2600 mm wheelbase): track 1533 mm at the wheel centres.
	p.wheelbase = 2.60;
	p.track = 1.533;
	p.abs = true;

	EngineParams &e = p.engine;
	// 1.2 turbo (CSS Prime): 173 N·m from 2000 to 4000 rpm, 115 hp @ 5200 rpm;
	// the turbo fills in between 1500 and 2500 rpm (as felt from a launch).
	e.torque_full = Curve{ { 0.0, 70.0 }, { 600.0, 95.0 }, { 1000.0, 110.0 }, { 1500.0, 128.0 }, { 2000.0, 155.0 },
		{ 2500.0, 173.0 }, { 4000.0, 173.0 }, { 4600.0, 166.0 }, { 5200.0, 157.0 }, { 5800.0, 138.0 },
		{ 6200.0, 112.0 }, { 6600.0, 80.0 } };
	e.inertia = 0.13;
	e.idle_rpm = 800.0;
	e.limiter_rpm = 6300.0;
	e.redline_rpm = 6000.0;

	GearboxParams &g = p.gearbox;
	if (automatic) {
		// GM GF6 6-speed automatic.
		g.type = TransmissionType::Automatic;
		g.forward = { 4.449, 2.908, 1.893, 1.446, 1.000, 0.742 };
		g.reverse = 2.871;
		g.final_drive = 3.49;
		g.efficiency = 0.90;
		g.upshift_kmh_light = { 16.0, 29.0, 42.0, 55.0, 68.0 };
		g.upshift_kmh_full = { 44.0, 76.0, 110.0, 145.0, 175.0 };
		g.downshift_hysteresis_kmh = 8.0;
		g.creep_idle_rpm = 750.0;
		TorqueConverterParams &tc = g.converter;
		tc.k_factor = Curve{ { 0.0, 150.0 }, { 0.5, 158.0 }, { 0.7, 170.0 }, { 0.8, 185.0 }, { 0.86, 205.0 },
			{ 0.92, 260.0 }, { 0.97, 450.0 }, { 1.0, 2000.0 } };
		tc.torque_ratio = Curve{ { 0.0, 2.0 }, { 0.3, 1.72 }, { 0.6, 1.36 }, { 0.8, 1.10 }, { 0.86, 1.0 }, { 1.0, 1.0 } };
		tc.turbine_inertia = 0.05;
	} else {
		// 6-speed manual; a tall 1st gear keeps the turbo's
		// torque from spinning the front tyres at a full-throttle start.
		p.clutch.max_torque = 240.0;
		g.type = TransmissionType::Manual;
		g.forward = { 3.154, 1.947, 1.300, 0.976, 0.787, 0.660 };
		g.reverse = 3.818;
		g.final_drive = 3.94;
		g.efficiency = 0.93;
	}

	TireParams &t = p.tire;
	t.radius = 0.317; // the game model's tyre (185/65 R15 ~ 0.311 m)
	t.width = 0.185;
	t.load_nominal = (p.mass * kGravity) / 4.0;

	p.steering.wheel_lock_deg = 500.0;
	p.steering.max_road_angle_deg = 37.0; // 10.4 m turning circle

	layout_wheels(p, p.wheelbase, p.track, p.track, t.radius, 0.27);
	for (int i = 0; i < 4; ++i) {
		WheelParams &w = p.wheels[static_cast<size_t>(i)];
		const bool front = i < 2;
		w.inertia = front ? 1.2 : 1.0;
		w.brake_torque = front ? 1470.0 : 630.0;
		w.handbrake_torque = front ? 0.0 : 1000.0;
		w.spring_rate = front ? 25000.0 : 21000.0;
		w.damper_bump = front ? 1700.0 : 1400.0;
		w.damper_rebound = front ? 2700.0 : 2250.0;
		w.travel_up = 0.10;
		w.travel_down = 0.09;
	}
	p.anti_roll_front = 12500.0;
	p.anti_roll_rear = 4000.0;
	return p;
}

VehicleParams make_gazelle() {
	VehicleParams p;
	p.id = "gazelle";
	p.mass = 2150.0 + 75.0;
	// A tall van: estimates from the mass and the body (6.1 x 2.07 x 2.7 m),
	// 55/45 front/rear unladen.
	p.inertia = { 1650.0, 6400.0, 6100.0 };
	p.center_of_mass = { 0.0, 0.80, -0.19 };
	p.drag_area = 0.40 * 4.7;
	// Measured on the game model (pipeline/blender/build_gazelle.py, scaled to
	// the maker's 3745 mm wheelbase).
	p.wheelbase = 3.745;
	p.track = 1.70;
	p.abs = true;

	EngineParams &e = p.engine;
	// Cummins ISF 2.8: a flat 297 N·m from 1400 to 2600 rpm, 120 hp at 3400.
	e.torque_full = Curve{ { 0.0, 110.0 }, { 600.0, 150.0 }, { 900.0, 205.0 }, { 1200.0, 265.0 }, { 1400.0, 297.0 },
		{ 2600.0, 297.0 }, { 3000.0, 283.0 }, { 3400.0, 252.0 }, { 3700.0, 212.0 }, { 4000.0, 140.0 } };
	e.inertia = 0.38; // dual-mass flywheel
	e.friction_const = 16.0;
	e.friction_per_krpm = 9.0;
	e.compression_hold = 70.0;
	e.idle_rpm = 750.0;
	e.stall_rpm = 380.0;
	e.catch_rpm = 330.0;
	e.limiter_rpm = 3900.0;
	e.redline_rpm = 3700.0;
	e.starter_torque = 190.0;
	e.starter_max_rpm = 420.0;
	e.idle_max_throttle = 0.14;
	e.progression_low = 3.0;

	p.clutch.max_torque = 480.0;

	GearboxParams &g = p.gearbox;
	g.type = TransmissionType::Manual;
	g.forward = { 4.05, 2.34, 1.395, 1.0, 0.849 };
	g.reverse = 3.51;
	g.final_drive = 4.3;
	g.efficiency = 0.92;
	g.inertia = 0.05;

	TireParams &t = p.tire;
	t.radius = 0.342; // 185/75 R16C: 406/2 + 185*0.75 = 341.75 mm
	t.width = 0.185;
	t.load_nominal = (p.mass * kGravity) / 4.0;
	t.relax_long = 0.28;
	t.relax_lat = 0.55;
	t.rolling_resistance = 0.011;

	p.steering.wheel_lock_deg = 630.0; // 3.5 turns lock to lock
	p.steering.max_road_angle_deg = 40.0; // ~11.8 m turning circle

	layout_wheels(p, p.wheelbase, p.track, 1.58, t.radius, 0.30);
	for (int i = 0; i < 4; ++i) {
		WheelParams &w = p.wheels[static_cast<size_t>(i)];
		const bool front = i < 2;
		w.driven = !front;
		w.inertia = front ? 2.0 : 2.4;
		w.brake_torque = front ? 2700.0 : 1800.0;
		w.handbrake_torque = front ? 0.0 : 1800.0;
		w.spring_rate = front ? 52000.0 : 70000.0;
		w.damper_bump = front ? 3600.0 : 4200.0;
		w.damper_rebound = front ? 5800.0 : 6800.0;
		w.travel_up = 0.10;
		w.travel_down = 0.10;
	}
	p.anti_roll_front = 24000.0;
	p.anti_roll_rear = 10000.0;
	return p;
}

VehicleParams make_preset(const std::string &id) {
	if (id == "cobalt_at") {
		return make_cobalt_at();
	}
	if (id == "gazelle") {
		return make_gazelle();
	}
	if (id == "gentra") {
		return make_gentra();
	}
	if (id == "onix" || id == "onix_at") {
		return make_onix(id == "onix_at");
	}
	return make_nexia2();
}

} // namespace avto
