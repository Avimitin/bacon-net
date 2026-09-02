// Game icons from https://github.com/bicarus-dev/bemani_fan_site_icons (see README).
import iidx from "./assets/games/ac_iidx33.png";
import ddr from "./assets/games/ac_ddr_world.png";
import sdvx from "./assets/games/ac_sdvx6.png";
import gitadora from "./assets/games/ac_gitadora.png";
import drs from "./assets/games/ac_dancerush.png";
import nostalgia from "./assets/games/ac_nostalgia_op3_loc.png";

export const gameIcons = { iidx, ddr, sdvx, gitadora, drs, nostalgia };

export function gameIcon(key) {
  return gameIcons[key] || null;
}
