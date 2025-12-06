/**
 * Subscribe Flow with Privacy Check
 *
 * This module handles the subscribe button clicks and integrates privacy checks
 * before dispatching the subscribe action.
 */

import { privacyManager } from './privacy_manager'

export class SubscribeFlowHandler {
  constructor() {
    console.log('[SubscribeFlow] Initializing subscribe flow handler')
    this.setupListeners()
  }

  /**
   * Setup event delegation for subscribe buttons
   */
  private setupListeners(): void {
    // Use event delegation on document.body for subscribe buttons
    document.body.addEventListener('click', (e: MouseEvent) => {
      const target = e.target as HTMLElement
      const button = target.closest('.js-subscribe-with-privacy')

      if (button instanceof HTMLElement) {
        e.preventDefault()
        this.handleSubscribe(button)
      }
    })

    console.log('[SubscribeFlow] Event delegation setup complete')
  }

  /**
   * Handle subscribe button click with privacy check flow
   */
  private async handleSubscribe(button: HTMLElement): Promise<void> {
    const feed = button.getAttribute('data-feed')
    const subscribeUrl = button.getAttribute('data-subscribe-url')

    if (!feed || !subscribeUrl) {
      console.error('[SubscribeFlow] Missing data attributes', {
        feed,
        subscribeUrl,
      })
      return
    }

    // Disable button during process
    button.setAttribute('disabled', 'true')
    const originalText = button.textContent || ''
    button.textContent = 'Checking privacy...'

    try {
      console.log('[SubscribeFlow] Checking privacy for feed:', feed)

      // Check/request privacy
      const privacy = await privacyManager.ensurePrivacy(feed, 'subscribe')

      if (privacy === null) {
        // User cancelled or error
        console.log('[SubscribeFlow] Privacy choice failed or cancelled')
        button.removeAttribute('disabled')
        button.textContent = originalText
        return
      }

      console.log('[SubscribeFlow] Privacy confirmed:', privacy)

      // Privacy set - proceed with subscribe
      button.textContent = 'Subscribing...'

      // Create form and submit
      const form = document.createElement('form')
      form.method = 'POST'
      form.action = subscribeUrl

      // CSRF token
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
      if (csrfToken) {
        const csrfInput = document.createElement('input')
        csrfInput.type = 'hidden'
        csrfInput.name = '_csrf_token'
        csrfInput.value = csrfToken
        form.appendChild(csrfInput)
      }

      document.body.appendChild(form)
      console.log('[SubscribeFlow] Submitting form to:', subscribeUrl)
      form.submit()
    } catch (error) {
      console.error('[SubscribeFlow] Error during subscribe flow:', error)
      button.removeAttribute('disabled')
      button.textContent = originalText
      alert('Failed to process subscription. Please try again.')
    }
  }
}

// Auto-initialize when DOM is ready
const initializeSubscribeFlow = () => {
  console.log('[SubscribeFlow] DOM ready, initializing...')
  new SubscribeFlowHandler()
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeSubscribeFlow)
  console.log('[SubscribeFlow] Waiting for DOMContentLoaded event')
} else {
  // DOM is already loaded (e.g., script loaded after content)
  initializeSubscribeFlow()
}
