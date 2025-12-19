/**
 * Toast Notification System
 * Displays temporary notifications with auto-dismiss functionality
 *
 * Accessibility features:
 * - aria-live region for screen reader announcements
 * - role="alert" for urgent messages (error), role="status" for others
 * - Escape key to dismiss notifications
 * - Focus management for keyboard users
 */

interface Toast {
  id: string
  message: string
  type: 'info' | 'success' | 'error' | 'warning'
  duration?: number
}

// Human-readable labels for screen readers
const TYPE_LABELS: Record<Toast['type'], string> = {
  info: 'Information',
  success: 'Success',
  error: 'Error',
  warning: 'Warning'
}

class ToastManager {
  private toasts: Toast[] = []
  private container: HTMLDivElement | null = null
  private readonly maxVisible = 3
  private readonly defaultDuration = 5000 // 5 seconds

  constructor() {
    this.initializeContainer()
    this.setupKeyboardHandlers()
  }

  private initializeContainer(): void {
    // Create toast container if it doesn't exist
    let container = document.getElementById('toast-container') as HTMLDivElement
    if (!container) {
      container = document.createElement('div')
      container.id = 'toast-container'
      container.className = 'fixed top-4 left-4 z-50 space-y-2 max-w-sm pointer-events-none'

      // Accessibility: aria-live region for screen reader announcements
      container.setAttribute('role', 'region')
      container.setAttribute('aria-label', 'Notifications')
      container.setAttribute('aria-live', 'polite')
      container.setAttribute('aria-relevant', 'additions removals')

      document.body.appendChild(container)
    }
    this.container = container
  }

  /**
   * Setup keyboard event handlers for accessibility
   */
  private setupKeyboardHandlers(): void {
    document.addEventListener('keydown', (e) => {
      // Escape key dismisses the most recent toast
      if (e.key === 'Escape' && this.toasts.length > 0) {
        const latestToast = this.toasts[this.toasts.length - 1]
        this.dismiss(latestToast.id)
      }
    })
  }

  /**
   * Show a toast notification
   */
  show(message: string, type: 'info' | 'success' | 'error' | 'warning' = 'info', duration?: number): void {
    const id = `toast-${Date.now()}-${Math.random()}`
    const toast: Toast = {
      id,
      message,
      type,
      duration: duration || this.defaultDuration
    }

    this.toasts.push(toast)
    this.render()

    // Auto-dismiss after duration
    if (toast.duration) {
      setTimeout(() => this.dismiss(id), toast.duration)
    }
  }

  /**
   * Dismiss a specific toast
   */
  dismiss(id: string): void {
    this.toasts = this.toasts.filter(t => t.id !== id)
    this.render()
  }

  /**
   * Clear all toasts
   */
  clearAll(): void {
    this.toasts = []
    this.render()
  }

  /**
   * Render all visible toasts
   */
  private render(): void {
    if (!this.container) return

    // Clear container
    this.container.innerHTML = ''

    // Show only the first maxVisible toasts
    const visibleToasts = this.toasts.slice(0, this.maxVisible)

    visibleToasts.forEach((toast) => {
      const toastEl = this.createToastElement(toast)
      this.container!.appendChild(toastEl)
    })
  }

  /**
   * Create a toast DOM element with accessibility support
   */
  private createToastElement(toast: Toast): HTMLDivElement {
    const toastEl = document.createElement('div')
    toastEl.id = toast.id
    toastEl.className = this.getToastClasses(toast.type)

    // Accessibility: Use role="alert" for errors (urgent), role="status" for others
    const role = toast.type === 'error' ? 'alert' : 'status'
    toastEl.setAttribute('role', role)
    toastEl.setAttribute('aria-atomic', 'true')

    const bgColors = {
      info: 'bg-blue-50 border-blue-200',
      success: 'bg-green-50 border-green-200',
      error: 'bg-red-50 border-red-200',
      warning: 'bg-yellow-50 border-yellow-200'
    }

    const textColors = {
      info: 'text-blue-800',
      success: 'text-green-800',
      error: 'text-red-800',
      warning: 'text-yellow-800'
    }

    // Focus ring colors for dismiss button
    const focusColors = {
      info: 'focus:ring-blue-500',
      success: 'focus:ring-green-500',
      error: 'focus:ring-red-500',
      warning: 'focus:ring-yellow-500'
    }

    const icons = {
      info: '✓',
      success: '✓',
      error: '✕',
      warning: '⚠'
    }

    const typeLabel = TYPE_LABELS[toast.type]
    const dismissLabel = `Dismiss ${typeLabel.toLowerCase()} notification: ${toast.message}`

    toastEl.innerHTML = `
      <div class="pointer-events-auto rounded-lg border ${bgColors[toast.type]} p-4 shadow-lg animate-slide-in">
        <div class="flex items-start gap-3">
          <span class="text-lg font-bold ${textColors[toast.type]}" aria-hidden="true">${icons[toast.type]}</span>
          <span class="sr-only">${typeLabel}:</span>
          <p class="${textColors[toast.type]} text-sm font-medium">${this.escapeHtml(toast.message)}</p>
          <button
            type="button"
            data-toast-dismiss="${toast.id}"
            class="${textColors[toast.type]} ml-auto hover:opacity-70 transition-opacity focus:outline-none focus:ring-2 ${focusColors[toast.type]} focus:ring-offset-2 rounded"
            aria-label="${this.escapeHtml(dismissLabel)}"
          >
            <span aria-hidden="true">✕</span>
          </button>
        </div>
      </div>
    `

    // Add click handler for dismiss button (instead of inline onclick)
    const dismissBtn = toastEl.querySelector(`[data-toast-dismiss="${toast.id}"]`)
    if (dismissBtn) {
      dismissBtn.addEventListener('click', () => this.dismiss(toast.id))
    }

    return toastEl
  }

  /**
   * Get CSS classes for toast type
   */
  private getToastClasses(type: string): string {
    return 'pointer-events-auto'
  }

  /**
   * Escape HTML entities
   */
  private escapeHtml(text: string): string {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}

// Create global toast manager instance
const toastManager = new ToastManager()

// Add CSS animation for slide-in effect
const style = document.createElement('style')
style.textContent = `
  @keyframes slideIn {
    from {
      transform: translateX(-100%);
      opacity: 0;
    }
    to {
      transform: translateX(0);
      opacity: 1;
    }
  }

  .animate-slide-in {
    animation: slideIn 0.3s ease-out;
  }
`
document.head.appendChild(style)

export { toastManager, ToastManager }
