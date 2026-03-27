/**
 * Shared SVG icon builder for editor UI controls.
 * Provides a declarative icon registry and a single factory function so
 * icon shapes are defined once and reused across list editors and other
 * controls. Strict CSP requires createElementNS — never innerHTML.
 *
 * - ordered_list_editor_utils: primary consumer (chevron, delete, undo)
 */

const ICONS = {
  chevron: {
    viewBox: "0 0 24 24",
    children: [
      { tag: "polyline", attrs: { points: "6 15 12 9 18 15" } }
    ]
  },
  delete: {
    viewBox: "0 0 24 24",
    children: [
      { tag: "line", attrs: { x1: "6", y1: "6", x2: "18", y2: "18" } },
      { tag: "line", attrs: { x1: "18", y1: "6", x2: "6", y2: "18" } }
    ]
  },
  undo: {
    viewBox: "0 0 24 24",
    children: [
      { tag: "path", attrs: { d: "M4 9h11a4 4 0 0 1 0 8H11" } },
      { tag: "polyline", attrs: { points: "7 5 4 9 7 13" } }
    ]
  },
  plus: {
    viewBox: "0 0 24 24",
    children: [
      { tag: "line", attrs: { x1: "12", y1: "5", x2: "12", y2: "19" } },
      { tag: "line", attrs: { x1: "5", y1: "12", x2: "19", y2: "12" } }
    ]
  }
}

export function buildIcon(name, size) {
  const def = ICONS[name]
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.setAttribute("viewBox", def.viewBox)
  svg.setAttribute("width", size)
  svg.setAttribute("height", size)
  svg.setAttribute("fill", "none")

  def.children.forEach(({ tag, attrs }) => {
    const el = document.createElementNS("http://www.w3.org/2000/svg", tag)
    Object.entries(attrs).forEach(([k, v]) => el.setAttribute(k, v))
    el.setAttribute("stroke", "currentColor")
    el.setAttribute("stroke-width", "2")
    el.setAttribute("stroke-linecap", "round")
    el.setAttribute("stroke-linejoin", "round")
    svg.appendChild(el)
  })

  return svg
}
