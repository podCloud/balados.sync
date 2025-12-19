/**
 * Vitest test setup file
 * Configures DOM environment and global test utilities
 */

import { vi } from 'vitest'

// Mock console methods to reduce noise in tests
vi.spyOn(console, 'log').mockImplementation(() => {})
vi.spyOn(console, 'warn').mockImplementation(() => {})

// Reset DOM between tests
beforeEach(() => {
  document.body.innerHTML = ''
  document.head.innerHTML = ''
})

// Clear all mocks after each test
afterEach(() => {
  vi.clearAllMocks()
})

// Setup CSRF meta tag (commonly needed)
export function setupCSRFToken(token: string = 'test-csrf-token'): void {
  const meta = document.createElement('meta')
  meta.setAttribute('name', 'csrf-token')
  meta.setAttribute('content', token)
  document.head.appendChild(meta)
}

// Setup current user ID on body
export function setupCurrentUser(userId: string | null): void {
  if (userId) {
    document.body.setAttribute('data-current-user-id', userId)
  } else {
    document.body.removeAttribute('data-current-user-id')
  }
}

// Create a mock timeline event element
export function createTimelineEventElement(options: {
  id: string
  eventType: 'play' | 'subscribe'
  userId?: string | null
  privacy?: string
  feed: string
  item?: string | null
}): HTMLElement {
  const { id, eventType, userId, privacy = 'public', feed, item } = options

  const article = document.createElement('article')
  article.setAttribute('data-event-id', id)
  article.setAttribute('data-event-type', eventType)
  if (userId) {
    article.setAttribute('data-user-id', userId)
  }
  article.setAttribute('data-privacy', privacy)

  // Create timestamp element (needed for menu injection)
  const timeContainer = document.createElement('div')
  const time = document.createElement('time')
  time.textContent = '2 hours ago'
  timeContainer.appendChild(time)
  article.appendChild(timeContainer)

  // Create podcast link
  const podcastLink = document.createElement('a')
  podcastLink.href = `/podcasts/${feed}`
  podcastLink.textContent = 'Test Podcast'
  article.appendChild(podcastLink)

  // Create episode link for play events
  if (eventType === 'play' && item) {
    const episodeLink = document.createElement('a')
    episodeLink.href = `/episodes/${item}`
    episodeLink.textContent = 'Test Episode'
    article.appendChild(episodeLink)
  }

  return article
}

// Create timeline container with events
export function createTimelineContainer(
  containerId: string,
  events: Array<{
    id: string
    eventType: 'play' | 'subscribe'
    userId?: string | null
    privacy?: string
    feed: string
    item?: string | null
  }>
): HTMLElement {
  const container = document.createElement('div')
  container.id = containerId

  events.forEach((event) => {
    container.appendChild(createTimelineEventElement(event))
  })

  document.body.appendChild(container)
  return container
}

// Mock fetch for API calls
export function mockFetch(
  response: { ok: boolean; status?: number; json?: () => Promise<unknown> }
): void {
  global.fetch = vi.fn().mockResolvedValue({
    ok: response.ok,
    status: response.status ?? (response.ok ? 200 : 500),
    json: response.json ?? (async () => ({}))
  })
}

// Mock localStorage
export function mockLocalStorage(): {
  getItem: ReturnType<typeof vi.fn>
  setItem: ReturnType<typeof vi.fn>
  removeItem: ReturnType<typeof vi.fn>
  clear: ReturnType<typeof vi.fn>
} {
  const storage: Record<string, string> = {}

  const mock = {
    getItem: vi.fn((key: string) => storage[key] ?? null),
    setItem: vi.fn((key: string, value: string) => {
      storage[key] = value
    }),
    removeItem: vi.fn((key: string) => {
      delete storage[key]
    }),
    clear: vi.fn(() => {
      Object.keys(storage).forEach((key) => delete storage[key])
    })
  }

  Object.defineProperty(window, 'localStorage', {
    value: mock,
    writable: true
  })

  return mock
}
