/**
 * Tests for TimelineActionsMenu
 *
 * Tests cover:
 * - Menu injection and rendering
 * - Ownership detection (isOwner logic)
 * - Action filtering based on event type
 * - Unsubscribe action (success/error cases)
 * - Keyboard navigation (Escape key)
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import {
  setupCSRFToken,
  setupCurrentUser,
  createTimelineContainer,
  mockFetch
} from './setup'

// Mock the dependencies before importing the module
vi.mock('../privacy_manager', () => ({
  privacyManager: {
    requestPrivacyChoice: vi.fn(),
    clearCache: vi.fn()
  }
}))

vi.mock('../toast_notifications', () => ({
  toastManager: {
    show: vi.fn()
  }
}))

// Import after mocking
import { TimelineActionsMenu } from '../timeline_actions_menu'
import { privacyManager } from '../privacy_manager'
import { toastManager } from '../toast_notifications'

describe('TimelineActionsMenu', () => {
  let menu: TimelineActionsMenu

  beforeEach(() => {
    // Setup DOM environment
    setupCSRFToken('test-csrf-token')
    vi.clearAllMocks()
  })

  afterEach(() => {
    document.body.innerHTML = ''
    document.head.innerHTML = ''
  })

  describe('Menu injection and rendering', () => {
    it('should inject action buttons into event cards', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button')
      expect(menuButton).not.toBeNull()
    })

    it('should not duplicate menu buttons on re-initialization', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')
      menu.initialize('timeline') // Re-initialize

      const menuButtons = document.querySelectorAll('.timeline-menu-button')
      expect(menuButtons.length).toBe(1)
    })

    it('should warn and not crash when container not found', () => {
      const warnSpy = vi.spyOn(console, 'warn')
      menu = new TimelineActionsMenu()
      menu.initialize('non-existent-container')

      expect(warnSpy).toHaveBeenCalledWith(
        expect.stringContaining('Container non-existent-container not found')
      )
    })

    it('should add group class to event cards for hover effect', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const eventCard = document.querySelector('[data-event-id="event-1"]')
      expect(eventCard?.classList.contains('group')).toBe(true)
    })

    it('should show dropdown when menu button is clicked', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      expect(dropdown?.classList.contains('hidden')).toBe(false)
    })

    it('should close dropdown when clicking outside', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      // Open menu
      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      // Click outside
      document.body.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      expect(dropdown?.classList.contains('hidden')).toBe(true)
    })
  })

  describe('Ownership detection (isOwner logic)', () => {
    it('should show owner-only actions when user owns the event', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      const unsubscribeAction = dropdown?.querySelector('button')
      const actionTexts = Array.from(dropdown?.querySelectorAll('button') || []).map(
        (btn) => btn.textContent?.trim()
      )

      // Should include owner-only actions like Unsubscribe and Change Privacy
      expect(actionTexts.some((text) => text?.includes('Unsubscribe'))).toBe(true)
      expect(actionTexts.some((text) => text?.includes('Change Privacy'))).toBe(true)
    })

    it('should hide owner-only actions when user does not own the event', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'other-user-456', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      const actionTexts = Array.from(dropdown?.querySelectorAll('button') || []).map(
        (btn) => btn.textContent?.trim()
      )

      // Should NOT include owner-only actions
      expect(actionTexts.some((text) => text?.includes('Unsubscribe'))).toBe(false)
      expect(actionTexts.some((text) => text?.includes('Change Privacy'))).toBe(false)
      // But should include public actions
      expect(actionTexts.some((text) => text?.includes('View Podcast'))).toBe(true)
    })

    it('should hide auth-required actions when user is not logged in', () => {
      setupCurrentUser(null) // No user logged in
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'other-user', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      const actionTexts = Array.from(dropdown?.querySelectorAll('button') || []).map(
        (btn) => btn.textContent?.trim()
      )

      // Should NOT include auth-required actions
      expect(actionTexts.some((text) => text?.includes('Unsubscribe'))).toBe(false)
      expect(actionTexts.some((text) => text?.includes('Change Privacy'))).toBe(false)
      // Should include public actions
      expect(actionTexts.some((text) => text?.includes('View Podcast'))).toBe(true)
    })
  })

  describe('Action filtering based on event type', () => {
    it('should show View Episode action for play events', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        {
          id: 'event-1',
          eventType: 'play',
          userId: 'user-123',
          feed: 'podcast-feed-1',
          item: 'episode-guid-1'
        }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      const actionTexts = Array.from(dropdown?.querySelectorAll('button') || []).map(
        (btn) => btn.textContent?.trim()
      )

      expect(actionTexts.some((text) => text?.includes('View Episode'))).toBe(true)
    })

    it('should NOT show View Episode action for subscribe events', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      const actionTexts = Array.from(dropdown?.querySelectorAll('button') || []).map(
        (btn) => btn.textContent?.trim()
      )

      expect(actionTexts.some((text) => text?.includes('View Episode'))).toBe(false)
    })

    it('should show Unsubscribe action only for subscribe events (not play)', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        {
          id: 'event-1',
          eventType: 'play',
          userId: 'user-123',
          feed: 'podcast-feed-1',
          item: 'episode-1'
        }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      const actionTexts = Array.from(dropdown?.querySelectorAll('button') || []).map(
        (btn) => btn.textContent?.trim()
      )

      // Unsubscribe should NOT appear for play events
      expect(actionTexts.some((text) => text?.includes('Unsubscribe'))).toBe(false)
    })

    it('should always show View Podcast action', () => {
      setupCurrentUser(null)
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'other-user', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      const actionTexts = Array.from(dropdown?.querySelectorAll('button') || []).map(
        (btn) => btn.textContent?.trim()
      )

      expect(actionTexts.some((text) => text?.includes('View Podcast'))).toBe(true)
    })
  })

  describe('Unsubscribe action', () => {
    beforeEach(() => {
      // Mock window.confirm
      vi.spyOn(window, 'confirm').mockReturnValue(true)
    })

    it('should call unsubscribe API and show success toast on success', async () => {
      setupCurrentUser('user-123')
      mockFetch({ ok: true, status: 200 })

      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      // Open menu and click unsubscribe
      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      const unsubscribeBtn = Array.from(dropdown?.querySelectorAll('button') || []).find(
        (btn) => btn.textContent?.includes('Unsubscribe')
      ) as HTMLElement

      unsubscribeBtn.click()

      // Wait for async action
      await vi.waitFor(() => {
        expect(toastManager.show).toHaveBeenCalledWith('Successfully unsubscribed', 'success')
      })

      // Card should be faded
      const eventCard = document.querySelector('[data-event-id="event-1"]') as HTMLElement
      expect(eventCard.style.opacity).toBe('0.5')
    })

    it('should show error toast on API failure', async () => {
      setupCurrentUser('user-123')
      mockFetch({ ok: false, status: 500 })

      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      // Open menu and click unsubscribe
      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      const unsubscribeBtn = Array.from(dropdown?.querySelectorAll('button') || []).find(
        (btn) => btn.textContent?.includes('Unsubscribe')
      ) as HTMLElement

      unsubscribeBtn.click()

      // Wait for async action
      await vi.waitFor(() => {
        expect(toastManager.show).toHaveBeenCalledWith(
          'Server error, please try again later',
          'error'
        )
      })
    })

    it('should show appropriate error message for 401 status', async () => {
      setupCurrentUser('user-123')
      mockFetch({ ok: false, status: 401 })

      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const unsubscribeBtn = Array.from(
        document.querySelector('.timeline-menu-dropdown')?.querySelectorAll('button') || []
      ).find((btn) => btn.textContent?.includes('Unsubscribe')) as HTMLElement

      unsubscribeBtn.click()

      await vi.waitFor(() => {
        expect(toastManager.show).toHaveBeenCalledWith(
          'You must be logged in to unsubscribe',
          'error'
        )
      })
    })

    it('should show appropriate error message for 404 status', async () => {
      setupCurrentUser('user-123')
      mockFetch({ ok: false, status: 404 })

      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const unsubscribeBtn = Array.from(
        document.querySelector('.timeline-menu-dropdown')?.querySelectorAll('button') || []
      ).find((btn) => btn.textContent?.includes('Unsubscribe')) as HTMLElement

      unsubscribeBtn.click()

      await vi.waitFor(() => {
        expect(toastManager.show).toHaveBeenCalledWith('Subscription not found', 'error')
      })
    })

    it('should not call API if user cancels confirmation', async () => {
      setupCurrentUser('user-123')
      vi.spyOn(window, 'confirm').mockReturnValue(false)
      const fetchSpy = vi.fn()
      global.fetch = fetchSpy

      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const unsubscribeBtn = Array.from(
        document.querySelector('.timeline-menu-dropdown')?.querySelectorAll('button') || []
      ).find((btn) => btn.textContent?.includes('Unsubscribe')) as HTMLElement

      unsubscribeBtn.click()

      // Fetch should not be called
      expect(fetchSpy).not.toHaveBeenCalled()
    })

    it('should restore card opacity on API error', async () => {
      setupCurrentUser('user-123')
      mockFetch({ ok: false, status: 500 })

      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const eventCard = document.querySelector('[data-event-id="event-1"]') as HTMLElement
      eventCard.style.opacity = '1' // Set initial opacity

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const unsubscribeBtn = Array.from(
        document.querySelector('.timeline-menu-dropdown')?.querySelectorAll('button') || []
      ).find((btn) => btn.textContent?.includes('Unsubscribe')) as HTMLElement

      unsubscribeBtn.click()

      await vi.waitFor(() => {
        expect(toastManager.show).toHaveBeenCalled()
      })

      // Opacity should be restored to original
      expect(eventCard.style.opacity).toBe('1')
    })
  })

  describe('Change Privacy action', () => {
    it('should call privacyManager.requestPrivacyChoice when Change Privacy is clicked', async () => {
      setupCurrentUser('user-123')
      vi.mocked(privacyManager.requestPrivacyChoice).mockResolvedValue('public')

      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const changePrivacyBtn = Array.from(
        document.querySelector('.timeline-menu-dropdown')?.querySelectorAll('button') || []
      ).find((btn) => btn.textContent?.includes('Change Privacy')) as HTMLElement

      changePrivacyBtn.click()

      await vi.waitFor(() => {
        expect(privacyManager.requestPrivacyChoice).toHaveBeenCalledWith(
          'podcast-feed-1',
          'subscribe'
        )
      })
    })

    it('should show success toast and clear cache after privacy change', async () => {
      setupCurrentUser('user-123')
      vi.mocked(privacyManager.requestPrivacyChoice).mockResolvedValue('friends')

      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const changePrivacyBtn = Array.from(
        document.querySelector('.timeline-menu-dropdown')?.querySelectorAll('button') || []
      ).find((btn) => btn.textContent?.includes('Change Privacy')) as HTMLElement

      changePrivacyBtn.click()

      await vi.waitFor(() => {
        expect(toastManager.show).toHaveBeenCalledWith('Privacy updated to friends', 'success')
        expect(privacyManager.clearCache).toHaveBeenCalled()
      })
    })

    it('should use play context for play events', async () => {
      setupCurrentUser('user-123')
      vi.mocked(privacyManager.requestPrivacyChoice).mockResolvedValue('public')

      createTimelineContainer('timeline', [
        {
          id: 'event-1',
          eventType: 'play',
          userId: 'user-123',
          feed: 'podcast-feed-1',
          item: 'episode-1'
        }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const changePrivacyBtn = Array.from(
        document.querySelector('.timeline-menu-dropdown')?.querySelectorAll('button') || []
      ).find((btn) => btn.textContent?.includes('Change Privacy')) as HTMLElement

      changePrivacyBtn.click()

      await vi.waitFor(() => {
        expect(privacyManager.requestPrivacyChoice).toHaveBeenCalledWith('podcast-feed-1', 'play')
      })
    })
  })

  describe('Keyboard navigation (Escape key)', () => {
    it('should close menu when Escape key is pressed', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      // Open menu
      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const dropdown = document.querySelector('.timeline-menu-dropdown')
      expect(dropdown?.classList.contains('hidden')).toBe(false)

      // Press Escape
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))

      expect(dropdown?.classList.contains('hidden')).toBe(true)
    })

    it('should not throw error when Escape is pressed with no menu open', () => {
      setupCurrentUser('user-123')
      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'podcast-feed-1' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      // Press Escape without opening menu - should not throw
      expect(() => {
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
      }).not.toThrow()
    })
  })

  describe('Navigation actions', () => {
    it('should navigate to podcast page when View Podcast is clicked', () => {
      setupCurrentUser('user-123')
      const locationAssign = vi.fn()
      Object.defineProperty(window, 'location', {
        value: { href: '', assign: locationAssign },
        writable: true
      })

      createTimelineContainer('timeline', [
        { id: 'event-1', eventType: 'subscribe', userId: 'user-123', feed: 'my-podcast-feed' }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const viewPodcastBtn = Array.from(
        document.querySelector('.timeline-menu-dropdown')?.querySelectorAll('button') || []
      ).find((btn) => btn.textContent?.includes('View Podcast')) as HTMLElement

      viewPodcastBtn.click()

      expect(window.location.href).toBe('/podcasts/my-podcast-feed')
    })

    it('should navigate to episode page when View Episode is clicked', () => {
      setupCurrentUser('user-123')
      Object.defineProperty(window, 'location', {
        value: { href: '' },
        writable: true
      })

      createTimelineContainer('timeline', [
        {
          id: 'event-1',
          eventType: 'play',
          userId: 'user-123',
          feed: 'podcast-feed-1',
          item: 'episode-guid-123'
        }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const viewEpisodeBtn = Array.from(
        document.querySelector('.timeline-menu-dropdown')?.querySelectorAll('button') || []
      ).find((btn) => btn.textContent?.includes('View Episode')) as HTMLElement

      viewEpisodeBtn.click()

      expect(window.location.href).toBe('/episodes/episode-guid-123')
    })

    it('should properly encode special characters in feed URL', () => {
      setupCurrentUser('user-123')
      Object.defineProperty(window, 'location', {
        value: { href: '' },
        writable: true
      })

      createTimelineContainer('timeline', [
        {
          id: 'event-1',
          eventType: 'subscribe',
          userId: 'user-123',
          feed: 'feed with spaces & special'
        }
      ])

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      const menuButton = document.querySelector('.timeline-menu-button') as HTMLElement
      menuButton.click()

      const viewPodcastBtn = Array.from(
        document.querySelector('.timeline-menu-dropdown')?.querySelectorAll('button') || []
      ).find((btn) => btn.textContent?.includes('View Podcast')) as HTMLElement

      viewPodcastBtn.click()

      expect(window.location.href).toBe('/podcasts/feed%20with%20spaces%20%26%20special')
    })
  })

  describe('Event data extraction', () => {
    it('should skip events without required data attributes', () => {
      setupCurrentUser('user-123')

      // Create container with incomplete event card
      const container = document.createElement('div')
      container.id = 'timeline'

      const incompleteCard = document.createElement('article')
      incompleteCard.setAttribute('data-event-id', 'event-1')
      // Missing data-event-type
      container.appendChild(incompleteCard)

      document.body.appendChild(container)

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      // No menu button should be injected
      const menuButton = container.querySelector('.timeline-menu-button')
      expect(menuButton).toBeNull()
    })

    it('should skip events without feed link', () => {
      setupCurrentUser('user-123')

      const container = document.createElement('div')
      container.id = 'timeline'

      const cardWithoutFeed = document.createElement('article')
      cardWithoutFeed.setAttribute('data-event-id', 'event-1')
      cardWithoutFeed.setAttribute('data-event-type', 'subscribe')

      // Add timestamp but no podcast link
      const time = document.createElement('time')
      const timeContainer = document.createElement('div')
      timeContainer.appendChild(time)
      cardWithoutFeed.appendChild(timeContainer)

      container.appendChild(cardWithoutFeed)
      document.body.appendChild(container)

      menu = new TimelineActionsMenu()
      menu.initialize('timeline')

      // No menu button should be injected because feed cannot be extracted
      const menuButton = container.querySelector('.timeline-menu-button')
      expect(menuButton).toBeNull()
    })
  })
})
