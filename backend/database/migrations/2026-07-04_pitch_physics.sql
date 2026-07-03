ALTER TABLE game_pitch_locations
  ADD COLUMN IF NOT EXISTS x0 numeric,  ADD COLUMN IF NOT EXISTS vx0 numeric, ADD COLUMN IF NOT EXISTS ax numeric,
  ADD COLUMN IF NOT EXISTS y0 numeric,  ADD COLUMN IF NOT EXISTS vy0 numeric, ADD COLUMN IF NOT EXISTS ay numeric,
  ADD COLUMN IF NOT EXISTS z0 numeric,  ADD COLUMN IF NOT EXISTS vz0 numeric, ADD COLUMN IF NOT EXISTS az numeric,
  ADD COLUMN IF NOT EXISTS cross_y numeric;
GRANT ALL ON game_pitch_locations TO playball_user;
