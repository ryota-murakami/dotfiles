import { expect, test } from 'vitest'

import { createPin } from './useStickToBottom'

/** A scroll container of 100 px that clamps its position like a real one. */
function scrollBox(contentHeight: number) {
  let top = 0
  return {
    clientHeight: 100,
    scrollHeight: contentHeight,
    get scrollTop() {
      return top
    },
    set scrollTop(value: number) {
      top = Math.max(0, Math.min(value, this.scrollHeight - this.clientHeight))
    },
  }
}

test('stays at the newest Row when a Row arrives before the event of its own scroll', () => {
  // Arrange
  const box = scrollBox(500)
  const pin = createPin(box)
  pin.follow()

  // Act: a Row makes the content taller, and only then the container reports the pin's own scroll
  box.scrollHeight = 560
  pin.onScroll()
  pin.follow()

  // Assert
  expect(box.scrollTop).toBe(460)
})

test('leaves the reader where they scrolled to while new Rows arrive', () => {
  // Arrange
  const box = scrollBox(500)
  const pin = createPin(box)
  pin.follow()

  // Act
  box.scrollTop = 120
  pin.onScroll()
  box.scrollHeight = 560
  pin.follow()

  // Assert
  expect(box.scrollTop).toBe(120)
})

test('follows the newest Row again once the reader scrolls back to the bottom', () => {
  // Arrange
  const box = scrollBox(500)
  const pin = createPin(box)
  pin.follow()
  box.scrollTop = 120
  pin.onScroll()

  // Act
  box.scrollTop = 400
  pin.onScroll()
  box.scrollHeight = 560
  pin.follow()

  // Assert
  expect(box.scrollTop).toBe(460)
})
