/**
 * Privacy Manager - Handles privacy checks, modal interactions, and server communication
 *
 * This module manages the privacy level selection flow for subscriptions and plays.
 * It handles caching, modal display, event listeners, and API communication.
 */

interface PrivacyCheckResponse {
  has_privacy: boolean
  privacy?: string
}

interface PrivacySetResponse {
  status: string
  privacy: string
}

export class PrivacyManager {
  private privacyCache: Map<string, string | null>
  private modal: HTMLElement | null
  private pendingActions: Map<string, () => void>
  private csrfToken: string

  constructor() {
    this.privacyCache = new Map()
    this.modal = document.getElementById('privacy-modal')
    this.pendingActions = new Map()
    this.csrfToken = this.getCSRFToken()

    console.log('[PrivacyManager] Initialized')
    this.initModalListeners()
  }

  /**
   * Check if privacy is set for a feed
   * Uses cache if available, otherwise fetches from server
   */
  async checkPrivacy(feed: string): Promise<string | null> {
    // Check cache first
    if (this.privacyCache.has(feed)) {
      const cached = this.privacyCache.get(feed)
      console.log('[PrivacyManager] Cache hit for', feed, ':', cached)
      return cached || null
    }

    try {
      console.log('[PrivacyManager] Checking privacy for feed:', feed)
      const response = await fetch(`/privacy/check/${feed}`, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
        },
        credentials: 'same-origin',
      })

      if (!response.ok) {
        console.error('[PrivacyManager] Check failed:', response.status)
        return null
      }

      const data: PrivacyCheckResponse = await response.json()
      console.log('[PrivacyManager] Check result:', data)

      if (data.has_privacy && data.privacy) {
        // Cache the result
        this.privacyCache.set(feed, data.privacy)
        return data.privacy
      } else {
        // Don't cache "not set" - user might set it
        return null
      }
    } catch (error) {
      console.error('[PrivacyManager] Check error:', error)
      return null
    }
  }

  /**
   * Set privacy level for a feed
   */
  async setPrivacy(feed: string, privacy: string): Promise<boolean> {
    try {
      console.log('[PrivacyManager] Setting privacy for', feed, 'to', privacy)

      const response = await fetch(`/privacy/set/${feed}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': this.csrfToken,
        },
        credentials: 'same-origin',
        body: JSON.stringify({ privacy }),
      })

      if (!response.ok) {
        console.error('[PrivacyManager] Set failed:', response.status)
        return false
      }

      const data: PrivacySetResponse = await response.json()
      console.log('[PrivacyManager] Set result:', data)

      if (data.status === 'success') {
        // Update cache
        this.privacyCache.set(feed, data.privacy)
        console.log('[PrivacyManager] Privacy set successfully for', feed)
        return true
      }

      return false
    } catch (error) {
      console.error('[PrivacyManager] Set error:', error)
      return false
    }
  }

  /**
   * Show privacy modal and wait for user choice
   * Returns Promise that resolves to chosen privacy level or null if cancelled
   */
  async requestPrivacyChoice(
    feed: string,
    context: 'subscribe' | 'play'
  ): Promise<string | null> {
    return new Promise((resolve) => {
      if (!this.modal) {
        console.error('[PrivacyManager] Modal not found')
        resolve(null)
        return
      }

      // Update modal attributes
      this.modal.setAttribute('data-feed', feed)
      this.modal.setAttribute('data-context', context)

      console.log('[PrivacyManager] Showing modal for', context, 'on feed:', feed)

      // Show modal (remove 'hidden' class)
      this.modal.classList.remove('hidden')

      // Focus first button
      const firstButton = this.modal.querySelector('.js-privacy-option')
      if (firstButton instanceof HTMLElement) {
        firstButton.focus()
      }

      // Setup one-time listeners for this request
      const handleChoice = async (privacy: string) => {
        console.log('[PrivacyManager] User chose:', privacy)
        this.modal?.classList.add('hidden')

        // Set privacy on server
        const success = await this.setPrivacy(feed, privacy)

        if (success) {
          resolve(privacy)
        } else {
          // If setting failed, return null to allow retry
          resolve(null)
        }

        cleanup()
      }

      const handleCancel = () => {
        console.log('[PrivacyManager] User cancelled privacy choice')
        this.modal?.classList.add('hidden')
        resolve(null)
        cleanup()
      }

      const cleanup = () => {
        document.removeEventListener('privacy-choice', choiceListener)
        document.removeEventListener('privacy-cancel', cancelListener)
      }

      const choiceListener = (e: Event) => {
        const customEvent = e as CustomEvent
        handleChoice(customEvent.detail.privacy)
      }

      const cancelListener = () => {
        handleCancel()
      }

      document.addEventListener('privacy-choice', choiceListener)
      document.addEventListener('privacy-cancel', cancelListener)
    })
  }

  /**
   * Check privacy and show modal if needed
   * Returns Promise with privacy level (or null if private/cancelled)
   * This is the main public API
   */
  async ensurePrivacy(
    feed: string,
    context: 'subscribe' | 'play'
  ): Promise<string | null> {
    console.log('[PrivacyManager] Ensuring privacy for', context, ':', feed)

    // Check if privacy is already set
    const existingPrivacy = await this.checkPrivacy(feed)

    if (existingPrivacy) {
      // Privacy already set
      console.log('[PrivacyManager] Privacy already set to:', existingPrivacy)
      return existingPrivacy
    }

    // Privacy not set - show modal
    console.log('[PrivacyManager] Privacy not set, showing modal')
    return this.requestPrivacyChoice(feed, context)
  }

  /**
   * Initialize modal button listeners
   */
  private initModalListeners(): void {
    if (!this.modal) {
      console.warn('[PrivacyManager] Modal element not found during initialization')
      return
    }

    console.log('[PrivacyManager] Setting up modal listeners')

    // Privacy option buttons
    const optionButtons = this.modal.querySelectorAll('.js-privacy-option')
    optionButtons.forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.preventDefault()
        const button = e.currentTarget as HTMLElement
        const privacy = button.getAttribute('data-privacy')
        if (privacy) {
          console.log('[PrivacyManager] Privacy option clicked:', privacy)
          // Dispatch custom event
          document.dispatchEvent(
            new CustomEvent('privacy-choice', {
              detail: { privacy },
            })
          )
        }
      })
    })

    // Cancel buttons
    const cancelButtons = this.modal.querySelectorAll('.js-hide-modal')
    cancelButtons.forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.preventDefault()
        console.log('[PrivacyManager] Cancel button clicked')
        document.dispatchEvent(new CustomEvent('privacy-cancel'))
      })
    })

    // Background click
    this.modal.addEventListener('click', (e) => {
      if (e.target === this.modal) {
        console.log('[PrivacyManager] Background clicked')
        document.dispatchEvent(new CustomEvent('privacy-cancel'))
      }
    })

    // Escape key
    document.addEventListener('keydown', (e) => {
      if (
        e.key === 'Escape' &&
        this.modal &&
        !this.modal.classList.contains('hidden')
      ) {
        console.log('[PrivacyManager] Escape key pressed')
        document.dispatchEvent(new CustomEvent('privacy-cancel'))
      }
    })
  }

  /**
   * Get CSRF token from meta tag
   */
  private getCSRFToken(): string {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token?.getAttribute('content') || ''
  }

  /**
   * Clear privacy cache (useful after logout or manual privacy changes)
   */
  clearCache(): void {
    console.log('[PrivacyManager] Clearing cache')
    this.privacyCache.clear()
  }
}

// Export singleton instance
export const privacyManager = new PrivacyManager()

// Make available globally for debugging
if (typeof window !== 'undefined') {
  (window as any).__privacyManager = privacyManager
}
