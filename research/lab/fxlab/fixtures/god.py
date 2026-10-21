"""Fixtures for god. Owned by scope fxlab-god (T5).

Each fixture makes its own sandbox from the run4-closeout save, so the player force has real research.
"""

import json

from ..lab import SbxError
from .registry import Result, fixture

SAVE = "run4-closeout"


def jlua(lab, code):
    return json.loads(lab.lua(code))


def ground(lab, box, x=0, y=0, r=3):
    lab.lua(f'local s = game.surfaces["sbx-{box}"] s.request_to_generate_chunks({{{x}, {y}}}, {r}) '
            f's.force_generate_chunk_requests()')


def ent(box, pos, name):
    """Lua that binds `e` to the entity called `name` at a position a god call returned."""
    return (f'local e = game.surfaces["sbx-{box}"].find_entities_filtered{{name = "{name}", '
            f'position = {{{pos["x"]}, {pos["y"]}}}, radius = 1}}[1] ')


def player_bonuses(lab, keys):
    """The player force's bonuses read straight from the game, under the names the bonuses verb uses."""
    code = f'''
local keys = helpers.json_to_table([==[{json.dumps(sorted(keys))}]==])
local f = game.forces.player
local out = {{}}
for _, k in ipairs(keys) do
  local fn, cat = k:match("^([%w_]+):(.+)$")
  if fn == "ammo_damage" then out[k] = f.get_ammo_damage_modifier(cat)
  elseif fn == "gun_speed" then out[k] = f.get_gun_speed_modifier(cat)
  elseif fn == "turret_attack" then out[k] = f.get_turret_attack_modifier(cat)
  else out[k] = f[k] end
end
rcon.print(helpers.table_to_json(out))'''
    return jlua(lab, code)


def recipe_diff(lab, box):
    """Count recipes whose enabled state differs between the player force and the sandbox force."""
    return jlua(lab, f'''
local a, b = game.forces.player, game.forces["sbx-{box}"]
local diff, enabled = 0, 0
for n, r in pairs(a.recipes) do
  if r.enabled then enabled = enabled + 1 end
  if r.enabled ~= b.recipes[n].enabled then diff = diff + 1 end
end
rcon.print(helpers.table_to_json({{diff = diff, enabled = enabled}}))''')


def same_research(lab, box):
    """F7: every bonus field and every enabled recipe of the sandbox force equals the player's."""
    mine = lab.sbx("bonuses", name=box)
    theirs = player_bonuses(lab, mine["bonuses"].keys())
    off = {k: (v, theirs.get(k)) for k, v in mine["bonuses"].items()
           if abs(v - (theirs.get(k) or 0)) > 1e-9}
    rd = recipe_diff(lab, box)
    player_researched = jlua(lab, 'local n = 0 for _, t in pairs(game.forces.player.technologies) do '
                                  'if t.researched then n = n + 1 end end rcon.print(helpers.table_to_json({n = n}))')["n"]
    ok = not off and rd["diff"] == 0 and mine["researched"] == player_researched
    return ok, {"fields": len(mine["bonuses"]), "off": off, "recipe_diff": rd["diff"], "recipes": rd["enabled"],
                "researched": mine["researched"], "player_researched": player_researched}


def player_digest(lab):
    """Research and bonuses of the player force, to prove a god call left them alone."""
    return lab.lua('''
local f = game.forces.player
local techs = {}
for n, t in pairs(f.technologies) do if t.researched then techs[#techs + 1] = n end end
table.sort(techs)
rcon.print(helpers.table_to_json({techs = table.concat(techs, ","), mining = f.mining_drill_productivity_bonus,
  inserter = f.inserter_stack_size_bonus, lab = f.laboratory_speed_modifier,
  bullet = f.get_ammo_damage_modifier("bullet")}))''')


@fixture(source=SAVE, tags={"god"})
def god_research_copy(lab):
    lab.sbx("sandbox_new", name="rc")
    ok, d = same_research(lab, "rc")
    lab.sbx("sandbox_new", name="rn", research="none")
    nb = lab.sbx("bonuses", name="rn")
    differs = nb["researched"] < d["player_researched"] and d["researched"] > 100
    return Result(ok and differs, f"copy equal={ok}: {d['fields']} bonus fields, {d['researched']} techs, "
                  f"{d['recipes']} recipes, recipe diff {d['recipe_diff']}; blank force has {nb['researched']} techs",
                  data={**d, "blank_researched": nb["researched"]})


@fixture(source=SAVE, tags={"god"})
def god_research_modes(lab):
    lab.sbx("sandbox_new", name="rm", research="none")
    got = {}
    lab.sbx("research", name="rm", mode="none")
    r = lab.sbx("research", name="rm", mode="list", techs=["chemical-science-pack"])
    prereqs = jlua(lab, '''
local t = game.forces["sbx-rm"].technologies["chemical-science-pack"]
local all, n = true, 0
for _, p in pairs(t.prerequisites) do n = n + 1 if not p.researched then all = false end end
rcon.print(helpers.table_to_json({all = all, n = n, tech = t.researched}))''')
    got["list"] = {"changed": r["count"], **prereqs}
    list_ok = prereqs["all"] and prereqs["n"] > 0 and prereqs["tech"] and r["count"] > prereqs["n"]

    lab.sbx("research", name="rm", mode="none")
    lab.sbx("research", name="rm", mode="levels", levels={"mining-productivity-3": 5})
    mining = lab.sbx("bonuses", name="rm")["bonuses"]["mining_drill_productivity_bonus"]
    got["levels_mining"] = mining
    levels_ok = abs(mining - 0.5) < 1e-9

    a = lab.sbx("research", name="rm", mode="all")
    got["all_researched"] = a["researched"]
    got["all_recipes"] = a["recipes"]
    all_ok = a["researched"] >= 250

    n = lab.sbx("research", name="rm", mode="none")
    direct = jlua(lab, 'local n = 0 for _, t in pairs(game.forces["sbx-rm"].technologies) do '
                       'if t.researched then n = n + 1 end end rcon.print(helpers.table_to_json({n = n}))')["n"]
    got["none_researched"] = n["researched"]
    none_ok = n["researched"] == 0 and direct == 0

    lab.sbx("research", name="rm", mode="list", techs=["automation"], recipes=["iron-gear-wheel"])
    ledger = lab.sbx("ledger", name="rm")
    kinds = {e["kind"] for e in ledger["entries"]}
    ledger_ok = kinds == {"research"} and ledger["count"] > 250

    ok = list_ok and levels_ok and all_ok and none_ok and ledger_ok
    return Result(ok, f"list pulled {r['count']} techs (prereqs ok={list_ok}); mining-productivity-3 at 5 gives "
                  f"{mining:.3f}; all researched {a['researched']}; none leaves {n['researched']}; "
                  f"ledger {ledger['count']} research entries", data=got)


@fixture(source=SAVE, tags={"god"})
def god_items(lab):
    lab.sbx("sandbox_new", name="it")
    ground(lab, "it")
    before = player_digest(lab)
    out = {}
    # chest
    c = lab.sbx("items", name="it", at=[5, 5], target="chest",
                items=[{"name": "iron-plate", "count": 100}, {"name": "coal", "count": 50}])
    held = jlua(lab, ent("it", c["position"], "steel-chest") +
                f'rcon.print(helpers.table_to_json({{iron = e.get_item_count("iron-plate"), '
                f'coal = e.get_item_count("coal"), name = e.name}}))')
    chest_ok = held["iron"] == 100 and held["coal"] == 50 and held["name"] == "steel-chest"
    # infinity chest: filled only on a running tick
    i = lab.sbx("items", name="it", at=[12, 5], target="infinity",
                items=[{"name": "iron-plate", "count": 50}, {"name": "copper-plate", "count": 50}])
    inf_code = ('local e = game.surfaces["sbx-it"].find_entities_filtered{name = "infinity-chest"}[1] '
                f'rcon.print(helpers.table_to_json({{iron = e.get_item_count("iron-plate"), '
                f'copper = e.get_item_count("copper-plate"), filters = #e.infinity_container_filters}}))')
    inf0 = jlua(lab, inf_code)
    lab.advance(2)
    inf2 = jlua(lab, inf_code)
    inf_ok = inf2["iron"] > 0 and inf2["copper"] > 0 and inf2["filters"] == 2
    # belt: a run of four, loaded from its first tile
    lab.lua('local s = game.surfaces["sbx-it"] local f = game.forces["sbx-it"] '
            'for x = 0, 3 do s.create_entity{name = "transport-belt", position = {x + 0.5, 12.5}, '
            'direction = defines.direction.east, force = f} end')
    b = lab.sbx("items", name="it", at=[0.5, 12.5], target="belt",
                items=[{"name": "iron-plate", "count": 8}, {"name": "copper-plate", "count": 4}])
    on_belt = jlua(lab, 'local n = 0 for _, e in pairs(game.surfaces["sbx-it"].find_entities_filtered{name = "transport-belt"}) '
                        'do n = n + e.get_item_count() end rcon.print(helpers.table_to_json({n = n}))')["n"]
    belt_ok = sum(b["inserted"].values()) == 12 and on_belt == 12
    # body
    body = lab.sbx("body", name="it", at=[20, 20])
    e = lab.sbx("items", name="it", target="entity", entity=body["unit"],
                items=[{"name": "iron-plate", "count": 100}, {"name": "firearm-magazine", "count": 20}])
    held_body = jlua(lab, ent("it", body["position"], "character") +
                     f'rcon.print(helpers.table_to_json({{iron = e.get_item_count("iron-plate"), '
                     f'ammo = e.get_item_count("firearm-magazine")}}))')
    try:
        lab.sbx("items", name="it", target="entity", items=[{"name": "coal", "count": 1}])
        no_entity = "allowed"
    except SbxError as exc:
        no_entity = exc.code
    body_ok = held_body["iron"] == 100 and held_body["ammo"] == 20 and no_entity == "bad_args"
    # ground
    lab.sbx("items", name="it", at=[30, 30], target="ground", items=[{"name": "stone", "count": 10}])
    spilled = jlua(lab, 'local n = 0 for _, e in pairs(game.surfaces["sbx-it"].find_entities_filtered{name = "item-on-ground", '
                        'position = {30, 30}, radius = 8}) do n = n + e.stack.count end '
                        'rcon.print(helpers.table_to_json({n = n}))')["n"]
    ground_ok = spilled == 10
    after = player_digest(lab)
    untouched = before == after
    out.update(chest=held, infinity_at_0=inf0, infinity_at_2=inf2, belt_inserted=b["inserted"], on_belt=on_belt,
               body=held_body, ground=spilled, player_untouched=untouched)
    ok = chest_ok and inf_ok and belt_ok and body_ok and ground_ok and untouched
    return Result(ok, f"chest {held['iron']}/{held['coal']}; infinity {inf0['iron']} then {inf2['iron']} after 2 ticks; "
                  f"belt {on_belt}/12; body {held_body['iron']} iron; ground {spilled}; player untouched={untouched}",
                  data=out)


@fixture(source=SAVE, tags={"god"})
def god_enemies(lab):
    lab.sbx("sandbox_new", name="en")
    ground(lab, "en", 0, 0, 4)
    evo_code = 'rcon.print(helpers.table_to_json({sbx = game.forces.enemy.get_evolution_factor("sbx-en"), ' \
               'nauvis = game.forces.enemy.get_evolution_factor("nauvis")}))'
    e0 = jlua(lab, evo_code)
    r = lab.sbx("evo", name="en", set=0.9)
    e1 = jlua(lab, evo_code)
    evo_ok = abs(r["evo"] - 0.9) < 1e-6 and abs(e1["nauvis"] - e0["nauvis"]) < 1e-12 and abs(e1["sbx"] - 0.9) < 1e-6
    nest = lab.sbx("nest", name="en", at=[150, -150], names=["biter-spawner", "spitter-spawner", "big-worm-turret"])
    spawners = jlua(lab, 'rcon.print(helpers.table_to_json({n = game.surfaces["sbx-en"].count_entities_filtered{'
                         'force = "enemy", type = "unit-spawner"}}))')["n"]
    nest_ok = len(nest["units"]) == 3 and spawners == 2
    lab.lua('local s = game.surfaces["sbx-en"] local f = game.forces["sbx-en"] '
            'for _, x in ipairs{-8, -4, 0, 4, 8} do '
            'local t = s.create_entity{name = "gun-turret", position = {x, 0}, force = f} '
            't.insert{name = "piercing-rounds-magazine", count = 20} end')
    w = lab.sbx("wave", name="en", **{"from": [0, 70]}, target=[0, 0], units={"small-biter": 20}, radius=20)
    s0 = lab.sbx("wave_status", name="en", group=w["group"])
    lab.advance(1200)
    s1 = lab.sbx("wave_status", name="en", group=w["group"])
    wave_ok = w["members"] == 20 and s0["alive"] == 20 and s1["killed"] > 0
    ok = evo_ok and nest_ok and wave_ok
    return Result(ok, f"evo sbx {e1['sbx']:.3f}, nauvis {e0['nauvis']:.4f} -> {e1['nauvis']:.4f}; nest units "
                  f"{len(nest['units'])}, spawners {spawners}; wave of {w['members']}: killed {s1['killed']}, alive "
                  f"{s1['alive']}, state {s1['state']}",
                  data={"evo": [e0, e1], "wave": w, "status_start": s0, "status_end": s1})


@fixture(source=SAVE, tags={"god"})
def god_body(lab):
    lab.sbx("sandbox_new", name="bd")
    ground(lab, "bd", 0, 0, 3)
    ground(lab, "bd", 300, 0, 1)
    tough = lab.sbx("body", name="bd", at=[50, 0])
    soft = lab.sbx("body", name="bd", at=[-50, 0], invulnerable=False)
    far = jlua(lab, f'''
local s = game.surfaces["sbx-bd"]
local c = game.get_entity_by_unit_number({tough["unit"]})
local chest = s.create_entity{{name = "wooden-chest", position = {{350.5, 0.5}}, force = "sbx-bd"}}
local dist = math.sqrt((chest.position.x - c.position.x) ^ 2 + (chest.position.y - c.position.y) ^ 2)
local reach = c.can_reach_entity(chest)
local mined = c.mine_entity(chest)
rcon.print(helpers.table_to_json({{dist = dist, reach = reach, mined = mined, gone = not chest.valid,
  destructible = c.destructible, reach_bonus = c.character_reach_distance_bonus}}))''')
    # four medium biters beside each body
    lab.lua('local s = game.surfaces["sbx-bd"] for _, x in ipairs{50, -50} do for i = 1, 4 do '
            's.create_entity{name = "medium-biter", position = {x + 2 + i, 3}, force = "enemy"} end end')
    lab.advance(300)
    hp = jlua(lab, f'''
local t = game.get_entity_by_unit_number({tough["unit"]})
local s = game.get_entity_by_unit_number({soft["unit"]})
rcon.print(helpers.table_to_json({{tough_valid = t ~= nil and t.valid, tough_hp = t and t.valid and t.health or 0,
  tough_max = t and t.valid and t.max_health or 0, soft_valid = s ~= nil and s.valid,
  soft_hp = s and s.valid and s.health or 0, soft_max = s and s.valid and s.max_health or 0}}))''')
    far_ok = far["reach"] and far["mined"] and far["gone"] and far["dist"] >= 299 and not far["destructible"]
    tough_ok = hp["tough_valid"] and hp["tough_hp"] == hp["tough_max"]
    soft_hurt = (not hp["soft_valid"]) or hp["soft_hp"] < hp["soft_max"]
    ok = far_ok and tough_ok and soft_hurt
    return Result(ok, f"mined a chest {far['dist']:.0f} tiles away (reach {far['reach']}); invulnerable body "
                  f"{hp['tough_hp']:.0f}/{hp['tough_max']:.0f} after 300 ticks of biters; the mortal control body "
                  f"{'died' if not hp['soft_valid'] else str(round(hp['soft_hp'])) + '/' + str(round(hp['soft_max']))}",
                  data={"far": far, "hp": hp})


@fixture(source=SAVE, tags={"god"})
def god_mode_switch(lab):
    lab.sbx("sandbox_new", name="ms")
    ground(lab, "ms", 0, 0, 4)
    evo_code = 'rcon.print(helpers.table_to_json({sbx = game.forces.enemy.get_evolution_factor("sbx-ms")}))'
    evo_before = jlua(lab, evo_code)["sbx"]
    lab.sbx("research", name="ms", mode="none")
    lab.sbx("research", name="ms", mode="levels", levels={"mining-productivity-3": 5})
    diverged, _ = same_research(lab, "ms")
    inf = lab.sbx("items", name="ms", at=[5, 5], target="infinity", items=[{"name": "iron-plate", "count": 50}])
    nest = lab.sbx("nest", name="ms", at=[100, 100], names=["biter-spawner", "big-worm-turret"])
    body = lab.sbx("body", name="ms", at=[0, 0], reach=1000)
    lab.sbx("evo", name="ms", set=0.9)
    ledger = lab.sbx("ledger", name="ms")
    entities = sum(1 for e in ledger["entries"] if e["kind"] == "entity")
    n_entries = ledger["count"]

    lab.lua('game.surfaces["sbx-ms"].find_entities_filtered{name = "infinity-chest"}[1].destroy()')
    sw = lab.sbx("sbx_mode", name="ms", mode="standard", research="copy")
    after = lab.sbx("ledger", name="ms")
    left = [e for e in after["entries"] if e["kind"] == "entity" and e["valid"]]
    still = jlua(lab, f'''
local c = game.get_entity_by_unit_number({body["unit"]})
rcon.print(helpers.table_to_json({{body_valid = c ~= nil and c.valid, reach = c.character_reach_distance_bonus,
  build = c.character_build_distance_bonus, mine = c.character_resource_reach_distance_bonus,
  destructible = c.destructible, evo = game.forces.enemy.get_evolution_factor("sbx-ms")}}))''')
    equal, detail = same_research(lab, "ms")
    gates = {}
    for verb, args in (("items", dict(at=[8, 8], items=[{"name": "iron-plate", "count": 1}])),
                       ("nest", dict(at=[100, 100], names=["biter-spawner"]))):
        try:
            lab.sbx(verb, name="ms", **args)
            gates[verb] = "allowed"
        except SbxError as exc:
            gates[verb] = exc.code
    reads = lab.sbx("bonuses", name="ms")["researched"] > 0 and lab.sbx("ledger", name="ms")["count"] == n_entries

    back = lab.sbx("sbx_mode", name="ms", mode="god")
    again = lab.sbx("items", name="ms", at=[8, 8], target="chest", items=[{"name": "iron-plate", "count": 5}])
    final = lab.sbx("ledger", name="ms")

    ok = (diverged is False and not left and entities >= 3 and sw["skipped"] == 1 and still["body_valid"] and still["reach"] == 0
          and still["build"] == 0 and still["mine"] == 0 and still["destructible"] and equal
          and abs(still["evo"] - evo_before) < 1e-9 and gates == {"items": "standard_mode", "nest": "standard_mode"}
          and reads and again["units"] and final["count"] == n_entries + 1)
    return Result(ok, f"undone {sw['undone']}, skipped {sw['skipped']} of {n_entries} entries; entities left "
                  f"{len(left)} of {entities} (body kept, reach {still['reach']}, destructible {still['destructible']}); "
                  f"research equal={equal}; evo back to {still['evo']:.3f}; gates {gates}; god again: chest "
                  f"{again['units']}",
                  data={"switch": sw, "state": still, "research": detail, "gates": gates, "entries": n_entries,
                        "diverged_before": diverged, "infinity": inf["units"], "nest": nest["units"]})


def player_full(lab):
    """The player force's techs with levels, enabled recipes and bonuses, as one comparable value."""
    return lab.lua('''
local f = game.forces.player
local techs, recipes, bonuses = {}, {}, {}
for n, t in pairs(f.technologies) do techs[#techs + 1] = n .. "=" .. tostring(t.researched) .. "/" .. t.level end
for n, r in pairs(f.recipes) do if r.enabled then recipes[#recipes + 1] = n end end
for _, k in ipairs{"mining_drill_productivity_bonus", "inserter_stack_size_bonus", "laboratory_speed_modifier",
  "manual_mining_speed_modifier", "worker_robots_speed_modifier", "character_inventory_slots_bonus"} do
  bonuses[#bonuses + 1] = k .. "=" .. tostring(f[k])
end
for cat in pairs(prototypes.ammo_category) do bonuses[#bonuses + 1] = cat .. "=" .. tostring(f.get_ammo_damage_modifier(cat)) end
table.sort(techs) table.sort(recipes) table.sort(bonuses)
rcon.print(helpers.table_to_json({techs = techs, recipes = recipes, bonuses = bonuses}))''')


@fixture(source=SAVE, tags={"god"})
def god_inplace_research(lab):
    lab.sbx("sandbox_new", name="ip", inplace={"surface": "nauvis", "force": "player"})
    pick = jlua(lab, '''
local f = game.forces.player
local tech, recipe
for n, t in pairs(f.technologies) do
  if not t.researched and t.prototype.max_level <= 1000000 and (not tech or n < tech) then tech = n end
end
for n, r in pairs(f.recipes) do if not r.enabled and not r.hidden and (not recipe or n < recipe) then recipe = n end end
rcon.print(helpers.table_to_json({tech = tech, recipe = recipe, mining = f.technologies["mining-productivity-3"].level}))''')
    before = player_full(lab)
    refused = {}
    for mode in ("none", "all"):
        try:
            lab.sbx("research", name="ip", mode=mode)
            refused[mode] = "allowed"
        except SbxError as exc:
            refused[mode] = exc.code
    untouched = player_full(lab) == before

    lab.sbx("research", name="ip", mode="levels", levels={"mining-productivity-3": pick["mining"] + 2})
    lab.sbx("research", name="ip", mode="list", techs=[pick["tech"]], recipes=[pick["recipe"]])
    changed = player_full(lab)
    diverged = changed != before
    mid = jlua(lab, f'''
local f = game.forces.player
rcon.print(helpers.table_to_json({{tech = f.technologies["{pick['tech']}"].researched,
  recipe = f.recipes["{pick['recipe']}"].enabled, level = f.technologies["mining-productivity-3"].level}}))''')
    ledger = lab.sbx("ledger", name="ip")
    recipe_entries = [e for e in ledger["entries"] if e.get("recipe")]

    sw = lab.sbx("sbx_mode", name="ip", mode="standard", research="keep")
    after = player_full(lab)
    equal = after == before
    detail = {}
    if not equal:
        for k in before:
            detail[k] = sorted(set(before[k]) ^ set(after[k]))[:10]
    ok = (refused == {"none": "bad_args", "all": "bad_args"} and untouched and diverged and mid["tech"]
          and mid["recipe"] and mid["level"] == pick["mining"] + 3 and len(recipe_entries) >= 1 and equal)
    return Result(ok, f"none/all refused {refused}; level {pick['mining']} -> {mid['level']}, {pick['tech']} and "
                  f"{pick['recipe']} on, {len(recipe_entries)} recipe entries; after the switch the player force "
                  f"equals its start: {equal}, undone {sw['undone']}",
                  data={"pick": pick, "mid": mid, "refused": refused, "diff": detail, "switch": sw})


@fixture(source=SAVE, tags={"god"})
def god_body_tp(lab):
    lab.sbx("sandbox_new", name="bt")
    ground(lab, "bt", 0, 0, 2)
    ground(lab, "bt", 0, 0, 0)
    lab.lua('game.surfaces.nauvis.request_to_generate_chunks({0, 0}, 2) game.surfaces.nauvis.force_generate_chunk_requests()')
    body = lab.sbx("body", name="bt", at=[10, 10], reach=500, invulnerable=True)
    lab.sbx("items", name="bt", target="entity", entity=body["unit"],
            items=[{"name": "iron-plate", "count": 77}, {"name": "firearm-magazine", "count": 9}])
    read = ('local c = game.get_entity_by_unit_number(%d) '
            'rcon.print(helpers.table_to_json({valid = c ~= nil and c.valid, surface = c and c.surface.name, '
            'iron = c and c.get_item_count("iron-plate"), ammo = c and c.get_item_count("firearm-magazine"), '
            'reach = c and c.character_reach_distance_bonus, mine = c and c.character_resource_reach_distance_bonus, '
            'destructible = c and c.destructible, x = c and c.position.x, y = c and c.position.y}))')
    start = jlua(lab, read % body["unit"])
    out = lab.sbx("body_tp", name="bt", at=[5, 5], surface="nauvis", unit=body["unit"])
    old_gone = jlua(lab, read % body["unit"])
    there = jlua(lab, read % out["unit"])
    on_ledger = [e for e in lab.sbx("ledger", name="bt")["entries"] if e["kind"] == "body"]
    over = lab.sbx("items", name="bt", target="entity", entity=out["unit"], items=[{"name": "coal", "count": 3}])
    back = lab.sbx("body_tp", name="bt", at=[-20, 30], surface="sbx-bt")
    home = jlua(lab, read % back["unit"])
    near = lab.sbx("body_tp", name="bt", at=[-30, 30])
    moved = jlua(lab, read % near["unit"])
    sw = lab.sbx("sbx_mode", name="bt", mode="standard")
    reset = jlua(lab, read % near["unit"])
    kept = lambda d: d["iron"] == 77 and d["ammo"] == 9 and d["reach"] == 500 and d["mine"] == 500 and not d["destructible"]
    ok = (start["surface"] == "sbx-bt" and out["teleported"] and out["unit"] != body["unit"] and not old_gone["valid"]
          and there["valid"] and there["surface"] == "nauvis" and kept(there) and abs(there["x"] - 5) < 10
          and len(on_ledger) == 1 and on_ledger[0]["unit"] == out["unit"] and over["inserted"] == {"coal": 3}
          and back["teleported"] and home["surface"] == "sbx-bt" and kept(home) and near["teleported"]
          and near["unit"] == back["unit"] and abs(moved["x"] + 30) < 5 and kept(moved)
          and reset["reach"] == 0 and reset["destructible"] and reset["iron"] == 77)
    return Result(ok, f"body {body['unit']} to nauvis as {out['unit']} (old gone={not old_gone['valid']}, iron "
                  f"{there['iron']}, ammo {there['ammo']}, reach {there['reach']}), back as {back['unit']} on "
                  f"{home['surface']}; same-surface move ok; ledger entries {len(on_ledger)}; after standard reach "
                  f"{reset['reach']}",
                  data={"start": start, "nauvis": there, "home": home, "moved": moved, "reset": reset, "switch": sw})
