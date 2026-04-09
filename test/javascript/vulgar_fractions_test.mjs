import assert from "node:assert/strict"
import { test } from "node:test"
import { toFractionString } from "../../app/javascript/utilities/vulgar_fractions.js"

test("integer returns plain number", () => {
  assert.equal(toFractionString(2.0), "2")
})

test("half returns 1/2", () => {
  assert.equal(toFractionString(0.5), "1/2")
})

test("third returns 1/3", () => {
  assert.equal(toFractionString(1/3), "1/3")
})

test("fifth returns 1/5", () => {
  assert.equal(toFractionString(0.2), "1/5")
})

test("sixth returns 1/6", () => {
  assert.equal(toFractionString(1/6), "1/6")
})

test("quarter returns 1/4", () => {
  assert.equal(toFractionString(0.25), "1/4")
})

test("three quarters returns 3/4", () => {
  assert.equal(toFractionString(0.75), "3/4")
})

test("mixed half returns 1 1/2", () => {
  assert.equal(toFractionString(1.5), "1 1/2")
})

test("mixed quarter returns 2 1/4", () => {
  assert.equal(toFractionString(2.25), "2 1/4")
})

test("non-matching decimal returns rounded", () => {
  assert.equal(toFractionString(1.37), "1.37")
})

test("zero returns 0", () => {
  assert.equal(toFractionString(0), "0")
})
