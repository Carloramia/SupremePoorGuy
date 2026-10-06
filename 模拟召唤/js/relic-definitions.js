export const RELICS = Object.freeze([
  {
    id: "tide-pump",
    name: "潮汐泵",
    subtitle: "TIDE PUMP",
    effect: "每刻入一枚符文，恢复 3% 生命",
    color: "#52d0c8",
    cells: [[0, 0], [1, 0], [0, 1]],
  },
  {
    id: "prism-heart",
    name: "棱镜心脏",
    subtitle: "PRISM HEART",
    effect: "相邻符文的效果强度提高 12%",
    color: "#e886ff",
    cells: [[0, 0], [1, 0], [0, 1], [-1, 1]],
  },
  {
    id: "bone-die",
    name: "骨骰",
    subtitle: "BONE DIE",
    effect: "召唤完成时随机强化一种属性",
    color: "#e4d6b0",
    cells: [[0, 0], [1, 0]],
  },
]);

export const relicById = (id) => RELICS.find((relic) => relic.id === id);
