import { cleanup } from '@testing-library/react'
import { afterEach } from 'vitest'

// Without vitest's globals, the testing library does not unmount what a test rendered
afterEach(() => {
  cleanup()
})
