/**
 * Timeline Actions Menu
 * Provides contextual action menus for timeline events with hover-triggered dropdowns.
 * Actions include navigation, unsubscribe, and privacy changes.
 */

import { privacyManager } from './privacy_manager'
import { toastManager } from './toast_notifications'

interface TimelineEventData {
  id: string
  eventType: string
  userId: string | null
  privacy: string
  feed: string
  item: string | null
}

interface ActionMenuItem {
  label: string
  icon: string
  action: (event: TimelineEventData, element: HTMLElement) => void
  destructive?: boolean
  requiresAuth?: boolean
  requiresOwnership?: boolean
}

class TimelineActionsMenu {
  private activeMenu: HTMLElement | null = null
  private activeButton: HTMLElement | null = null
  private currentUserId: string | null = null
  private csrfToken: string
  private initialized: boolean = false

  constructor() {
    this.csrfToken = this.getCSRFToken()
    this.currentUserId = this.getCurrentUserId()
    console.log('[TimelineActions] Initialized, currentUserId:', this.currentUserId)
  }

  /**
   * Initialize action menus for timeline events
   */
  initialize(containerId: string): void {
    const container = document.getElementById(containerId)
    if (!container) {
      console.warn(`[TimelineActions] Container ${containerId} not found`)
      return
    }

    // Inject action buttons into each event card
    this.injectActionButtons(container)

    // Setup global event listeners only once to prevent memory leaks
    if (!this.initialized) {
      // Setup global click listener to close menus
      document.addEventListener('click', (e) => {
        if (this.activeMenu && !this.activeMenu.contains(e.target as Node)) {
          this.closeActiveMenu()
        }
      })

      // Close on Escape key
      document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && this.activeMenu) {
          this.closeActiveMenu()
        }
      })

      this.initialized = true
    }

    console.log('[TimelineActions] Initialized for container:', containerId)
  }

  /**
   * Inject action buttons into each event card
   */
  private injectActionButtons(container: HTMLElement): void {
    const eventCards = container.querySelectorAll('[data-event-id]')

    eventCards.forEach((card) => {
      // Skip if action menu already exists (prevent duplicate injection)
      if (card.querySelector('.timeline-action-menu')) return

      const eventData = this.extractEventData(card as HTMLElement)
      if (!eventData) return

      // Find the timestamp element and add menu button next to it
      const timestampEl = card.querySelector('time')
      if (!timestampEl) return

      // Create the menu button container
      const menuContainer = document.createElement('div')
      menuContainer.className = 'relative ml-2 timeline-action-menu'
      menuContainer.innerHTML = `
        <button
          class="timeline-menu-button opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded hover:bg-zinc-100"
          aria-label="Actions"
          title="Actions"
        >
          <svg class="w-5 h-5 text-zinc-500" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z"/>
          </svg>
        </button>
        <div class="timeline-menu-dropdown hidden absolute right-0 top-full mt-1 z-50 w-48 bg-white rounded-lg shadow-lg border border-zinc-200 py-1"></div>
      `

      // Add group class to parent for hover effect
      const cardElement = card as HTMLElement
      cardElement.classList.add('group')

      // Insert after timestamp
      timestampEl.parentElement?.appendChild(menuContainer)

      // Setup button click handler
      const button = menuContainer.querySelector('.timeline-menu-button') as HTMLElement
      const dropdown = menuContainer.querySelector('.timeline-menu-dropdown') as HTMLElement

      button.addEventListener('click', (e) => {
        e.stopPropagation()
        e.preventDefault()
        this.toggleMenu(button, dropdown, eventData, cardElement)
      })
    })
  }

  /**
   * Extract event data from DOM element
   */
  private extractEventData(element: HTMLElement): TimelineEventData | null {
    const id = element.getAttribute('data-event-id')
    const eventType = element.getAttribute('data-event-type')
    const userId = element.getAttribute('data-user-id')
    const privacy = element.getAttribute('data-privacy') || 'unknown'

    if (!id || !eventType) return null

    // Extract feed from the podcast link (stops at ?, #, or / to avoid capturing query params)
    const podcastLink = element.querySelector('a[href^="/podcasts/"]')
    const feedMatch = podcastLink?.getAttribute('href')?.match(/\/podcasts\/([^/?#]+)/)
    const feed = feedMatch?.[1] || null

    // Extract item for play events (from episode link if exists, stops at ?, #, or /)
    const episodeLink = element.querySelector('a[href^="/episodes/"]')
    const itemMatch = episodeLink?.getAttribute('href')?.match(/\/episodes\/([^/?#]+)/)
    const item = itemMatch?.[1] || null

    if (!feed) return null

    return {
      id,
      eventType,
      userId,
      privacy,
      feed,
      item
    }
  }

  /**
   * Toggle menu visibility
   */
  private toggleMenu(
    button: HTMLElement,
    dropdown: HTMLElement,
    eventData: TimelineEventData,
    cardElement: HTMLElement
  ): void {
    // Close any other open menu
    if (this.activeMenu && this.activeMenu !== dropdown) {
      this.closeActiveMenu()
    }

    if (dropdown.classList.contains('hidden')) {
      // Build menu items based on event type
      this.buildMenuItems(dropdown, eventData, cardElement)
      dropdown.classList.remove('hidden')
      this.activeMenu = dropdown
      this.activeButton = button
    } else {
      this.closeActiveMenu()
    }
  }

  /**
   * Close the currently active menu
   */
  private closeActiveMenu(): void {
    if (this.activeMenu) {
      this.activeMenu.classList.add('hidden')
      this.activeMenu = null
      this.activeButton = null
    }
  }

  /**
   * Build menu items based on event type
   */
  private buildMenuItems(
    dropdown: HTMLElement,
    eventData: TimelineEventData,
    cardElement: HTMLElement
  ): void {
    const actions = this.getActionsForEvent(eventData)
    const isOwner = this.currentUserId && eventData.userId === this.currentUserId

    dropdown.innerHTML = ''

    actions.forEach((action) => {
      // Skip actions that require ownership if not owner
      if (action.requiresOwnership && !isOwner) return
      // Skip actions that require auth if not authenticated
      if (action.requiresAuth && !this.currentUserId) return

      const item = document.createElement('button')
      item.className = `w-full text-left px-4 py-2 text-sm flex items-center gap-2 hover:bg-zinc-100 ${
        action.destructive ? 'text-red-600 hover:bg-red-50' : 'text-zinc-700'
      }`
      item.innerHTML = `
        <span class="w-4 h-4">${action.icon}</span>
        <span>${action.label}</span>
      `

      item.addEventListener('click', (e) => {
        e.stopPropagation()
        this.closeActiveMenu()
        action.action(eventData, cardElement)
      })

      dropdown.appendChild(item)
    })

    // Add separator and info if empty
    if (dropdown.children.length === 0) {
      dropdown.innerHTML = `
        <div class="px-4 py-2 text-sm text-zinc-500 italic">
          No actions available
        </div>
      `
    }
  }

  /**
   * Get available actions for an event type
   */
  private getActionsForEvent(eventData: TimelineEventData): ActionMenuItem[] {
    const actions: ActionMenuItem[] = []

    // View Podcast - always available
    actions.push({
      label: 'View Podcast',
      icon: this.icons.podcast,
      action: (data) => {
        window.location.href = `/podcasts/${encodeURIComponent(data.feed)}`
      }
    })

    // View Episode - only for play events with item
    if (eventData.eventType === 'play' && eventData.item) {
      actions.push({
        label: 'View Episode',
        icon: this.icons.episode,
        action: (data) => {
          window.location.href = `/episodes/${encodeURIComponent(data.item!)}`
        }
      })
    }

    // Separator comment for owner-only actions
    // Unsubscribe - for subscribe events, owner only
    if (eventData.eventType === 'subscribe') {
      actions.push({
        label: 'Unsubscribe',
        icon: this.icons.unsubscribe,
        action: (data, element) => this.handleUnsubscribe(data, element),
        destructive: true,
        requiresAuth: true,
        requiresOwnership: true
      })
    }

    // Change Privacy - owner only
    actions.push({
      label: 'Change Privacy',
      icon: this.icons.privacy,
      action: (data) => this.handleChangePrivacy(data),
      requiresAuth: true,
      requiresOwnership: true
    })

    return actions
  }

  /**
   * Handle unsubscribe action
   */
  private async handleUnsubscribe(
    eventData: TimelineEventData,
    cardElement: HTMLElement
  ): Promise<void> {
    // Confirm before unsubscribing
    const confirmed = confirm(
      'Are you sure you want to unsubscribe from this podcast? This action cannot be undone.'
    )
    if (!confirmed) return

    // Store original opacity for error recovery
    const originalOpacity = cardElement.style.opacity || '1'

    try {
      const response = await fetch(`/podcasts/${encodeURIComponent(eventData.feed)}/subscribe`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        credentials: 'same-origin'
      })

      if (response.ok) {
        // Visual feedback - fade out the card
        cardElement.style.transition = 'opacity 0.3s ease-out'
        cardElement.style.opacity = '0.5'

        // Show success message
        this.showToast('Successfully unsubscribed', 'success')
      } else {
        // Restore original opacity on failure
        cardElement.style.opacity = originalOpacity
        // Use predefined error messages to prevent XSS from server responses
        const errorMessage = this.getUnsubscribeErrorMessage(response.status)
        this.showToast(errorMessage, 'error')
      }
    } catch (error) {
      // Restore original opacity on error
      cardElement.style.opacity = originalOpacity
      console.error('[TimelineActions] Unsubscribe error:', error)
      this.showToast('Failed to unsubscribe', 'error')
    }
  }

  /**
   * Get predefined error message for unsubscribe failures
   * Uses predefined messages to prevent XSS from untrusted server responses
   */
  private getUnsubscribeErrorMessage(statusCode: number): string {
    switch (statusCode) {
      case 401:
        return 'You must be logged in to unsubscribe'
      case 403:
        return 'You do not have permission to unsubscribe'
      case 404:
        return 'Subscription not found'
      case 422:
        return 'Unable to process unsubscribe request'
      case 500:
      case 502:
      case 503:
        return 'Server error, please try again later'
      default:
        return 'Failed to unsubscribe'
    }
  }

  /**
   * Handle change privacy action
   */
  private async handleChangePrivacy(eventData: TimelineEventData): Promise<void> {
    const context = eventData.eventType === 'play' ? 'play' : 'subscribe'
    const newPrivacy = await privacyManager.requestPrivacyChoice(eventData.feed, context)

    if (newPrivacy) {
      this.showToast(`Privacy updated to ${newPrivacy}`, 'success')
      // Clear cache to reflect new privacy
      privacyManager.clearCache()
    }
  }

  /**
   * Show a toast notification
   */
  private showToast(message: string, type: 'success' | 'error' | 'info'): void {
    toastManager.show(message, type)
  }

  /**
   * Get CSRF token from meta tag
   */
  private getCSRFToken(): string {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token?.getAttribute('content') || ''
  }

  /**
   * Get current user ID from body data attribute
   */
  private getCurrentUserId(): string | null {
    return document.body.getAttribute('data-current-user-id') || null
  }

  /**
   * SVG icons for menu items
   */
  private icons = {
    podcast: `<svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"/></svg>`,
    episode: `<svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>`,
    unsubscribe: `<svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>`,
    privacy: `<svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/></svg>`
  }
}

// Create global instance
const timelineActionsMenu = new TimelineActionsMenu()

export { timelineActionsMenu, TimelineActionsMenu }
