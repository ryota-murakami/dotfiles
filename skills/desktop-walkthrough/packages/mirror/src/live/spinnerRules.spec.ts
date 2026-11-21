import { expect, test } from 'vitest'

import {
  formatTokens,
  glyphAt,
  layoutBracket,
  lightCentre,
  splitLight,
  stallIntensity,
  stepShownLength,
  thinkingState,
  thinkingWording,
  tokensOfLength,
} from './spinnerRules'

test('the spinner glyph grows from a dot to the large star and falls back once every two seconds', () => {
  // Arrange
  const momentsOfOneCycle = [0, 300, 600, 700, 1000, 1300]

  // Act
  const glyphs = momentsOfOneCycle.map((ms) => glyphAt(1_795_000_000_000 - (1_795_000_000_000 % 2000) + ms))

  // Assert
  expect(glyphs).toEqual(['·', '✢', '✶', '✻', '✽', '✻'])
})

test('the light runs left to right while the request is sent and right to left otherwise', () => {
  // Arrange
  const verbWidth = 9

  // Act
  const requesting = [0, 50, 100].map((ms) => lightCentre(ms, 'requesting', verbWidth))
  const responding = [0, 200, 400].map((ms) => lightCentre(ms, 'responding', verbWidth))

  // Assert
  expect(requesting).toEqual([-10, -9, -8])
  expect(responding).toEqual([19, 18, 17])
})

test('the light lights the three cells around its centre of the verb', () => {
  // Arrange
  const verb = 'Puzzling…'

  // Act
  const runs = splitLight(verb, 4)

  // Assert
  expect(runs).toEqual([
    { text: 'Puz', isLit: false },
    { text: 'zli', isLit: true },
    { text: 'ng…', isLit: false },
  ])
})

test('a quiet turn starts to turn red after ten seconds and is fully red after twenty', () => {
  // Arrange
  const silences = [9_000, 10_000, 15_000, 20_000, 40_000]

  // Act
  const intensities = silences.map(stallIntensity)

  // Assert
  expect(intensities).toEqual([0, 0, 0.5, 1, 1])
})

test('the thinking wording changes at ten, twenty, thirty and forty-five seconds and names the effort', () => {
  // Arrange
  const durations = [0, 9_999, 10_000, 20_000, 30_000, 45_000]

  // Act
  const wordings = durations.map((ms) => thinkingWording(ms, undefined))
  const withEffort = thinkingWording(12_000, 'MAX')

  // Assert
  expect(wordings).toEqual([
    'thinking',
    'thinking',
    'still thinking',
    'thinking more',
    'thinking some more',
    'deep in thought',
  ])
  expect(withEffort).toBe('still thinking with max effort')
})

test('after thinking ends the line says how long it took for two seconds and then drops it', () => {
  // Arrange
  const thought = { start: 1000, end: 9000 }

  // Act
  const states = [8_999, 9_000, 10_999, 11_000].map((now) => thinkingState(now, thought))

  // Assert
  expect(states).toEqual([
    { kind: 'thinking', thinkingMs: 7_999 },
    { kind: 'thought-for', seconds: 8 },
    { kind: 'thought-for', seconds: 8 },
    { kind: 'none' },
  ])
})

test('a thought shorter than two seconds shows no label before it has lasted two seconds', () => {
  // Arrange
  const thought = { start: 1000, end: 1400 }

  // Act
  const states = [1_500, 2_999, 3_000].map((now) => thinkingState(now, thought))

  // Assert
  expect(states).toEqual([
    { kind: 'thinking', thinkingMs: 500 },
    { kind: 'thinking', thinkingMs: 1_999 },
    { kind: 'thought-for', seconds: 1 },
  ])
})

test('the token figure is a quarter of the response length in the terminal format', () => {
  // Arrange
  const lengths = [0, 3_996, 4_000, 20_800, 338_400, 4_800_000]

  // Act
  const figures = lengths.map((length) => formatTokens(tokensOfLength(length)))

  // Assert
  expect(figures).toEqual(['0', '999', '1.0k', '5.2k', '84.6k', '1.2m'])
})

test('the token figure counts up in small steps and snaps when the gap is huge', () => {
  // Arrange
  const steps = [
    [0, 60],
    [0, 150],
    [0, 1_000],
    [0, 2_001],
    [100, 40],
  ] as const

  // Act
  const next = steps.map(([shown, target]) => stepShownLength(shown, target))

  // Assert
  expect(next).toEqual([3, 23, 50, 2_001, 40])
})

test('a narrow line drops the tokens first, then the time, and keeps the thinking text longest', () => {
  // Arrange
  const parts = {
    verbWidth: 10,
    elapsed: '1m 5s',
    tokens: '↓ 84.6k tokens',
    thinking: { text: 'thinking with max effort', fallback: 'thinking' },
  }

  // Act
  const wide = layoutBracket({ columns: 110, ...parts })
  const medium = layoutBracket({ columns: 60, ...parts })
  const narrow = layoutBracket({ columns: 32, ...parts })

  // Assert
  expect(wide).toEqual({
    elapsed: '1m 5s',
    tokens: '↓ 84.6k tokens',
    thinking: 'thinking with max effort',
    isThinkingAlone: false,
  })
  expect(medium).toEqual({
    elapsed: '1m 5s',
    tokens: undefined,
    thinking: 'thinking with max effort',
    isThinkingAlone: false,
  })
  expect(narrow).toEqual({
    elapsed: undefined,
    tokens: undefined,
    thinking: 'thinking',
    isThinkingAlone: true,
  })
})
