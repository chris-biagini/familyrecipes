import assert from "node:assert/strict"
import { test } from "node:test"
import {
  simulateCurve,
  buildKeyframes,
  positionAtTime
} from "../../app/javascript/utilities/spin_physics.js"

function assertCloseTo(actual, expected, delta) {
  assert.ok(Math.abs(actual - expected) <= delta,
    `Expected ${actual} to be within ${delta} of ${expected}`)
}

test("simulateCurve returns keyframes starting at zero", () => {
  const kf = simulateCurve(1200, 68.75, 0.515625)
  assert.equal(kf[0].t, 0)
  assert.equal(kf[0].pos, 0)
  assert.equal(kf[0].v, 1200)
})

test("simulateCurve ends with velocity near zero", () => {
  const kf = simulateCurve(1200, 68.75, 0.515625)
  const last = kf[kf.length - 1]
  assert.ok(last.v < 1, `Final velocity ${last.v} should be < 1`)
  assert.ok(last.pos > 0, "Should have traveled some distance")
  assert.ok(last.t > 0, "Should have taken some time")
})

test("simulateCurve positions are monotonically increasing", () => {
  const kf = simulateCurve(1200, 68.75, 0.515625)
  for (let i = 1; i < kf.length; i++) {
    assert.ok(kf[i].pos >= kf[i - 1].pos, `Position decreased at index ${i}`)
  }
})

test("simulateCurve with pure constant friction", () => {
  const kf = simulateCurve(100, 50, 0)
  const last = kf[kf.length - 1]
  assertCloseTo(last.t, 2.0, 0.1)
})

test("buildKeyframes lands exactly on a slot boundary", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  const last = result.keyframes[result.keyframes.length - 1]
  assertCloseTo(last.pos, result.targetAngle, 0.01)
  assert.equal(result.targetAngle % 30, 0)
})

test("buildKeyframes ensures minimum 720 degrees of travel", () => {
  const result = buildKeyframes(50, 275, 0.75, 30)
  assert.ok(result.targetAngle >= 720,
    `Should travel at least 720°, got ${result.targetAngle}`)
})

test("buildKeyframes returns winnerSlot as index into 12 slots", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  assert.ok(result.winnerSlot >= 0 && result.winnerSlot < 12,
    `winnerSlot should be 0-11, got ${result.winnerSlot}`)
})

test("buildKeyframes winnerSlot matches target angle", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  const expectedSlot = (result.targetAngle / 30) % 12
  assert.equal(result.winnerSlot, expectedSlot)
})

test("positionAtTime interpolates correctly at midpoint", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  const totalTime = result.keyframes[result.keyframes.length - 1].t
  const mid = positionAtTime(result.keyframes, totalTime / 2)
  assert.ok(mid.pos > 0, "Should have traveled some distance at midpoint")
  assert.ok(mid.pos < result.targetAngle, "Should not have reached target at midpoint")
})

test("positionAtTime returns last keyframe at end", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  const totalTime = result.keyframes[result.keyframes.length - 1].t
  const end = positionAtTime(result.keyframes, totalTime + 1)
  assertCloseTo(end.pos, result.targetAngle, 0.01)
})
