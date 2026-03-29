/**
 * Physics simulation and visual effects for the dinner picker slot machine.
 * Pure functions — no DOM access, fully testable.
 *
 * - dinner_picker_controller.js: consumes these functions for animation
 * - dinner_picker_logic.js: weight computation (separate concern)
 * - test/javascript/spin_physics_test.mjs: unit tests
 */

const SIM_DT = 1 / 240

export function simulateCurve(v0, constFric, dragCoeff) {
  let v = v0
  let pos = 0
  let t = 0
  const keyframes = [{ t: 0, pos: 0, v: v0 }]

  while (v > 0.5 && t < 30) {
    const decel = constFric + dragCoeff * v
    v = Math.max(0, v - decel * SIM_DT)
    pos += v * SIM_DT
    t += SIM_DT
    keyframes.push({ t, pos, v })
  }

  return keyframes
}

export function buildKeyframes(spinForce, totalFriction, dragBlend, itemHeight) {
  const constFric = totalFriction * (1 - dragBlend)
  const dragCoeff = totalFriction * dragBlend / spinForce * 3

  const raw = simulateCurve(spinForce, constFric, dragCoeff)
  const naturalDist = raw[raw.length - 1].pos

  let targetItems = Math.round(naturalDist / itemHeight)
  if (targetItems < 5) targetItems = 5
  const targetPos = targetItems * itemHeight

  const scale = targetPos / raw[raw.length - 1].pos
  const keyframes = raw.map(kf => ({
    t: kf.t,
    pos: kf.pos * scale,
    v: kf.v * scale
  }))

  return { keyframes, targetPos, targetItems, winnerIndex: targetItems }
}

export function positionAtTime(keyframes, t) {
  if (t <= 0) return keyframes[0]
  if (t >= keyframes[keyframes.length - 1].t) return keyframes[keyframes.length - 1]

  let lo = 0
  let hi = keyframes.length - 1
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1
    if (keyframes[mid].t <= t) lo = mid
    else hi = mid
  }

  const a = keyframes[lo]
  const b = keyframes[hi]
  const frac = (t - a.t) / (b.t - a.t)
  return {
    t,
    pos: a.pos + (b.pos - a.pos) * frac,
    v: a.v + (b.v - a.v) * frac
  }
}

export function buildReelItems(recipes, winner, winnerIndex, totalItems) {
  return Array.from({ length: totalItems }, (_, i) =>
    i === winnerIndex ? winner : recipes[i % recipes.length]
  )
}

export function applyCylinderWarp(distFromCenter, itemHeight) {
  const absDist = Math.abs(distFromCenter)
  if (absDist > 1.5) return null

  const foreshorten = Math.max(0, 1 - Math.pow(absDist, 1.3))
  const scaleY = 0.15 + 0.85 * foreshorten
  const yShift = distFromCenter * (1 - scaleY) * itemHeight * 0.5

  return { scaleY, yShift }
}
