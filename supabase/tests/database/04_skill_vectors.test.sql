-- The hidden skill uses the same formula as Ranked.delta (scripts/logic/ranked.gd). The vectors below are the single
-- source: tests/test_queue_vectors.gd parses this very file and checks Ranked.delta against every row.
-- Row: (my team average, their team average, won, games already played, expected change).
begin;
select no_plan();

create temp table vectors (my float8, their float8, won boolean, games int, want int);
insert into vectors values
-- BEGIN VECTORS
  (1500.0, 1500.0, true, 0, 24),
  (1500.0, 1500.0, false, 0, -24),
  (1500.0, 1500.0, true, 4, 24),
  (1500.0, 1500.0, true, 5, 12),
  (1500.0, 1500.0, false, 12, -12),
  (1500.0, 2000.0, true, 10, 23),
  (2000.0, 1500.0, true, 10, 1),
  (1500.0, 2000.0, false, 10, -1),
  (2000.0, 1500.0, false, 10, -23),
  (1200.0, 1800.0, true, 3, 47),
  (1800.0, 1200.0, false, 3, -47),
  (1500.5, 1499.5, true, 7, 12),
  (1633.33, 1411.5, false, 2, -38),
  (1450.0, 1560.67, true, 5, 16),
  (5000.0, 0.0, true, 50, 1),
  (5000.0, 0.0, false, 50, -24),
  (0.0, 5000.0, true, 50, 24),
  (0.0, 5000.0, false, 50, -1),
  (1700.0, 1700.0, true, 4, 24),
  (1700.0, 1700.0, false, 5, -12),
  (1000.0, 1100.0, true, 0, 31),
  (1520.0, 1480.0, true, 20, 11),
  (1520.0, 1480.0, false, 20, -13),
  (3000.0, 2900.0, false, 100, -15)
-- END VECTORS
;

select is(app_private.skill_delta(v.my, v.their, v.won, v.games), v.want,
          format('skill_delta(%s, %s, %s, %s) = %s', v.my, v.their, v.won, v.games, v.want))
  from vectors v;
select is((select count(*)::int from vectors), 24, 'veinticuatro vectores');
select is(app_private.clamp_skill(-5), 0, 'minimo 0');
select is(app_private.clamp_skill(9000), 5000, 'maximo 5000');
select is(app_private.clamp_skill(1500), 1500, 'sin cambios dentro del rango');
select is(app_private.skill_window(0), 200, 'ventana inicial como Ranked.window(0)');
select is(app_private.skill_window(10), 300, 'ventana a los 10 s');
select is(app_private.skill_window(1000), 800, 'ventana maxima');
select * from finish();
rollback;
