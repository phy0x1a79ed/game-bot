-- Read-only geometric proof: can a burner-mining-drill's mining output ever
-- land inside a legally-placed neighbour burner-mining-drill's collision box?
-- Uses the exact collision_box from the prototype and the exact drop_position
-- offset measured live off a real placed drill (both fetched by the caller
-- and hard-coded below after an in-game probe). No entities are built.
local out = {}
local function p(s) out[#out+1] = s end

local HALF = 0.699219 -- collision_box half-width (square, direction-independent)
local MIN_LEGAL_SPACING = 2 * HALF -- 1.398438: any closer and boxes overlap => illegal placement

-- measured drop offsets (drill facing -> offset of its own output from its own centre)
local OFFSET = {
  north = {x=-0.347656, y=-1.296875},
  east  = {x= 1.296875, y=-0.347656},
  south = {x= 0.347656, y= 1.296875},
  west  = {x=-1.296875, y= 0.347656},
}

local function contains(px, py, cx, cy)
  return px >= cx - HALF and px <= cx + HALF and py >= cy - HALF and py <= cy + HALF
end

p("collision half-width=" .. HALF .. "  min legal centre spacing=" .. MIN_LEGAL_SPACING)
p("=== 2-drill facing pairs at the closest LEGAL spacing (2 tiles, integer grid) ===")
local pairs_to_test = {
  {name="A(east)->B east of A",   ax=0, ay=0, adir="east",  bx=2, by=0},
  {name="A(west)->B west of A",   ax=0, ay=0, adir="west",  bx=-2, by=0},
  {name="A(south)->B south of A", ax=0, ay=0, adir="south", bx=0, by=2},
  {name="A(north)->B north of A", ax=0, ay=0, adir="north", bx=0, by=-2},
}
for _, t in pairs(pairs_to_test) do
  local off = OFFSET[t.adir]
  local px, py = t.ax+off.x, t.ay+off.y
  local hit = contains(px, py, t.bx, t.by)
  local margin = t.adir=="east" and (t.bx-HALF)-px or t.adir=="west" and px-(t.bx+HALF)
    or t.adir=="south" and (t.by-HALF)-py or (py-(t.by-HALF))
  p(string.format("%-28s drop=(%.4f,%.4f) target_bbox_x=[%.4f,%.4f] y=[%.4f,%.4f] INSERTS=%s (miss margin=%.4f tiles)",
    t.name, px, py, t.bx-HALF, t.bx+HALF, t.by-HALF, t.by+HALF, tostring(hit), margin))
end

p("=== 4-drill ring, 2-tile square, BOTH rotations ===")
-- square corners (0,0) (2,0) (2,2) (0,2). CW: 0,0->2,0->2,2->0,2->0,0 (E,S,W,N facing)
-- CCW: 0,0->0,2->2,2->2,0->0,0 (S,E,N,W facing)
local function ring_edge(name, ax,ay,adir,bx,by)
  local off = OFFSET[adir]
  local px, py = ax+off.x, ay+off.y
  local hit = contains(px, py, bx, by)
  p(string.format("  %-22s A=(%d,%d) dir=%-5s drop=(%.4f,%.4f) -> B=(%d,%d) bbox_x=[%.4f,%.4f] y=[%.4f,%.4f] INSERTS=%s",
    name, ax,ay,adir, px, py, bx, by, bx-HALF, bx+HALF, by-HALF, by+HALF, tostring(hit)))
end
p("-- clockwise (each drill faces the next corner clockwise) --")
ring_edge("(0,0)east->(2,0)", 0,0,"east", 2,0)
ring_edge("(2,0)south->(2,2)", 2,0,"south", 2,2)
ring_edge("(2,2)west->(0,2)", 2,2,"west", 0,2)
ring_edge("(0,2)north->(0,0)", 0,2,"north", 0,0)
p("-- anticlockwise --")
ring_edge("(0,0)south->(0,2)", 0,0,"south", 0,2)
ring_edge("(0,2)east->(2,2)", 0,2,"east", 2,2)
ring_edge("(2,2)north->(2,0)", 2,2,"north", 2,0)
ring_edge("(2,0)west->(0,0)", 2,0,"west", 0,0)

p("=== is any legal placement close enough at all? (brute-force integer offsets |dx|,|dy|<=3) ===")
for _, adir in ipairs({"east"}) do
  local off = OFFSET[adir]
  for dx=-3,3 do
    for dy=-3,3 do
      if not (dx==0 and dy==0) then
        local spacing = (dx*dx+dy*dy)^0.5
        local legal = spacing >= MIN_LEGAL_SPACING - 1e-6 -- ignoring diagonal-box subtlety, checked properly below
        -- proper legality: AABB overlap test between A at (0,0) and B at (dx,dy), both half-width HALF
        local overlap = math.abs(dx) < 2*HALF and math.abs(dy) < 2*HALF
        local px, py = off.x, off.y
        local hit = contains(px, py, dx, dy)
        if hit then
          p(string.format("facing=%s neighbour offset=(%d,%d) spacing=%.3f legal(no AABB overlap)=%s  <-- CANDIDATE", adir, dx, dy, spacing, tostring(not overlap)))
        end
      end
    end
  end
end

rcon.print(table.concat(out, "\n"))
