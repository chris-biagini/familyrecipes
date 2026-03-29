import assert from "node:assert/strict"
import { test } from "node:test"
import {
  simulateCurve,
  buildKeyframes,
  applyCylinderWarp,
  buildReelItems
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

test("buildKeyframes lands exactly on target position", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  const last = result.keyframes[result.keyframes.length - 1]
  assertCloseTo(last.pos, result.targetPos, 0.01)
})

test("buildKeyframes target is a multiple of itemHeight", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  assert.equal(result.targetPos % 30, 0)
})

test("buildKeyframes ensures minimum travel", () => {
  const result = buildKeyframes(50, 275, 0.75, 30)
  assert.ok(result.targetItems >= 5, `Should travel at least 5 items, got ${result.targetItems}`)
})

test("buildKeyframes returns winnerIndex within reel bounds", () => {
  const result = buildKeyframes(1200, 275, 0.75, 30)
  assert.equal(result.winnerIndex, result.targetItems)
  assert.ok(result.winnerIndex > 0)
})

test("buildReelItems places winner at winnerIndex", () => {
  const recipes = [
    { title: "A", slug: "a" },
    { title: "B", slug: "b" },
    { title: "C", slug: "c" }
  ]
  const winner = recipes[1]
  const items = buildReelItems(recipes, winner, 10, 15)
  assert.equal(items[10].title, "B")
  assert.equal(items.length, 15)
})

test("buildReelItems loops recipes to fill reel", () => {
  const recipes = [
    { title: "A", slug: "a" },
    { title: "B", slug: "b" }
  ]
  const winner = recipes[0]
  const items = buildReelItems(recipes, winner, 5, 8)
  assert.equal(items[0].title, "A")
  assert.equal(items[1].title, "B")
  assert.equal(items[2].title, "A")
  assert.equal(items[5].title, "A")
})

test("applyCylinderWarp returns scaleY 1.0 at center", () => {
  const result = applyCylinderWarp(0, 76)
  assertCloseTo(result.scaleY, 1.0, 0.01)
  assertCloseTo(result.yShift, 0, 0.1)
})

test("applyCylinderWarp compresses at edges", () => {
  const result = applyCylinderWarp(1.0, 76)
  assert.ok(result.scaleY < 0.5, `scaleY at edge should be < 0.5, got ${result.scaleY}`)
})

test("applyCylinderWarp returns null for off-screen items", () => {
  const result = applyCylinderWarp(2.0, 76)
  assert.equal(result, null)
})

test("applyCylinderWarp foreshortening is gradual from center", () => {
  const center = applyCylinderWarp(0, 76)
  const nearby = applyCylinderWarp(0.2, 76)
  const mid = applyCylinderWarp(0.5, 76)
  assert.ok(nearby.scaleY < center.scaleY, "Items near center should already be slightly compressed")
  assert.ok(mid.scaleY < nearby.scaleY, "Compression should increase toward edges")
})
