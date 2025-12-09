/**
 * Mark as Played Handler
 *
 * Toggles played status for episodes optimistically.
 * Sends RecordPlay command via WebSocket with toggled played value.
 */

import { Dispatcher } from './dispatch_events'

export class MarkPlayedHandler {
  private dispatcher: Dispatcher

  constructor() {
    this.dispatcher = new Dispatcher()
  }

  init(): void {
    document.addEventListener('click', (e: MouseEvent) => {
      const btn = (e.target as HTMLElement).closest('.mark-played-btn')
      if (btn instanceof HTMLButtonElement) {
        this.handleMarkPlayedClick(btn)
      }
    })
  }

  private async handleMarkPlayedClick(btn: HTMLButtonElement): Promise<void> {
    const feed = btn.dataset.feed
    const item = btn.dataset.item
    const isCurrentlyPlayed = btn.dataset.played === 'true'

    if (!feed || !item) return

    // Optimistic update
    this.toggleIcon(btn, !isCurrentlyPlayed)

    try {
      // Dispatch RecordPlay with toggled played value
      await this.dispatcher.recordPlay(feed, item, !isCurrentlyPlayed)
    } catch (error) {
      console.error('[MarkPlayed] Error:', error)
      // Rollback UI on error
      this.toggleIcon(btn, isCurrentlyPlayed)
    }
  }

  private toggleIcon(btn: HTMLButtonElement, isPlayed: boolean): void {
    btn.dataset.played = isPlayed ? 'true' : 'false'

    const svg = btn.querySelector('svg')
    if (!svg) return

    if (isPlayed) {
      // Show filled checkmark
      svg.setAttribute('fill', 'currentColor')
      svg.setAttribute('stroke', 'none')
      svg.className = 'w-5 h-5 text-green-600'
      svg.innerHTML = '<path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />'
    } else {
      // Show empty circle
      svg.setAttribute('fill', 'none')
      svg.setAttribute('stroke', 'currentColor')
      svg.className = 'w-5 h-5 text-gray-400 hover:text-gray-600'
      svg.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m7 0a9 9 0 11-18 0 9 9 0 0118 0z" />'
    }
  }
}

// Auto-init
const handler = new MarkPlayedHandler()
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => handler.init())
} else {
  handler.init()
}
